#!/usr/bin/bash -e

# Enabling some extra Bash scripting features.
shopt -s extglob

# Short hands for formatted output.
abwarn() { echo -e "[\e[33mWARN\e[0m]:  \e[1m$*\e[0m"; }
aberr()  { echo -e "[\e[31mERROR\e[0m]: \e[1m$*\e[0m"; }
abinfo() { echo -e "[\e[96mINFO\e[0m]:  \e[1m$*\e[0m"; }
abdbg()  { echo -e "[\e[32mDEBUG\e[0m]: \e[1m$*\e[0m"; }

build_rootfs() {
	abinfo "${FUNCNAME[0]}: Performing pre-build clean up ($1) ..."
        rm -rf aosc-system-$1

	abinfo "${FUNCNAME[0]}: Generating system release ($1) ..."
	aoscbootstrap \
		stable ./aosc-system-$1 http://localhost/debs/ \
		--config=/usr/share/aoscbootstrap/config/aosc-mainline.toml \
		-x \
		--arch=arm64 \
		-s \
			/usr/share/aoscbootstrap/scripts/reset-repo.sh \
		-s \
			/usr/share/aoscbootstrap/scripts/enable-dkms.sh \
		--include-files ../asahi-$1.lst
}

build_postinst() {
	abinfo "${FUNCNAME[0]}: Running post-generation steps ($1) ..."
	cd aosc-system-$1
        mkdir -pv \
		boot/efi/m1n1 \
		etc/X11/xorg.conf.d

	abinfo "${FUNCNAME[0]}: Setting hostname ($1) ..."
        echo aosc-asahi > etc/hostname

	abinfo "${FUNCNAME[0]}: Installing device initialisation scripts ($1) ..."
        install -Dvm644 ../../files/30-modeset.conf \
		etc/X11/xorg.conf.d/30-modeset.conf
        install -Dvm644 ../../files/blacklist.conf \
		etc/modprobe.d/
	install -Dvm644 ../../files/dracut/10-asahi.conf \
		usr/lib/dracut/dracut.conf.d/10-asahi.conf
	cp -rv ../../files/dracut/modules.d \
		usr/lib/dracut/

	abinfo "${FUNCNAME[0]}: Installing kernel and bootloader data ($1) ..."
        arch-chroot . \
		apt update
	wget \
		https://repo.aosc.io/debs/pool/kernel-m1/main/l/linux-kernel-m1-6.3.5_6.3.5-0_arm64.deb \
		https://repo.aosc.io/debs/pool/kernel-m1/main/m/m1n1_1.4.6-0_arm64.deb \
		https://repo.aosc.io/debs/pool/kernel-m1/main/u/uboot-asahi_2023.07.02+3-0_arm64.deb
        arch-chroot . \
		apt install -y \
			./linux-kernel-m1-6.3.5_6.3.5-0_arm64.deb \
			./m1n1_1.4.6-0_arm64.deb \
			./uboot-asahi_2023.07.02+3-0_arm64.deb

	abinfo "${FUNCNAME[0]}: Assembling m1n1 bootloader image ($1) ..."
	# Note: The m1n1.bin bootloader image is a concat-ed image with m1n1,
	# device trees (from Kernel), u-boot, and bootloader configuration bundled.
	#
	# Ref: https://github.com/AsahiLinux/asahi-scripts/blob/4788327780a583b7ed701bc400394816b9792c53/update-m1n1#L51
	cat usr/lib/asahi-boot/m1n1.bin >> boot/boot.bin
	cat usr/lib/aosc-os-arm64-boot/dtbs-kernel-6.3.5-aosc-m1/*.dtb >> boot/boot.bin
	gzip -c usr/lib/uboot-asahi/u-boot-nodtb.bin >> boot/boot.bin
	cat etc/m1n1.conf >> boot/boot.bin

	abinfo "${FUNCNAME[0]}: Cleaning up ($1) ..."
        arch-chroot . apt clean
	rm -v ./*.deb
        rm -v var/lib/apt/lists/!(auxfiles|partial)

	cd ..
}

build_sys_image() {
	abinfo "${FUNCNAME[0]}: Performing pre-build clean up ($1) ..."
	umount -Rf mnt_$1 || true
        rm -fv media_$1

	abinfo "${FUNCNAME[0]}: Detecting image size ..."
	# Note: ext4 reserves 5% by default, giving it 50% for collaterals.
	# CAUTION: image size should be multiple of 4,096 (4 KiB).
	# According to [1], a image size not divisible to 4,096 will cause
	# EINVAL during the dd process. The image size is not necessarily
	# divisible to 16MiB, but it should be divisible to logical block
	# size, which is 4 KiB.
	# [1]: https://github.com/AsahiLinux/asahi-installer/pull/236#issuecomment-1805853152
	local image_size="$(echo "scale=0;v=$(du -sb aosc-system-$1 | cut -f1)*1.5;b=4096;v=(v+b)/b;v*b" | bc)"
	abinfo "${FUNCNAME[0]}: Determined image size as $image_size Bytes ..."

	abinfo "${FUNCNAME[0]}: Generating image ($1) ..."
        fallocate -l ${image_size} media_$1

	abinfo "${FUNCNAME[0]}: Preparing filesystem ($1) ..."
        mkfs.ext4 media_$1

	abinfo "${FUNCNAME[0]}: Preparing mount points ($1) ..."
	mkdir -pv mnt_$1
        mount -o loop media_$1 mnt_$1

	abinfo "${FUNCNAME[0]}: Transferring files to system image ($1) ..."
	rsync -aAX --info=progress2 aosc-system-$1/ mnt_$1/

	abinfo "${FUNCNAME[0]}: Performing post-build clean up ($1) ..."
        umount -Rf mnt_$1
}

build_grub_efi_image() {
	abinfo "${FUNCNAME[0]}: Performing pre-build clean up ($1) ..."
	rm -rfv EFI

	abinfo "${FUNCNAME[0]}: Preparing to build GRUB EFI image ($1) ..."
	mkdir -p EFI/{BOOT,aosc,grub}
        local GRUB_UUID=`blkid -s UUID -o value media_$1`

	echo "Generating grub.cfg ($1) ..."
	cat > grub.cfg << EOF
search.fs_uuid $GRUB_UUID root
linux (\$root)/boot/vmlinux-6.3.5-aosc-m1 root=UUID=$GRUB_UUID rw usbcore.autosuspend=-1
initrd (\$root)/boot/initramfs-6.3.5-aosc-m1.img
boot
EOF

# Debian: see https://salsa.debian.org/philh/grub2/-/blob/dgit/sid/debian/build-efi-images
# Integrate as many modules as possible, in order to make GRUB discover partitions by UUID
GRUB_MODULES="
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

	abinfo "${FUNCNAME[0]}: Generating GRUB image ($1) ..."
	/usr/bin/grub-mkimage \
        	-O arm64-efi \
        	-o ./bootaa64.efi \
        	-p /EFI/aosc \
        	$GRUB_MODULES

	abinfo "${FUNCNAME[0]}: Installing GRUB image ($1) ..."
        install -Dvm644 -v ./bootaa64.efi EFI/BOOT/BOOTAA64.EFI
	install -Dvm644 -v ./grub.cfg EFI/aosc
}

build_asahi_installer_image() {
	abinfo "${FUNCNAME[0]}: Performing pre-build clean up ($1) ..."
	rm -rfv aii

	abinfo "${FUNCNAME[0]}: Assembling files ($1) ..."
        install -Dvm644 aosc-system-$1/boot/boot.bin \
		aii/esp/m1n1/boot.bin
	cp -av EFI \
		aii/esp/
        ln -v media_$1 \
		aii/media

	abinfo "${FUNCNAME[0]}: Generating system release archive ($1) ..."
	cd aii
        zip -r9 ../aosc-os_${1}_$(date +%Y%m%d)_arm64+asahi.zip esp media
	cd ..
	sha256sum aosc-os_${1}_$(date +%Y%m%d)_arm64+asahi.zip \
		>> aosc-os_${1}_$(date +%Y%m%d)_arm64+asahi.zip.sha256sum
}

abinfo "Creating directories ..."
mkdir -pv build
cd build

abinfo "Setting time zone to UTC ..."
export TZ=UTC

for i in "$@"; do
	abinfo "Genrating system release ($i) ..."
	build_rootfs $i
	build_postinst $i
	build_sys_image $i
	build_grub_efi_image $i
	build_asahi_installer_image $i
done
