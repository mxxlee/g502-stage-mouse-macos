use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};

use clap::Args;
use hidpp_core::features::{read_battery, MouseButtonSpy, OnboardMode, OnboardProfiles};
use hidpp_core::HidppError;

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

/// Stream raw physical button transitions as newline-delimited JSON.
pub fn handle_buttons(
    ctx: &DeviceContext,
    _args: &ButtonArgs,
    output: OutputFormat,
) -> Result<(), String> {
    KEEP_LISTENING.store(true, Ordering::SeqCst);
    install_signal_handlers();

    let previous_mode = OnboardProfiles::get_mode(ctx.device()).map_err(|e| e.to_string())?;
    OnboardProfiles::set_mode(ctx.device(), OnboardMode::Host).map_err(|e| e.to_string())?;

    let feature = MouseButtonSpy::feature_index(ctx.device()).map_err(|e| e.to_string())?;
    let button_count = MouseButtonSpy::button_count(ctx.device()).map_err(|e| e.to_string())?;
    // Lire la batterie avant d'activer MouseButtonSpy. Une requête synchrone
    // pendant l'écoute pourrait consommer puis ignorer une notification 0x8110.
    if let Err(error) = emit_battery(ctx, output) {
        let _ = OnboardProfiles::set_mode(ctx.device(), previous_mode);
        return Err(error);
    }
    if let Err(error) = MouseButtonSpy::start(ctx.device()) {
        let _ = OnboardProfiles::set_mode(ctx.device(), previous_mode);
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
    let restore_result = OnboardProfiles::set_mode(ctx.device(), previous_mode);
    match (result, restore_result) {
        (Err(error), _) => Err(error),
        (Ok(()), Err(error)) => Err(error.to_string()),
        (Ok(()), Ok(())) => Ok(()),
    }
}
