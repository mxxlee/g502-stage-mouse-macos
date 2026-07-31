# Contributing

Thank you for helping make G502 Stage Mouse safer and more useful.

## Before opening an issue

Search existing issues and run **Diagnostic POWERPLAY / HID++…** from the app's
menu. Remove serial numbers, usernames, and personal paths before posting logs.

For hardware or sleep/reconnect problems, include:

- Mac model and chip;
- macOS version;
- mouse model and wired, LIGHTSPEED, or POWERPLAY connection;
- USB VID/PID if available;
- whether G HUB, LinearMouse, BetterMouse, or similar software was running;
- precise steps and the result after sleep or unlock.

For hover problems, also state whether **Wake hover now** temporarily restores
the UI and whether the issue happens while G502 Stage Mouse is closed.

## Development

```bash
cd work/opengcontrol
cargo fmt --all -- --check
cargo test --workspace --locked
cd ../..
./build.command
```

The build script runs `work/verify_hover_safety.sh`. Do not bypass this check.

## Safety rules

Changes to the hover path must never:

- activate, raise, or focus windows;
- synthesize a click;
- move the pointer;
- hide the cursor;
- run a periodic pointer polling loop;
- recover during a drag or recent keyboard input.

Changes that write an onboard mouse profile must create a backup first and make
the user action explicit.

## Pull requests

Keep changes focused, explain the user-visible behavior, and list the exact
tests run. Runtime behavior on real hardware matters more than a successful
compile alone.

By contributing, you agree that your contribution may be distributed under the
license that applies to the component you changed.
