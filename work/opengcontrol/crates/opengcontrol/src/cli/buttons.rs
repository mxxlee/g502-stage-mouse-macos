use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};

use clap::Args;
use hidpp_core::features::{read_battery, MouseButtonSpy, OnboardMode, OnboardProfiles};
use hidpp_core::{FeatureIndex, HidTransport, HidppDevice, HidppError};

use crate::context::DeviceContext;
use crate::output::OutputFormat;

#[derive(Args)]
pub struct ButtonArgs {}

static KEEP_LISTENING: AtomicBool = AtomicBool::new(true);

#[cfg(unix)]
extern "C" fn stop_listening(_: libc::c_int) {
    KEEP_LISTENING.store(false, Ordering::SeqCst);
}

#[cfg(unix)]
fn install_signal_handlers() {
    unsafe {
        libc::signal(
            libc::SIGTERM,
            stop_listening as *const () as libc::sighandler_t,
        );
        libc::signal(
            libc::SIGINT,
            stop_listening as *const () as libc::sighandler_t,
        );
    }
}

#[cfg(not(unix))]
fn install_signal_handlers() {}

fn emit_battery(ctx: &DeviceContext, output: OutputFormat) -> Result<(), String> {
    match read_battery(ctx.device()) {
        Ok(reading) => match output {
            OutputFormat::Json => println!(
                "{}",
                serde_json::json!({
                    "battery_available": true,
                    "battery_percent": reading.percentage,
                    "battery_estimated": reading.estimated,
                    "battery_level": reading.level.map(|level| level.as_str()),
                    "battery_charging": reading.charging.is_charging(),
                    "battery_status": reading.charging.as_str(),
                    "battery_voltage_mv": reading.voltage_mv
                })
            ),
            OutputFormat::Human => println!(
                "Battery: {}{} — {}",
                reading
                    .percentage
                    .map(|percentage| percentage.to_string())
                    .unwrap_or_else(|| "unknown".to_string()),
                if reading.percentage.is_some() {
                    "%"
                } else {
                    ""
                },
                reading.charging.as_str()
            ),
        },
        Err(error) => match output {
            OutputFormat::Json => println!(
                "{}",
                serde_json::json!({
                    "battery_available": false,
                    "battery_error": error.to_string()
                })
            ),
            OutputFormat::Human => println!("Battery unavailable: {error}"),
        },
    }
    io::stdout().flush().map_err(|error| error.to_string())
}

/// The mouse powers up in host mode, where it ignores its stored profile. Leave it in
/// onboard mode so the stored profile applies once the app stops listening.
fn mode_after_listening(_previous: OnboardMode) -> OnboardMode {
    OnboardMode::Onboard
}

fn enter_host_mode<T: HidTransport>(
    device: &HidppDevice<T>,
) -> Result<(FeatureIndex, u8, OnboardMode), String> {
    let feature = MouseButtonSpy::feature_index(device).map_err(|e| e.to_string())?;
    let button_count = MouseButtonSpy::button_count(device).map_err(|e| e.to_string())?;
    let previous_mode = OnboardProfiles::get_mode(device).map_err(|e| e.to_string())?;
    OnboardProfiles::set_mode(device, OnboardMode::Host).map_err(|e| e.to_string())?;
    Ok((feature, button_count, previous_mode))
}

/// Stream raw physical button transitions as newline-delimited JSON.
pub fn handle_buttons(
    ctx: &DeviceContext,
    _args: &ButtonArgs,
    output: OutputFormat,
) -> Result<(), String> {
    KEEP_LISTENING.store(true, Ordering::SeqCst);
    install_signal_handlers();

    let (feature, button_count, previous_mode) = enter_host_mode(ctx.device())?;
    // Lire la batterie avant d'activer MouseButtonSpy. Une requête synchrone
    // pendant l'écoute pourrait consommer puis ignorer une notification 0x8110.
    if let Err(error) = emit_battery(ctx, output) {
        let _ = OnboardProfiles::set_mode(ctx.device(), mode_after_listening(previous_mode));
        return Err(error);
    }
    if let Err(error) = MouseButtonSpy::start(ctx.device()) {
        let _ = OnboardProfiles::set_mode(ctx.device(), mode_after_listening(previous_mode));
        return Err(error.to_string());
    }

    match output {
        OutputFormat::Json => println!(
            "{}",
            serde_json::json!({
                "ready": true,
                "feature": "8110",
                "button_count": button_count,
                "mode": "host",
                "previous_mode": match previous_mode {
                    OnboardMode::Onboard => "onboard",
                    OnboardMode::Host => "host",
                }
            })
        ),
        OutputFormat::Human => {
            println!("MouseButtonSpy ready — {button_count} physical buttons")
        }
    }
    io::stdout().flush().map_err(|e| e.to_string())?;

    let mut previous = 0u16;
    let result = loop {
        if !KEEP_LISTENING.load(Ordering::SeqCst) {
            break Ok(());
        }
        let message = match ctx.device().read_message(1000) {
            Ok(message) => message,
            Err(HidppError::Timeout { .. }) => continue,
            Err(error) => break Err(error.to_string()),
        };
        let Some(current) = MouseButtonSpy::event_mask(feature, &message) else {
            continue;
        };
        let changed = previous ^ current;
        for index in 0..button_count.min(16) {
            let bit = 1u16 << index;
            if changed & bit == 0 {
                continue;
            }
            let pressed = current & bit != 0;
            match output {
                OutputFormat::Json => println!(
                    "{}",
                    serde_json::json!({
                        "button_index": index,
                        "pressed": pressed,
                        "mask": format!("{current:04X}")
                    })
                ),
                OutputFormat::Human => println!(
                    "Button {index}: {}",
                    if pressed { "pressed" } else { "released" }
                ),
            }
        }
        previous = current;
        if let Err(error) = io::stdout().flush() {
            break Err(error.to_string());
        }
    };

    let _ = MouseButtonSpy::stop(ctx.device());
    let restore_result =
        OnboardProfiles::set_mode(ctx.device(), mode_after_listening(previous_mode));
    match (result, restore_result) {
        (Err(error), _) => Err(error),
        (Ok(()), Err(error)) => Err(error.to_string()),
        (Ok(()), Ok(())) => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;
    use std::sync::{Arc, Mutex};

    const SOFTWARE_ID: u8 = 0x0C;

    fn short_response(feature_index: u8, function: u8, params: [u8; 3]) -> Vec<u8> {
        vec![
            0x10,
            0xFF,
            feature_index,
            (function << 4) | SOFTWARE_ID,
            params[0],
            params[1],
            params[2],
        ]
    }

    struct ScriptedTransport {
        writes: Arc<Mutex<Vec<Vec<u8>>>>,
        pending: Mutex<VecDeque<Vec<u8>>>,
    }

    impl ScriptedTransport {
        fn new() -> Self {
            Self {
                writes: Arc::new(Mutex::new(Vec::new())),
                pending: Mutex::new(VecDeque::new()),
            }
        }

        fn respond(request: &[u8]) -> Vec<u8> {
            let (feature, function) = (request[3], request[4] >> 4);
            match (feature, function) {
                (0x00, 0) => {
                    let code = u16::from_be_bytes([request[5], request[6]]);
                    let index = if code == 0x8100 { 0x05 } else { 0x00 };
                    short_response(0x00, 0, [index, 0, 0])
                }
                (0x05, 2) => short_response(0x05, 2, [OnboardMode::Onboard as u8, 0, 0]),
                _ => short_response(feature, function, [0, 0, 0]),
            }
        }
    }

    impl HidTransport for ScriptedTransport {
        fn write(&self, data: &[u8]) -> Result<(), HidppError> {
            self.writes.lock().unwrap().push(data.to_vec());
            self.pending.lock().unwrap().push_back(Self::respond(data));
            Ok(())
        }

        fn read(&self, buf: &mut [u8], _timeout_ms: i32) -> Result<usize, HidppError> {
            let response = self
                .pending
                .lock()
                .unwrap()
                .pop_front()
                .ok_or(HidppError::Timeout { timeout_ms: 0 })?;
            buf[..response.len()].copy_from_slice(&response);
            Ok(response.len())
        }
    }

    #[test]
    fn listening_always_ends_in_onboard_mode() {
        assert_eq!(
            mode_after_listening(OnboardMode::Host),
            OnboardMode::Onboard
        );
        assert_eq!(
            mode_after_listening(OnboardMode::Onboard),
            OnboardMode::Onboard
        );
    }

    #[test]
    fn missing_button_spy_feature_leaves_mode_unchanged() {
        let transport = ScriptedTransport::new();
        let writes = transport.writes.clone();
        let device = HidppDevice::new(transport);

        assert!(enter_host_mode(&device).is_err());

        let mode_writes: Vec<_> = writes
            .lock()
            .unwrap()
            .iter()
            .filter(|write| write[3] == 0x05 && write[4] >> 4 == 1)
            .cloned()
            .collect();
        if let Some(last) = mode_writes.last() {
            assert_eq!(last[5], OnboardMode::Onboard as u8);
        }
    }
}
