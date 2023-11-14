#!/bin/bash -e
# SPDX-License-Identifier: MIT

export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

export REPO_BASE="https://repo.aosc.io/aosc-os/os-arm64/asahi"
export VERSION_FLAG="https://cdn.asahilinux.org/installer/latest"
export INSTALLER_BASE="https://cdn.asahilinux.org/installer"
export INSTALLER_DATA="${REPO_BASE}/installer_data.json"

TMP="/tmp/asahi-install"

echo
echo "------------------------------------------------------"
echo "Welcome to AOSC OS Installer for Apple Silicon Devices"
echo "------------------------------------------------------"

if [ -e "$TMP" ]; then
	mv "$TMP" "$TMP-$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$TMP"
cd "$TMP"

echo "... Querying asahi-installer versions ..."
PKG_VER="$(curl --no-progress-meter -L $VERSION_FLAG)"

echo "... Found asashi-installer version: $PKG_VER ..."

echo "... Downloading asahi-installer ..."
PKG="installer-$PKG_VER.tar.gz"
curl --no-progress-meter -L -o "$PKG" "$INSTALLER_BASE/$PKG"
if [ $? != 0 ]; then
	echo "Error downloading installer_data.json: $?"
	exit 1
fi

echo "... Extracting asahi-installer ..."

tar xf "$PKG"
if [ $? != 0 ]; then
	echo "Error extracting asahi-installer: $?"
	exit 1
fi

echo "------------------------------------------------------"
echo "             Initializing asahi-installer             "
echo "------------------------------------------------------"

if [ "$USER" != "root" ]; then
	echo "asahi-installer requires administrative rights."
	echo "Please enter your administrator password when prompted."
	exec caffeinate -dis sudo -E ./install.sh "$@"
else
	exec caffeinate -dis ./install.sh "$@"
fi
