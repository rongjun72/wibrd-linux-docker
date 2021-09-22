<table border="0">
  <tr>
    <td align="left" valign="middle">
    <h1>Wi-SUN Border Router Container</h1>
  </td>
  <td align="left" valign="middle">
    <a href="https://wi-sun.org/">
      <img src="https://wi-sun.org/wp-content/uploads/Wi-SUN-Main-Logo.png"  title="Wi-SUN" alt="Wi-SUN Logo" width="300"/>
    </a>
  </td>
  </tr>
</table>

In a Wi-SUN network, the Border Router (BR) is in charge of the management of
the network (authentication, routing, etc...) and providing internet connectivity to the
network.

To simplify the deployment and network configuration, all the work is done inside a Docker container. It
aims to run on a Raspberry Pi, but it should work on any Linux host.

This implementation relies on an external EFR (Silicon Labs radio device)
flashed with Silicon Labs Wi-SUN RCP firmware. The EFR has to be connected to
the host using USB.  The docker will see it as a serial (UART) connection. In
order to simplify deployment, this image is able to flash the correct firmware
(see [Using the JTAG link](#using-the-jtag-link)).

The use of a network with IPv6 connectivity is encouraged. If IPv6 is not available,
you will have to use "local" or "site-local" modes (these modes have some
pitfalls, see below).

# Installation

A pre-build image of the container is not (yet) available. You have to build an
image yourself.

Install docker:

    sudo apt-get install docker.io

Ensure that your current user is allowed to run docker (you will have to log out
and back in for this to take effect!):

    sudo usermod -aG docker pi

Go to this repository and build the image with:

    DOCKER_BUILDKIT=1 docker build --build-arg "GIT_DESCRIBE=$(git describe --tag --match v*)" --ssh default -t wisun-img .

Note that `DOCKER_BUILDKIT` and `--ssh` are necessary to authenticate to the
Github private git repository. If this step fail, check the section [I have an
error while retrieving `wsbrd`
sources](#i-have-an-error-while-retrieving-wsbrd-sources)

Then, you may save a bunch of bytes by removing the build environment and only
keeping the final image:

    docker image prune

If you have an IPv6 network, create a macvlan interface to leverage it (replace
`eth0` by the name of you physical network interface):

    sudo docker network create -d macvlan -o parent=eth0 wisun-net

Launch image
------------

Before you continue, you have to be aware that if no IPv6 network is detected
(and no command line option prevents it), this image will advertise a network
configuration. It may impact the other hosts on your network. To avoid any
inconvenience, we suggest to work with an isolated network. See also [Can this
image breaks my local network?](#can-this-image-breaks-my-local-network)

Check that the Wi-SUN BR device is available on `/dev/ttyACM0` (or pass the
correct device name to the guest with `-d`).

Launch your image using:

    docker run -ti --privileged --rm --network=wisun-net --name=wisun-vm wisun-img

From now on, your Wi-SUN nodes should be able to interact with your IPv6
network.

Note that the container accepts a few options which you can list with:

    docker run -ti --privileged --rm wisun-img --help

You may want to open a shell into the container:

    docker exec -ti wisun-vm sh

Advanced users may want to drop the `--rm` option and work with `docker start`,
`docker stop`, etc...

Using the JTAG link
-------------------

The docker image is able to use the JTAG link available with Silicon Labs chips
to configure the Wi-SUN parameters, flash the radio board or get chip traces.

You can start the container with "--flash -" to flash the connected board with
the built-in firmware. This firmware should work with most of Silicon Labs radio
boards:

    docker run -ti --privileged --rm --network=wisun-net --name=wisun-vm wisun-img --flash -

You also replace "-" by another path to flash your custom firmware.

You can also use the JTAG link to retrieve traces from the radio board. You can
either pass `-T` to `docker run` or start the traces afterward with command
wisun-device-traces:

    docker exec -ti wisun-vm wisun-device-traces

Bugs and limitations
--------------------

### I have an error while retrieving `wsbrd` sources

`wsbrd` is hosted on a private repository. You have to have a running
`ssh-agent` with your key inside to access the repository.

To see if your environment is correct, check if your key appears in the output
of:

    ssh-add -l

The process to work with ssh keys is lengthy described in [GitHub
documentation][1].

To summary, if `ssh-add` cannot open a connection to your authentication agent,
you can run a local agent with:

    eval $(ssh-agent)

If the agent has no identities, ensure that your key is available in` ~/.ssh`
and register them with:

    ssh-add

Finally, check you are able to clone the repository:

    git clone ssh://git@github.com/SiliconLabs/wisun-br-linux

If you still don't have access, maybe your key does not match the key of your
Gihub account or you don't have permission to access the `wisun-br-linux`
repository.

[1]: https://docs.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh

### I want to use this architecture for production

By default, this docker uses a method called Neighbor Discovery Proxy (NDP
Proxy). It works with most IPv6 network topologies without touching the network
infra.  However, it does not scale very well and you may find limitations in
corner cases. For production, prefer the subnet mode (aka Prefix Delegation) or
even better use DHCPv6-PD protocol (not presented in this docker).

### I have no IPv6 network

This project does not aim to provide IPv6 connectivity. If your ISP does not
provide IPv6, you can either:

  - get an equipment providing IPv6 through NAT64 or 6to4
  - get an equipment advertising a site-local IPv6 prefix (eg. fd01::/64). You
    can do that using radvd with any standard Linux.

### The container does not detect my IPv6 network

The container relies on Router Advertisements. If your network use DHCPv6, or
does not have Router Advertisement for any reason, the container won't detect
the network.

### Cannot reach (IPv4) internet from the container

This happens when you use the macvlan driver. It is necessary to get an IP from
the DHCP server of the host network. Just add `-D` when you run the docker to
run a DHCP client:

    docker run -ti --privileged --rm --network=wisun-net --name=wisun-vm wisun-img -D

### I have restarted my docker image and I can't ping my Wi-SUN device anymore

The proxy creates the necessary routes when it receives a Neighbor Solicitation.
Your host has probably cached this information. The easiest way to fix that is
to flush the neighbor information of your host with:

    ip -6 neigh flush dev eth0

Alternatively you can force a neighbor discovery on your Wi-SUN node:

    ndisc6 2a01:e35:2435:66a0:202:f7ff:fef0:0 eth0


### Wi-SUN can reach outside network, but can't reach docker host

It is a [limitation of the macvlan interface][2]. This situation is actually not
an error — it is the defined behavior of macvtap. Due to the way in which the
host's physical Ethernet is attached to the macvtap bridge, traffic into that
bridge from the guests that is forwarded to the physical interface cannot be
bounced back up to the host's IP stack. Additionally, traffic from the host's IP
stack that is sent to the physical interface cannot be bounced back up to the
macvtap bridge for forwarding to the guests.

There are several ways to work around the problem. The easiest way probably is
to use a secondary physical network interface exclusively for the guest.

    dhcpcd --release eth1
    docker network create -d macvlan -o parent=eth1 wisun-net
    ip link set dev eth1 up
    docker run -ti --privileged --rm --network=wisun-net --name=wisun-vm wisun-img


[2]: https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Virtualization_Host_Configuration_and_Guest_Installation_Guide/App_Macvtap.html

### Unable to launch the container on my Windows workstation

This project has not yet been tested on windows hosts. It seems it should work
as soon as you use Windows Subsystem for Linux (WSL2) and the USB-UART of the
Wi-SUN BR is handled by WSL2. In other words, you should see /dev/ttyUSB0 on
WSL2.

### I have re-plugged the serial interface and nothings work anymore

The docker container does not (yet) support device hot-plugging. You have to
restart the docker container if you unplug the gateway.

### When I try to ping from my Wi-SUN Device, the reply is transmitted after 5s of latency

When using the proxy, it takes a few seconds to establish connection the first
time a end device tries to access the outside. The problem is [ndppd does not
receive locally generated neighbor solicitation][3] (A). The system unlocks when
a solicitation comes from outside (B).

        tun0  2 1.806167960 2a01:e35:2435:66a0:20d:6fff:fe20:c096 → 2a00:1450:4007:809::200e ICMPv6 104 Echo (ping) request id=0x0001, seq=0, hop limit=63
        eth0  1 0.000000000 2a01:e35:2435:66a0:20d:6fff:fe20:c096 → 2a00:1450:4007:809::200e ICMPv6 118 Echo (ping) request id=0x0001, seq=0, hop limit=62
        eth0  2 0.007452561 2a00:1450:4007:809::200e → 2a01:e35:2435:66a0:20d:6fff:fe20:c096 ICMPv6 118 Echo (ping) reply id=0x0001, seq=0, hop limit=118 (request in 1)
    (A) eth0  3 0.007558306 fe80::42:acff:fe13:2 → ff02::1:ff20:c096 ICMPv6 86 Neighbor Solicitation for 2a01:e35:2435:66a0:20d:6fff:fe20:c096 from 02:42:ac:13:00:02
    (A) eth0  4 1.016063581 fe80::42:acff:fe13:2 → ff02::1:ff20:c096 ICMPv6 86 Neighbor Solicitation for 2a01:e35:2435:66a0:20d:6fff:fe20:c096 from 02:42:ac:13:00:02
    (A) eth0  5 2.039971376 fe80::42:acff:fe13:2 → ff02::1:ff20:c096 ICMPv6 86 Neighbor Solicitation for 2a01:e35:2435:66a0:20d:6fff:fe20:c096 from 02:42:ac:13:00:02
        eth0  6 3.060057826 2a01:e35:2435:66a0:42:acff:fe13:2 → 2a00:1450:4007:809::200e ICMPv6 166 Destination Unreachable (Address unreachable)
    (B) eth0  7 5.043717586 fe80::224:d4ff:fea3:4493 → 2a01:e35:2435:66a0:20d:6fff:fe20:c096 ICMPv6 86 Neighbor Solicitation for 2a01:e35:2435:66a0:20d:6fff:fe20:c096 from 00:24:d4:a3:44:93
        eth0  8 5.043761372 fe80::42:acff:fe13:2 → fe80::224:d4ff:fea3:4493 ICMPv6 174 Redirect
        eth0  9 5.043782371 fe80::42:acff:fe13:2 → ff02::1:ff20:c096 ICMPv6 86 Neighbor Solicitation for 2a01:e35:2435:66a0:20d:6fff:fe20:c096 from 02:42:ac:13:00:02
    (B) tun0  3 6.850276506 fe80::10c3:41bf:aa66:69a3 → ff02::1:ff20:c096 ICMPv6 72 Neighbor Solicitation for 2a01:e35:2435:66a0:20d:6fff:fe20:c096 from 00:00:00:00:00:00
        tun0  4 6.870837671 fe80::202:f7ff:fef0:0 → fe80::10c3:41bf:aa66:69a3 ICMPv6 72 Neighbor Advertisement 2a01:e35:2435:66a0:20d:6fff:fe20:c096 (sol) is at 00:02:f7:f0:00:00
        eth0 10 5.067321429 fe80::42:acff:fe13:2 → fe80::224:d4ff:fea3:4493 ICMPv6 86 Neighbor Advertisement 2a01:e35:2435:66a0:20d:6fff:fe20:c096 (rtr, sol) is at 02:42:ac:13:00:02

The subnet mode does not suffers of this limitation.

[3]: https://github.com/DanielAdolfsson/ndppd/issues/69

### Can this image breaks my local network?

When this image start in `site_local` mode, it will advertise network
configuration. The other hosts on the local network will also receive this
configuration and will use it. From here, there are two situations:

  1. The hosts already have a valid IPv6 configuration. The new configuration
     will probably break the current one.

  2. The other hosts only use IPv4. IPv4 traffic won't be impacted. However,
     some DNS records may contain IPv4 and IPv6 fields. In this case, the
     applications may try to use the new shiny IPv6 configuration. The hosts
     will forward IPv6 traffic to the docker image. The image will reply with an
     error. Then, if we are lucky (AFAIK the most common case), the application
     will fallback to IPv4 and it will work. Else, if we are not lucky, the
     application will just stop here with a failure.


If you don't enforce `site_local`, the image will try to detect existent IPv6
network. `site_local` will be started only no IPv6 network has been detected. So
the first scenario is unlikely to happen.

Anyway, if you use `site_local` mode, we recommend to use a dedicated network.

Further improvements
--------------------

- Replace radvd with a small RS/RA proxy. nd-proxy.c seems to mostly do the job,
  but:

   1. for an unknown reason, it does not receive RS from tun0 and does not send
      RA to tun0 (while radvd is able to do that very well)
   2. it is written in C++

- Provide an example of Prefix Delegation and DHCPv6-PD

- Docker does not yet support '--ipam-driver=dhcp --ipam-opt dhcp_interface=eth0'
