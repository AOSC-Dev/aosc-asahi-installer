#!/bin/sh
# SPDX-License-Identifier: MIT

set -e

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

export VERSION_FLAG=https://cdn.asahilinux.org/installer/latest
export INSTALLER_BASE=https://cdn.asahilinux.org/installer
export INSTALLER_DATA=https://raw.githubusercontent.com/AOSC-Dev/aosc-asahi-installer/master/data/installer_data.json
export REPO_BASE=https://repo.aosc.io/misc
PKG=installer.tar.gz

#TMP="$(mktemp -d)"
TMP=/tmp/asahi-install

echo
echo "Bootstrapping installer:"

mkdir -p "$TMP"
cd "$TMP"

echo "  Downloading..."

curl --no-progress-meter -L -O "$INSTALLER_BASE/$PKG"
curl --no-progress-meter -L -O "$INSTALLER_DATA"

echo "  Extracting..."

tar xf "$PKG"

echo "  Initializing..."
echo

if [ "$USER" != "root" ]; then
    echo "The installer needs to run as root."
    echo "Please enter your sudo password if prompted."
    exec caffeinate -dis sudo -E ./install.sh "$@"
else
    exec caffeinate -dis ./install.sh "$@"
fi

