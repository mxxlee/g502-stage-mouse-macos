<p align="center">
  <img src="Assets/AppIcon-1024.png" width="128" alt="G502 Stage Mouse icon">
</p>

# G502 Stage Mouse for macOS

Native macOS menu bar utility for the Logitech G502 X LIGHTSPEED: direct HID++
button mapping, macOS navigation shortcuts, middle-button free-scroll, wake
recovery, and a conservative workaround for a persistent hover-rendering bug.

**[Lire en français](README.fr.md)**

> [!IMPORTANT]
> This is a personal, community project. It is not affiliated with or endorsed
> by Logitech or Apple. The main test machine is a Mac mini M4 Pro running
> macOS 26 with two external displays.

## Why this exists

I am not a software developer. I am a video editor who wanted to make everyday
work on macOS more comfortable.

The G502 has enough physical buttons to replace many trackpad gestures, but
macOS does not map them cleanly to Mission Control, App Exposé, Stage Manager,
Spaces, or native back/forward navigation. G HUB was unreliable on my setup, so
this app communicates with the mouse directly through Logitech's HID++ protocol.

The project also grew around a macOS issue I had lived with for about a year:
after a click, hover animations could stop updating across different apps. The
pointer and clicks still worked, but menus, video controls, and buttons no
longer reacted visually until a very fast mouse movement or a WindowServer
restart temporarily restored them.

The app was built iteratively with AI-assisted development, real-world testing,
and repeated event-safety and energy-use audits. It is shared so that other
people can inspect it, adapt it, and improve it.

## Features

- Visual mapping for the physical G3-G9 buttons.
- Mission Control, App Exposé, desktop, Spaces, and app switching.
- Native back and forward actions in compatible applications.
- Direct HID++ support without a G HUB runtime dependency.
- Wired G502 X LIGHTSPEED, LIGHTSPEED receiver, and POWERPLAY support.
- Battery, charging state, and DPI control from 100 to 25,600.
- Automatic detector recovery after sleep, unlock, and reconnect.
- Event-driven macOS hover stabilizer with no idle polling loop.
- Windows-style vertical and horizontal free-scroll while holding the wheel.
- Optional hold-and-move gesture on one G button to switch Spaces.
- Local, checksum-verified update channel for development builds.

| Button | Physical control | Default action |
| --- | --- | --- |
| G3 | Middle click | Mission Control |
| G4 | Rear thumb button | Back |
| G5 | Front thumb button | Forward |
| G6 | Removable DPI Shift | App Exposé |
| G7 | DPI down | Previous Space |
| G8 | DPI up | Next Space |
| G9 | Profile switch | Show Desktop |

Every mapping can be changed in the visual configuration window.

## Hover stabilizer

The **Stabilize hover after clicks** option is disabled by default. First test
the manual **Wake hover now** action while the issue is visible. If hover starts
working again, enable the automatic mode.

Automatic recovery posts three nearby `mouseMoved` events after a left or
right click. The real pointer position is reused, so the cursor does not move.
There is no periodic timer: when you are not clicking, the stabilizer does no
work.

Safety boundaries are enforced in code and by
[`work/verify_hover_safety.sh`](work/verify_hover_safety.sh):

- no simulated click;
- no window activation, raising, or focus change;
- no pointer warp and no cursor hiding;
- no recovery while a button or drag is active;
- recovery is cancelled when keyboard input occurred in the previous 400 ms;
- listeners stop during sleep, lock, and application shutdown.

This mitigates a symptom; it does not fix WindowServer itself. A closely related
render-suspension issue was documented in
[Mozilla Bug 2033230](https://bugzilla.mozilla.org/show_bug.cgi?id=2033230).

## Middle-button free-scroll

Enable **Free-scroll while holding the wheel**, hold the middle button, and move
the mouse. Motion is converted to smooth vertical and horizontal scrolling.
High-frequency events are coalesced over 8 ms to reduce WindowServer pressure.

A movement under 10 points remains a short click: the configured G3 action runs
normally. If G3 is set to **System Default**, the app replays a native middle
click. **No Action** blocks the button entirely.

## Desktop swipe

Choose one trigger button, G4 to G9, in **Desktop swipe** in the visual
configuration window. Hold it and move the mouse left or right to switch to the
next or previous Space, like a trackpad swipe: moving left goes to the next
Space and moving right goes to the previous one. Check **Reverse direction** to
swap them. Each hold switches once. Vertical or small movements
switch nothing. The **Swipe distance** slider sets how far to move, from 40 to
300 points (default 120).

A short press with under 10 points of net movement keeps the button's normal action.
If G4 or G5 is set to **System Default**, a short press replays its native back
or forward click. With **No Action**, a short press does nothing. G3 stays reserved for free-scroll. The default is Off.

While the app runs, **System Default** on G4 and G5 means the app itself sends
Back and Forward, because the mouse stops sending G5's native click in its
button-capture mode.

Switching uses `Control`+Left and `Control`+Right, so those Mission Control
keyboard shortcuts must be enabled in System Settings. The app needs
Accessibility and Input Monitoring. On the USB-only G502 X (`C099`), the feature
depends on its live button press and release stream, which has had limited
testing.

The configuration window also has a **Polling rate** setting (125, 250, 500 or
1000 Hz). If windows lag while you drag them, try 500 Hz. The app saves your choice and re-applies it after each reconnect
or wake, because the mouse forgets it when the Mac sleeps.

## Back up the mouse's profiles

Saving to the onboard profile writes the mouse's flash memory. Before you use
it on a G502 X, save a byte-for-byte copy with the bundled helper:

```sh
opengcontrol profile backup-raw ~/Documents/g502x-backup.json
opengcontrol profile restore-raw ~/Documents/g502x-backup.json --yes
```

`restore-raw` checks the device, sector size and CRCs, rewrites only sectors
that differ, and verifies each one by read-back. Keep the file somewhere safe.
When the app quits it returns the mouse to onboard mode, so the stored profile
applies again.

## Compatibility

- macOS 13 or later;
- Apple Silicon;
- G502 X (USB-only, no wireless): `046D:C099`. There is no battery display. The
  app remembers your DPI and polling rate and re-applies them on every connect.
  **Save to onboard profile** writes the DPI to the mouse's active profile; make
  a raw backup first (see below);
- G502 X LIGHTSPEED connected by USB: `046D:C098`;
- LIGHTSPEED receiver: `046D:C547`;
- POWERPLAY: `046D:C53A`.

Other Logitech models are not guaranteed. Contributions that add safely tested
device definitions are welcome.

## Install a release build

1. Download the latest ZIP from
   [Releases](https://github.com/ymergame/g502-stage-mouse-macos/releases).
2. Unzip it and move **G502 Stage Mouse.app** to `/Applications`.
3. Open the app.
4. Grant **Accessibility** and **Input Monitoring** in System Settings → Privacy
   & Security.
5. Open the mouse icon in the menu bar and select **Configure visually…**.

Current community builds are ad hoc signed and not notarized. macOS may warn on
first launch and can ask for Accessibility or Input Monitoring again after an
update. A stable Developer ID signature is required to avoid that limitation.

Mission Control and Space shortcuts must also be enabled in System Settings →
Keyboard → Keyboard Shortcuts → Mission Control.

## Build from source

Requirements:

- Xcode Command Line Tools;
- Rust and Cargo;
- an Apple Silicon Mac for the current app target.

```bash
git clone https://github.com/ymergame/g502-stage-mouse-macos.git
cd g502-stage-mouse-macos/work/opengcontrol
cargo build --release
cd ../..
./build.command
```

The ZIP and manifest are created in `build/`. To explicitly publish the archive
to the app's local update channel:

```bash
PUBLISH_LOCAL_UPDATE=1 ./build.command
```

Run the helper tests independently with:

```bash
cd work/opengcontrol
cargo test --workspace --locked
```

## Permissions and privacy

Accessibility is required to trigger macOS navigation shortcuts. Input
Monitoring is required to receive the extra mouse buttons. G502 Stage Mouse does
not include telemetry, an account system, or a cloud service. Configuration and
the development update channel stay local to the Mac.

Because these permissions are powerful, inspect the source and build it yourself
if that is more comfortable. Security reports are documented in
[`SECURITY.md`](SECURITY.md).

## Repository layout

```text
Sources/G502StageMouse/   Swift/AppKit application and UI
Assets/                   App icon and attributed 3D mouse model
work/opengcontrol/        Vendored Rust HID++ helper and local extensions
work/verify_hover_safety.sh
                          Event-safety regression check
docs/                     Architecture and troubleshooting guides
build.command             Build, ad hoc signature, ZIP, and manifest
```

The architecture is described in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Known limitations

- The hover workaround is macOS-specific and may not help every WindowServer
  rendering problem.
- Release builds are not currently Developer ID signed or notarized.
- The 3D mouse model is CC BY-NC-SA 4.0, not MIT; commercial redistributors must
  replace it. See [`ASSET-LICENSES.md`](ASSET-LICENSES.md).
- Hardware support is deliberately narrow because button remapping can alter a
  mouse's onboard profile.

## Contributing

Bug reports, hardware observations, documentation fixes, and carefully scoped
pull requests are welcome. Please include the exact Mac, macOS version, mouse
connection type, receiver VID/PID, and reproduction steps.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## Credits and license

The original application code and documentation are released under the
[MIT License](LICENSE). The vendored `opengcontrol` helper retains its upstream
license and contributor attribution. The 3D model has a separate non-commercial
Creative Commons license.

See [`THIRD-PARTY-NOTICES.txt`](THIRD-PARTY-NOTICES.txt) and
[`ASSET-LICENSES.md`](ASSET-LICENSES.md) before redistributing the app.
