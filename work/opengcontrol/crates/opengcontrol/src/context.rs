use std::collections::HashSet;

use hidapi::HidApi;
use hidpp_core::{FeatureCode, HidapiTransport, HidppDevice, HidppError};
use logitech_devices::{device_info::DeviceInfo, enumerate_supported_devices};

use crate::output::OutputFormat;
use crate::permissions::classify_open_error;
use crate::spinner::Spinner;

/// A deduplicated physical device (one entry per mouse, regardless of HID interfaces).
pub struct PhysicalDevice {
    pub name: &'static str,
    pub vid: u16,
    pub pid: u16,
    /// The preferred HID path for this device (Unifying receiver interface first).
    pub path: String,
}

/// Enumerate all connected supported devices, one entry per physical device.
pub fn enumerate_physical_devices() -> Result<Vec<PhysicalDevice>, String> {
    let api = HidApi::new().map_err(|e| format!("Failed to initialize HID API: {e}"))?;
    let supported = enumerate_supported_devices(&api);
    let mut seen = HashSet::new();
    let devices = supported
        .into_iter()
        .filter(|(_, h)| seen.insert((h.vendor_id(), h.product_id())))
        .map(|(info, h)| PhysicalDevice {
            name: info.name,
            vid: h.vendor_id(),
            pid: h.product_id(),
            path: h.path().to_string_lossy().into_owned(),
        })
        .collect();
    Ok(devices)
}

/// Holds an opened HID++ device and its static registry entry.
pub struct DeviceContext {
    device: HidppDevice<HidapiTransport>,
    device_info: &'static DeviceInfo,
}

impl DeviceContext {
    /// Open the first supported device (or the one at `device_path`).
    /// Shows an animated spinner in human output mode while connecting.
    pub fn open(device_path: Option<&str>, output: OutputFormat) -> Result<Self, HidppError> {
        let api = HidApi::new().map_err(|e| HidppError::Transport(e.to_string()))?;

        let supported = enumerate_supported_devices(&api);
        if supported.is_empty() {
            return Err(HidppError::NoDeviceFound);
        }

        let requested: Vec<_> = if let Some(path) = device_path {
            vec![supported
                .into_iter()
                .find(|(_, h)| h.path().to_string_lossy() == path)
                .ok_or_else(|| HidppError::Transport(format!("No device found at path: {path}")))?]
        } else {
            supported
                .into_iter()
                // HID++ lives on the vendor-defined channel. Never send protocol
                // writes to the keyboard or mouse boot interfaces.
                .filter(|(_, h)| h.usage_page() == 0xFF00 && h.usage() == 0x01)
                .collect()
        };

        if requested.is_empty() {
            return Err(HidppError::Transport(
                "No Logitech HID++ interface (usage page 0xFF00, usage 0x01) was found".into(),
            ));
        }

        let spinner = Spinner::new("Searching Logitech HID++ endpoints…", output);
        let mut attempts = Vec::new();
        let mut permission_denied = false;

        for (device_info, hid_info) in requested {
            let pid = hid_info.product_id();
            let path = hid_info.path().to_string_lossy().into_owned();
            let is_numbered_hidpp = hid_info.usage_page() == 0xFF00;
            let is_receiver = matches!(pid, 0xC539 | 0xC547 | 0xC53A);
            let addresses: &[u8] = if is_receiver {
                // POWERPLAY and LIGHTSPEED expose paired devices at receiver slots.
                // Address 0xFF targets the receiver itself on raw macOS HID and
                // therefore cannot expose the mouse's 0x8100 feature.
                &[0x01, 0x02, 0x03, 0x04, 0x05, 0x06]
            } else {
                &[0xFF]
            };

            let hid_device = match api.open_path(hid_info.path()) {
                Ok(device) => device,
                Err(e) => {
                    let err = classify_open_error(e);
                    permission_denied |= matches!(err, HidppError::PermissionDenied);
                    attempts.push(format!(
                        "{:04X}:{:04X} path={} open={}",
                        hid_info.vendor_id(),
                        pid,
                        path,
                        err
                    ));
                    continue;
                }
            };

            let transport = if is_numbered_hidpp {
                HidapiTransport::new_wireless(hid_device)
            } else {
                HidapiTransport::new(hid_device)
            };
            let mut device = HidppDevice::with_device_id(transport, addresses[0]);

            for &address in addresses {
                device.set_device_id(address);
                match device.get_feature_index(FeatureCode::OnboardProfiles) {
                    Ok(index) => {
                        attempts.push(format!(
                            "{:04X}:{:04X}@{:02X}=0x8100/index-{:02X}",
                            hid_info.vendor_id(),
                            pid,
                            address,
                            index.0
                        ));
                        spinner.clear();
                        return Ok(Self {
                            device,
                            device_info,
                        });
                    }
                    Err(err) => attempts.push(format!(
                        "{:04X}:{:04X}@{:02X}={}",
                        hid_info.vendor_id(),
                        pid,
                        address,
                        err
                    )),
                }
            }
        }

        if permission_denied {
            spinner.finish_err("Permission denied");
            Err(HidppError::PermissionDenied)
        } else {
            let summary = attempts.join("; ");
            spinner.finish_err("G502 X HID++ endpoint not found");
            Err(HidppError::NoOnboardProfilesEndpoint { attempts: summary })
        }
    }

    pub fn device(&self) -> &HidppDevice<HidapiTransport> {
        &self.device
    }

    pub fn device_info(&self) -> &'static DeviceInfo {
        self.device_info
    }
}
