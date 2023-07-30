#!/usr/bin/env bash

# SPDX-License-Identifier: MIT

set -o errexit
set -o nounset
set -o pipefail
set -o xtrace

cd "$(dirname "$0")"

unset LC_CTYPE
unset LANG

build_rootfs()
{
(
        sudo rm -rf aosc-system
        mkdir -p cache
	sudo aoscbootstrap stable ./aosc-system http://192.168.1.5:2345/aosc/debs/ --arch=arm64 --config=/usr/share/aoscbootstrap/config/aosc-mainline.toml

        cd aosc-system

        sudo mkdir -p boot/efi/m1n1 etc/X11/xorg.conf.d

        sudo bash -c 'echo aosc > etc/hostname'

	sudo chroot . apt update
	sudo chroot . apt upgrade -y

        sudo cp ../../files/rc.local etc/rc.local
        sudo cp ../../files/30-modeset.conf etc/X11/xorg.conf.d/30-modeset.conf
        sudo cp ../../files/blacklist.conf etc/modprobe.d/

        sudo cp ../../files/grub etc/default/grub
        sudo -- perl -p -i -e 's/root:x:/root::/' etc/passwd

        sudo -- ln -s lib/systemd/systemd init
        sudo chroot . apt update
        wget https://repo.aosc.io/debs/pool/kernel-m1/main/l/linux-kernel-m1-6.3.5_6.3.5-0_arm64.deb
        wget https://thomas.glanzmann.de/asahi/2023-03-20/m1n1_1.2.4-2_arm64.deb
        sudo chroot . apt install -y ./linux-kernel-m1-6.3.5_6.3.5-0_arm64.deb ./m1n1_1.2.4-2_arm64.deb
        sudo chroot . apt clean
        sudo rm var/lib/apt/lists/* || true
)
}

build_dd()
{
(
        rm -f media
        fallocate -l 3G media
        mkdir -p mnt
        mkfs.ext4 media
        tune2fs -O extents,uninit_bg,dir_index -m 0 -c 0 -i 0 media
        sudo mount -o loop media mnt
	sudo rsync -axv --info=progress2 testing/ mnt/
        sudo rm -rf mnt/init mnt/boot/efi/m1n1
        sudo umount mnt
)
}

build_efi()
{
(
        rm -rf EFI
        mkdir -p EFI/boot EFI/grub
	cp testing/usr/lib/grub/arm64-efi/monolithic/grubaa64.efi EFI/boot/bootaa64.efi
        export INITRD=`ls -1 testing/boot/ | grep initrd`
        export VMLINUZ=`ls -1 testing/boot/ | grep vmlinuz`
        export UUID=`blkid -s UUID -o value media`
        cat > EFI/grub/grub.cfg <<EOF
search.fs_uuid ${UUID} root
linux (\$root)/boot/${VMLINUZ} root=UUID=${UUID} rw net.ifnames=0 usbcore.autosuspend=-1
initrd (\$root)/boot/${INITRD}
boot
EOF
)
}

build_asahi_installer_image()
{
(
        rm -rf aii
        mkdir -p aii/esp/m1n1
        cp -a EFI aii/esp/
        cp testing/usr/lib/m1n1/boot.bin aii/esp/m1n1/boot.bin
        ln media aii/media
        cd aii
        zip -r9 ../aosc-base.zip esp media
)
}

# build_desktop_rootfs_image()
# {
# 	CHROOT=testing
# 	sudo mount proc-live -t proc ${CHROOT}/proc
# 	sudo mount devpts-live -t devpts -o gid=5,mode=620 ${CHROOT}/dev/pts || true
# 	sudo mount sysfs-live -t sysfs ${CHROOT}/sys
# 	sudo chroot testing apt update
# 	sudo chroot testing apt install -y lightdm xserver-xorg deepin-desktop-environment-cli deepin-desktop-environment-core deepin-desktop-environment-base deepin-desktop-environment-extras libssl-dev firefox
# 	sudo chroot testing apt clean
# 	sudo rm testing/var/lib/apt/lists/* || true

# 	sudo chroot testing useradd -m -s /bin/bash hiweed
# 	sudo chroot testing usermod -aG sudo hiweed
# 	echo "Set passwd for default user hiweed"
# 	sudo chroot testing bash -c 'echo -e "1\n1" | passwd hiweed'

# 	sudo umount -l ${CHROOT}/proc
# 	sudo umount -l ${CHROOT}/dev/pts
# 	sudo umount -l ${CHROOT}/sys

# 	# resize rootfs
# 	fallocate -l 10G media
# 	e2fsck -f media
# 	resize2fs -p media

# 	sudo mount -o loop media mnt
# 	sudo rsync -axv --info=progress2 testing/ mnt/
#         sudo rm -rf mnt/init mnt/boot/efi/m1n1
#         sudo umount mnt
	
# 	rm -rf aii
#         mkdir -p aii/esp/m1n1
#         cp -a EFI aii/esp/
#         cp testing/usr/lib/m1n1/boot.bin aii/esp/m1n1/boot.bin
#         ln media aii/media
#         cd aii
#         zip -r9 ../deepin-desktop.zip esp media
# }

mkdir -p build
cd build

build_rootfs
build_dd
build_efi
build_asahi_installer_image
# build_desktop_rootfs_image
