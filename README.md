aosc-asahi-installer
====================

Scripts for generating and installing AOSC OS releases on Apple Silicon (Asahi) devices.

generate-releases.sh
--------------------

Usage:

```
generate-releases.sh [VARIANTS {base,desktop,server}]
```

install-system.sh
-----------------

Run the following command in a macOS terminal - you would need macOS Ventura (13) or newer:

```
curl https://raw.githubusercontent.com/AOSC-Dev/aosc-asahi-installer/master/install-system.sh | sh
```

metadata_generator
------------------

A tool for generating `installer_data.json`. First, build the tool:

```
cargo build --release
```

Next, generate said JSON:

```
Usage: metadata_generater [OPTIONS] --path <PATH> --os-name <OS_NAME> --efi-size <EFI_SIZE> --image-name <IMAGE_NAME>

Options:
  -p, --path <PATH>              The directory where the Asahi images
  -n, --os-name <OS_NAME>        Default OS name in asahi-installer
      --efi-size <EFI_SIZE>      Size of the EFI partition (in MiB)
      --image-name <IMAGE_NAME>  Name of the rootfs image
      --icon <ICON>              File name of the boot menu icon
  -h, --help                     Print help
  -V, --version                  Print version
```

For example:

```
./target/release/metadata_generator \
    --path ../build \
    --os-name "AOSC OS" \
    --efi-size 512 \
    --image-name rootfs.img \
    --icon aosc-os-128.icns \
    > installer_data.json
```
