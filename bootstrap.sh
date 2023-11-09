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
	#sudo umount aosc-system/boot/efi
        sudo rm -rf aosc-system
        mkdir -p cache
	sudo aoscbootstrap \
		stable ./aosc-system http://localhost/debs/ \
		--config=/usr/share/aoscbootstrap/config/aosc-mainline.toml \
		-x \
		--arch=arm64 \
		-s \
			/usr/share/aoscbootstrap/scripts/reset-repo.sh \
		-s \
			/usr/share/aoscbootstrap/scripts/enable-nvidia-drivers.sh \
		-s \
			/usr/share/aoscbootstrap/scripts/enable-dkms.sh \
		--include-files "../asahi-base.lst"

        cd aosc-system

        sudo mkdir -p boot/efi/m1n1 etc/X11/xorg.conf.d

        sudo bash -c 'echo aosc > etc/hostname'

	sudo arch-chroot . apt update
	sudo arch-chroot . apt upgrade -y

        sudo cp ../../files/rc.local etc/rc.local
        sudo cp ../../files/30-modeset.conf etc/X11/xorg.conf.d/30-modeset.conf
        sudo cp ../../files/blacklist.conf etc/modprobe.d/
	sudo mkdir -pv usr/lib/dracut/{dracut.conf.d,modules.d}
	sudo cp ../../files/dracut/10-asahi.conf usr/lib/dracut/dracut.conf.d/10-asahi.conf
	sudo cp -r ../../files/dracut/modules.d usr/lib/dracut/

        sudo cp ../../files/grub etc/default/grub
        sudo -- perl -p -i -e 's/root:x:/root::/' etc/passwd

        sudo -- ln -s lib/systemd/systemd init
        sudo arch-chroot . apt update
        wget https://repo.aosc.io/debs/pool/kernel-m1/main/l/linux-kernel-m1-6.3.5_6.3.5-0_arm64.deb
        wget https://thomas.glanzmann.de/asahi/2023-03-20/m1n1_1.2.4-2_arm64.deb
        sudo arch-chroot . apt install -y ./linux-kernel-m1-6.3.5_6.3.5-0_arm64.deb ./m1n1_1.2.4-2_arm64.deb
        sudo arch-chroot . apt clean
        sudo rm var/lib/apt/lists/* || true
)
}

build_dd()
{
(
        rm -f media
        fallocate -l 6G media
        mkdir -p mnt
        mkfs.ext4 media
        tune2fs -O extents,uninit_bg,dir_index -m 0 -c 0 -i 0 media
        sudo mount -o loop media mnt
	sudo rsync -axv --info=progress2 aosc-system/ mnt/
        sudo rm -rf mnt/init mnt/boot/efi/m1n1
        sudo umount mnt
)
}

build_efi()
{
(
	rm -rf EFI
	mkdir -p EFI/BOOT
	mkdir -p EFI/grub
        export UUID=`blkid -s UUID -o value media`
	cat > grub.cfg <<EOF
search.fs_uuid $UUID root
linux (\$root)/boot/vmlinux-6.3.5-aosc-m1 root=UUID=$UUID rw net.ifnames=0 usbcore.autosuspend=-1
initrd (\$root)/boot/initramfs-6.3.5-aosc-m1.img
boot
EOF

CD_MODULES="
        all_video
        boot
        btrfs
        cat
        chain
        configfile
        echo
        efifwsetup
        efinet
        ext2
        fat
        font
        f2fs
        gettext
        gfxmenu
        gfxterm
        gfxterm_background
        gzio
        halt
        help
        hfsplus
        iso9660
        jfs
        jpeg
        keystatus
        loadenv
        loopback
        linux
        ls
        lsefi
        lsefimmap
        lsefisystab
        lssal
        memdisk
        minicmd
        normal
        ntfs
        part_apple
        part_msdos
        part_gpt
        password_pbkdf2
        png
        probe
        reboot
        regexp
        search
        search_fs_uuid
        search_fs_file
        search_label
        serial
        sleep
        smbios
        squash4
        test
        tpm
        true
        video
        xfs
        zfs
        zfscrypt
        zfsinfo
        fdt
        "

GRUB_MODULES="$CD_MODULES
        cryptodisk
        gcry_arcfour
        gcry_blowfish
        gcry_camellia
        gcry_cast5
        gcry_crc
        gcry_des
        gcry_dsa
        gcry_idea
        gcry_md4
        gcry_md5
        gcry_rfc2268
        gcry_rijndael
        gcry_rmd160
        gcry_rsa
        gcry_seed
        gcry_serpent
        gcry_sha1
        gcry_sha256
        gcry_sha512
        gcry_tiger
        gcry_twofish
        gcry_whirlpool
        luks
        luks2
        lvm
        mdraid09
        mdraid1x
        raid5rec
        raid6rec
        "

	sudo /usr/bin/grub-mkimage \
        	-O arm64-efi \
        	-o ./bootaa64.efi \
        	-p /EFI/aosc \
        	$GRUB_MODULES

        sudo cp -v ./bootaa64.efi EFI/BOOT/BOOTAA64.EFI
	sudo mkdir -pv EFI/aosc
	sudo cp -v ./grub.cfg EFI/aosc
)
}

build_asahi_installer_image()
{
(
        rm -rf aii
        mkdir -p aii/esp/m1n1
        cp -a EFI aii/esp/
        cp aosc-system/usr/lib/m1n1/boot.bin aii/esp/m1n1/boot.bin
        ln media aii/media
        cd aii
        zip -r9 ../aosc-base.zip esp media
)
}

# build_desktop_rootfs_image()
# {
# 	arch-chroot=aosc-system
# 	sudo mount proc-live -t proc ${arch-chroot}/proc
# 	sudo mount devpts-live -t devpts -o gid=5,mode=620 ${arch-chroot}/dev/pts || true
# 	sudo mount sysfs-live -t sysfs ${arch-chroot}/sys
# 	sudo arch-chroot aosc-system apt update
# 	sudo arch-chroot aosc-system apt install -y lightdm xserver-xorg deepin-desktop-environment-cli deepin-desktop-environment-core deepin-desktop-environment-base deepin-desktop-environment-extras libssl-dev firefox
# 	sudo arch-chroot aosc-system apt clean
# 	sudo rm aosc-system/var/lib/apt/lists/* || true

# 	sudo arch-chroot aosc-system useradd -m -s /bin/bash hiweed
# 	sudo arch-chroot aosc-system usermod -aG sudo hiweed
# 	echo "Set passwd for default user hiweed"
# 	sudo arch-chroot aosc-system bash -c 'echo -e "1\n1" | passwd hiweed'

# 	sudo umount -l ${arch-chroot}/proc
# 	sudo umount -l ${arch-chroot}/dev/pts
# 	sudo umount -l ${arch-chroot}/sys

# 	# resize rootfs
# 	fallocate -l 10G media
# 	e2fsck -f media
# 	resize2fs -p media

# 	sudo mount -o loop media mnt
# 	sudo rsync -axv --info=progress2 aosc-system/ mnt/
#         sudo rm -rf mnt/init mnt/boot/efi/m1n1
#         sudo umount mnt
	
# 	rm -rf aii
#         mkdir -p aii/esp/m1n1
#         cp -a EFI aii/esp/
#         cp aosc-system/usr/lib/m1n1/boot.bin aii/esp/m1n1/boot.bin
#         ln media aii/media
#         cd aii
#         zip -r9 ../deepin-desktop.zip esp media
# 

mkdir -p build
cd build

#build_rootfs
#build_dd
build_efi
build_asahi_installer_image
#build_desktop_rootfs_image
