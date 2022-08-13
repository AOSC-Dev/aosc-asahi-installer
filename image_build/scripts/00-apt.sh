apt-get remove -y linux-kernel*
apt-get update
apt-get install -y grub

wget -O kernel.deb "https://repo.aosc.io/misc/linux-kernel-asahi-5.18.0_5.18.0-0_arm64.deb"
dpkg -i ./kernel.deb
