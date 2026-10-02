use std::collections::BTreeMap;

use hidpp_core::features::crc_ccitt;

pub const FORMAT: &str = "opengcontrol-raw-backup-v1";
const FIRST_ROM_SECTOR: u16 = 0x0100;

pub struct RawBackup {
    pub pid: u16,
    pub profile_size: u16,
    pub sectors: BTreeMap<u16, Vec<u8>>,
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn unhex(text: &str) -> Result<Vec<u8>, String> {
    if text.len() % 2 != 0 {
        return Err("odd-length hex string".into());
    }
    (0..text.len())
        .step_by(2)
        .map(|i| {
            u8::from_str_radix(&text[i..i + 2], 16).map_err(|_| "invalid hex digit".to_string())
        })
        .collect()
}

fn is_blank(data: &[u8]) -> bool {
    data.iter().all(|b| *b == 0xFF) || data.iter().all(|b| *b == 0x00)
}

fn crc_valid(data: &[u8]) -> bool {
    let n = data.len();
    n > 2 && crc_ccitt(&data[..n - 2]) == u16::from_be_bytes([data[n - 2], data[n - 1]])
}

impl RawBackup {
    pub fn to_json(&self) -> serde_json::Value {
        let sectors: serde_json::Map<String, serde_json::Value> = self
            .sectors
            .iter()
            .map(|(sector, data)| (format!("{sector:#06X}"), hex(data).into()))
            .collect();
        serde_json::json!({
            "format": FORMAT,
            "pid": format!("{:04X}", self.pid),
            "profile_size": self.profile_size,
            "sectors": sectors,
        })
    }

    pub fn from_json(value: &serde_json::Value) -> Result<Self, String> {
        if value["format"] != FORMAT {
            return Err("not an opengcontrol raw backup file".into());
        }
        let pid = value["pid"]
            .as_str()
            .and_then(|p| u16::from_str_radix(p, 16).ok())
            .ok_or("missing or invalid pid")?;
        let profile_size = value["profile_size"]
            .as_u64()
            .and_then(|s| u16::try_from(s).ok())
            .ok_or("missing or invalid profile_size")?;
        let mut sectors = BTreeMap::new();
        for (key, data) in value["sectors"].as_object().ok_or("missing sectors")? {
            let sector = u16::from_str_radix(key.trim_start_matches("0x"), 16)
                .map_err(|_| format!("invalid sector key {key}"))?;
            let bytes = unhex(data.as_str().ok_or("sector data must be a string")?)?;
            sectors.insert(sector, bytes);
        }
        Ok(Self {
            pid,
            profile_size,
            sectors,
        })
    }

    /// Sectors that a restore may write: user flash only, right size, valid CRC.
    /// Blank sectors are skipped because they cannot be rewritten byte for byte.
    pub fn restorable_sectors(&self, pid: u16, profile_size: u16) -> Result<Vec<u16>, String> {
        if self.pid != pid {
            return Err(format!(
                "backup is for {:04X}, connected device is {pid:04X}",
                self.pid
            ));
        }
        if self.profile_size != profile_size {
            return Err(format!(
                "backup sector size {} does not match device sector size {profile_size}",
                self.profile_size
            ));
        }
        let mut writable = Vec::new();
        for (sector, data) in &self.sectors {
            if *sector >= FIRST_ROM_SECTOR {
                continue;
            }
            if data.len() != profile_size as usize {
                return Err(format!("sector {sector:#06X} has the wrong length"));
            }
            if is_blank(data) {
                continue;
            }
            if !crc_valid(data) {
                return Err(format!("sector {sector:#06X} fails its CRC check"));
            }
            writable.push(*sector);
        }
        Ok(writable)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_sector(size: usize, fill: u8) -> Vec<u8> {
        let mut data = vec![fill; size];
        let crc = crc_ccitt(&data[..size - 2]).to_be_bytes();
        data[size - 2] = crc[0];
        data[size - 1] = crc[1];
        data
    }

    fn sample() -> RawBackup {
        let mut sectors = BTreeMap::new();
        sectors.insert(0x0000, valid_sector(32, 0x11));
        sectors.insert(0x0001, valid_sector(32, 0x22));
        sectors.insert(0x0002, vec![0xFF; 32]);
        sectors.insert(0x0101, valid_sector(32, 0x33));
        RawBackup {
            pid: 0xC099,
            profile_size: 32,
            sectors,
        }
    }

    #[test]
    fn json_round_trip_preserves_every_byte() {
        let backup = sample();
        let restored = RawBackup::from_json(&backup.to_json()).unwrap();
        assert_eq!(restored.pid, 0xC099);
        assert_eq!(restored.sectors, backup.sectors);
    }

    #[test]
    fn restore_skips_rom_and_blank_sectors() {
        let sectors = sample().restorable_sectors(0xC099, 32).unwrap();
        assert_eq!(sectors, vec![0x0000, 0x0001]);
    }

    #[test]
    fn restore_rejects_a_different_device() {
        assert!(sample().restorable_sectors(0xC098, 32).is_err());
    }

    #[test]
    fn restore_rejects_a_different_sector_size() {
        assert!(sample().restorable_sectors(0xC099, 64).is_err());
    }

    #[test]
    fn restore_rejects_a_corrupt_sector() {
        let mut backup = sample();
        backup.sectors.get_mut(&0x0001).unwrap()[5] ^= 0x01;
        assert!(backup.restorable_sectors(0xC099, 32).is_err());
    }

    #[test]
    fn rejects_files_with_another_format() {
        let value = serde_json::json!({"format": "something-else"});
        assert!(RawBackup::from_json(&value).is_err());
    }
}
