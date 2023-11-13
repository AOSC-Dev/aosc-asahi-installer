#!/bin/sh
# SPDX-License-Identifier: MIT

set -e

export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

export REPO_BASE="https://repo.aosc.io/aosc-os/os-arm64/asahi"
export VERSION_FLAG="https://cdn.asahilinux.org/installer/latest"
export INSTALLER_BASE="https://cdn.asahilinux.org/installer"
export INSTALLER_DATA="${REPO_BASE}/installer_data.json"

# Short hands for formatted output.
abwarn() { echo -e "[\e[33mWARN\e[0m]:  \e[1m$*\e[0m"; }
aberr()  { echo -e "[\e[31mERROR\e[0m]: \e[1m$*\e[0m"; }
abinfo() { echo -e "[\e[96mINFO\e[0m]:  \e[1m$*\e[0m"; }
abdbg()  { echo -e "[\e[32mDEBUG\e[0m]: \e[1m$*\e[0m"; }

TMP=/tmp/asahi-install

echo "------------------------------------------------------"
echo "Welcome to AOSC OS Installer for Apple Silicon Devices"
echo "------------------------------------------------------"

if [ -e "$TMP" ]; then
	mv "$TMP" "$TMP-$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$TMP"
cd "$TMP"

echo
abinfo "... Querying asahi-installer versions ..."
echo

PKG_VER="$(curl --no-progress-meter -L "$VERSION_FLAG")"
abinfo "... Found asashi-installer version: $PKG_VER ..."

PKG="installer-$PKG_VER.tar.gz"

abinfo "... Downloading asahi-installer ..."

curl --no-progress-meter -L -o "$PKG" "$INSTALLER_BASE/$PKG" || \
	aberr "Error downloading installer_data.json: $?"

echo
abinfo "... Extracting asahi-installer ..."
echo

tar xf "$PKG" || \
	aberr "Error extracting asahi-installer: $?"

echo
abinfo "... Initializing asahi-installer ..."
echo

if [ "$USER" != "root" ]; then
	abwarn "asahi-installer requires administrative rights."
	abwarn "Please enter your administrator password when prompted."
	exec caffeinate -dis sudo -E ./install.sh "$@"
else
	exec caffeinate -dis ./install.sh "$@"
fi
