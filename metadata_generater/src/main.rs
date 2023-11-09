use std::{fs, io::BufReader};

use clap::Parser;
use eyre::{eyre, Result};
use serde::Serialize;
use zip::ZipArchive;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    #[arg(long, short)]
    path: String,
    #[arg(long, short = 'n')]
    os_name: String,
    #[arg(long, value_parser = clap::value_parser!(u32).range(100..))]
    efi_size: u32,
}

#[derive(Debug, Serialize)]
struct Os {
    name: String,
    default_os_name: String,
    boot_object: String,
    next_object: String,
    package: String,
    partitions: Vec<Partition>,
}

#[derive(Debug, Serialize)]
struct Partition {
    name: String,
    #[serde(rename = "type")]
    part_type: String,
    size: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    format: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    copy_firmware: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    copy_installer_data: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    expand: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    image: Option<String>,
}

fn main() -> Result<()> {
    let Args {
        path,
        os_name,
        efi_size,
    } = Args::parse();

    let dir = fs::read_dir(path)?;

    let mut res = vec![];

    for i in dir.flatten() {
        if i.path().extension().map(|x| x == "zip").unwrap_or(false) {
            let name = i
                .file_name()
                .to_str()
                .map(|x| x.to_string())
                .ok_or_else(|| eyre!("Could not get file name"))?;

            let mut zip = ZipArchive::new(BufReader::new(fs::File::open(i.path())?))?;

            let mut size = None;

            for i in 0..zip.len() {
                let file = zip.by_index(i)?;
                if file.name() == "media" {
                    size = Some(file.size());
                }
            }

            let size = size.ok_or_else(|| eyre!("Could not get rootfs file: media"))? as f64
                / 1024.0
                / 1024.0
                / 1024.0;

            let rootfs_size = format!("{}GB", size.round() as u64);

            res.push(Os {
                name: name.strip_suffix(".zip").unwrap_or(&name).to_string(),
                default_os_name: os_name.to_string(),
                boot_object: "m1n1.bin".to_string(),
                next_object: "m1n1/boot.bin".to_string(),
                package: name,
                partitions: vec![
                    Partition {
                        name: "EFI".to_string(),
                        part_type: "EFI".to_string(),
                        size: format!("{efi_size}MB"),
                        format: Some("fat".to_string()),
                        copy_firmware: Some(true),
                        copy_installer_data: Some(true),
                        source: Some("esp".to_string()),
                        expand: None,
                        image: None,
                    },
                    Partition {
                        name: "Root".to_string(),
                        part_type: "Linux".to_string(),
                        size: rootfs_size,
                        format: None,
                        copy_firmware: None,
                        copy_installer_data: None,
                        source: None,
                        expand: Some(true),
                        image: Some("media".to_string()),
                    },
                ],
            });
        }
    }

    let s = serde_json::to_string_pretty(&res)?;
    println!("{s}");

    Ok(())
}
