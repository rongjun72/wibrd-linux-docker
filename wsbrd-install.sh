#!/bin/sh
# vim: set sw=4 expandtab:
#
# Copyright 2021, Silicon Labs
# SPDX-License-Identifier: Apache-2.0
# Main authors:
#     - Jérôme Pouiller <jerome.pouiller@silabs.com>
#
set -e

# This script expects to run as root
[ $(id -u) == 0 ]

apk add git openssh-client cmake ninja pkgconf linux-headers libnl3-dev elogind-dev cargo dbus-dev
##rm -rf ./wsbrd

if [ ! -d wsbrd ]; then
    echo "----------./wsbrd does not exist! git clone it"
    git clone --depth=10 --quiet --branch=merge_rcp https://github.com/rongjun72/wisun-br-linux ./wsbrd
else
    echo "----------./wsbrd already exist! use this local copy to compile"
fi
export CARGO_NET_GIT_FETCH_WITH_CLI=true
cmake -S ./wsbrd -B ./wsbrd-build -G Ninja
ninja -C ./wsbrd-build
ninja -C ./wsbrd-build install
echo -n "Built with wsbrd " >> /etc/issue
(git -C ./wsbrd describe --tags --dirty --match "*v[0-9].[0-9]*" || echo '<unknown version>') >> /etc/issue
