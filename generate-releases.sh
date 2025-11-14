#!/usr/bin/bash -e

# Enabling some extra Bash scripting features.
shopt -s extglob

# If local testing is enabled, do not compress the archive.
if [ "$LOCAL_TESTING" = "1" ] ; then
	ZIP_ARG="-r"
else
	ZIP_ARG="-r9"
fi

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
		--branch stable \
		--target ./aosc-system-$1 \
		--mirror ${REPO:-https://repo.aosc.io}/debs/ \
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

	abinfo "${FUNCNAME[0]}: Setting hostname ($1) ..."
	echo aosc-asahi > etc/hostname

	abinfo "${FUNCNAME[0]}: Creating devena-firstboot initramfs image ..."
	arch-chroot . \
		create-devena-initrd

	abinfo "${FUNCNAME[0]}: Assembling m1n1 bootloader image ($1) ..."
	# Note: The m1n1.bin bootloader image is a concat-ed image with m1n1,
	# device trees (from Kernel), u-boot, and bootloader configuration bundled.
	#
	# Ref: https://github.com/AsahiLinux/asahi-scripts/blob/4788327780a583b7ed701bc400394816b9792c53/update-m1n1#L51
	ls -l usr/lib/asahi-boot/m1n1.bin
	cat usr/lib/asahi-boot/m1n1.bin >> boot/boot.bin
	ls -l usr/lib/aosc-os-arm64-boot/dtbs-kernel-$(basename $(ls -d usr/lib/modules/*-aosc-asahi | sort -rV | head -1 ))/*.dtb
	cat usr/lib/aosc-os-arm64-boot/dtbs-kernel-$(basename $(ls -d usr/lib/modules/*-aosc-asahi | sort -rV | head -1 ))/*.dtb >> boot/boot.bin
	ls -l usr/lib/asahi-boot/u-boot-nodtb.bin
	gzip -c usr/lib/asahi-boot/u-boot-nodtb.bin >> boot/boot.bin
	# FIXME: m1n1 does not function properly with configuration attached.
	# A node in device tree called 'chosen/asahi,efi-boot-partition' will
	# not appear in the DT if we have the configuration attached to m1n1.
	# ls -l etc/m1n1.conf
	# cat etc/m1n1.conf >> boot/boot.bin

	abinfo "${FUNCNAME[0]}: Generating initramfs image ($1) ..."
	arch-chroot . \
		update-initramfs

	abinfo "Enabling PipeWire ..."
	mkdir -pv etc/systemd/user/sockets.target.wants \
		etc/systemd/user/pipewire.service.wants
	ln -svf /usr/lib/systemd/user/pipewire.socket \
		etc/systemd/user/sockets.target.wants/pipewire.socket
	ln -svf /usr/lib/systemd/user/pipewire-pulse.socket \
		etc/systemd/user/sockets.target.wants/pipewire-pulse.socket
	ln -svf /usr/lib/systemd/user/wireplumber.service \
		etc/systemd/user/pipewire.service.wants/wireplumber.service

	abinfo "${FUNCNAME[0]}: Resetting root home ($1) ..."
	rm -rv root/.*
	cp -av etc/skel/.* root/

	abinfo "Resetting machine-id ..."
	echo "uninitialized" > etc/machine-id

	cd ..
}

build_sys_image() {
	abinfo "${FUNCNAME[0]}: Performing pre-build clean up ($1) ..."
	umount -Rf rootfs_$1 || true
	rm -fv rootfs_$1

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
	fallocate -l ${image_size} rootfs_$1

	abinfo "${FUNCNAME[0]}: Preparing filesystem ($1) ..."
	mkfs.ext4 rootfs_$1

	abinfo "${FUNCNAME[0]}: Preparing mount points ($1) ..."
	mkdir -pv mnt_$1
	mount -o loop rootfs_$1 mnt_$1

	abinfo "${FUNCNAME[0]}: Transferring files to system image ($1) ..."
	rsync -aAX --info=progress2 aosc-system-$1/ mnt_$1/

	abinfo "${FUNCNAME[0]}: Performing post-build clean up ($1) ..."
	umount -Rf mnt_$1
}

build_grub_efi_image() {
	abinfo "${FUNCNAME[0]}: Performing pre-build clean up ($1) ..."
	rm -rfv EFI

	abinfo "${FUNCNAME[0]}: Preparing to build GRUB EFI image ($1) ..."
	mkdir -p EFI/{BOOT,aosc}
	local GRUB_UUID=`blkid -s UUID -o value rootfs_$1`

	local _vmlinux=$(basename $(ls -d aosc-system-$i/boot/vmlinux-*-aosc-asahi | sort -rV | head -1))

	abinfo "${FUNCNAME[0]}: Generating grub.cfg ($1) ..."
	cat > EFI/aosc/grub.cfg << EOF
search.fs_uuid $GRUB_UUID root
echo 'Booting AOSC OS for the first time ...'
echo 'The first boot setup procedure will take place shortly.'
linux (\$root)/boot/$_vmlinux root=UUID=$GRUB_UUID quiet rw rd.auto rd.auto=1 splash
initrd (\$root)/boot/devena-firstboot.img
boot
EOF

# Debian: see https://salsa.debian.org/philh/grub2/-/blob/dgit/sid/debian/build-efi-images
# Integrate as many modules as possible, in order to make GRUB discover partitions by UUID
#
# ~Mingcong: Use pre-built GRUB image from the `grub` package.
# It is not possible to use the prebuilt image from `grub`, since it is built
# with the prefix /boot/grub, which is hard-coded to the grub image.
# The image we are building is meant to use with EFI medias, since we are
# building it with the prefix /EFI/aosc, so that a config file can present
# in EFI partition at /EFI/aosc/grub.cfg, without hard-coding filesystem UUID
# of the boot partition to make it bootable.
# ~Cyan
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
		-o EFI/BOOT/BOOTAA64.EFI \
		-p /EFI/aosc \
		$GRUB_MODULES
}

build_asahi_installer_image() {
	abinfo "${FUNCNAME[0]}: Performing pre-build clean up ($1) ..."
	rm -rfv aii

	abinfo "${FUNCNAME[0]}: Assembling files ($1) ..."
	install -Dvm644 aosc-system-$1/boot/boot.bin \
		aii/esp/m1n1/boot.bin
	cp -av EFI \
		aii/esp/
	ln -v rootfs_$1 \
		aii/rootfs.img

	abinfo "${FUNCNAME[0]}: Copying logo..."
	cp ../logo/aosc-os-asahi-128.icns \
		aii/aosc-os-128.icns

	abinfo "${FUNCNAME[0]}: Generating system release archive ($1) ..."
	cd aii
	zip $ZIP_ARGS ../aosc-os_${1}_$(date +%Y%m%d)_arm64+asahi.zip esp rootfs.img aosc-os-128.icns
	cd ..
	sha256sum aosc-os_${1}_$(date +%Y%m%d)_arm64+asahi.zip \
		>> aosc-os_${1}_$(date +%Y%m%d)_arm64+asahi.zip.sha256sum
}

build_clean_up() {
	abinfo "${FUNCNAME[0]}: Cleaning up ($1) ..."
	rm -rf \
		aii \
		aosc-system-$1 \
		mnt_$1 \
		rootfs_$i \
		EFI
}

abinfo "Creating directories ..."
mkdir -pv build
cd build

abinfo "Setting time zone to UTC ..."
export TZ=UTC

for i in "$@"; do
	abinfo "Performing pre-build clean up ($i) ..."
	build_clean_up $i

	abinfo "Generating system release ($i) ..."
	build_rootfs $i
	build_postinst $i
	build_sys_image $i
	build_grub_efi_image $i
	build_asahi_installer_image $i
	build_clean_up $i
done
