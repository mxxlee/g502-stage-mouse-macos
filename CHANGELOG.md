# Changelog

All notable changes to G502 Stage Mouse are documented here.

## [14.8] - 2026-10-01

Adds the USB-only G502 X, desktop swipe, English and French, and safer saving to
the mouse's onboard memory.

### Added

- Support for the USB-only Logitech G502 X (`046D:C099`), separate from the
  G502 X LIGHTSPEED. It has no battery display.
- English and French interface, with a language choice in the menu.
- **Desktop swipe:** hold one chosen button (G4 to G9) and move left or right to
  switch Spaces. A short press keeps its normal action. The distance (40 to 300
  points, default 120) and the direction are adjustable.
- **No Action** now blocks a button completely. The previous behavior is renamed
  **System Default**; existing settings keep working as before.
- **Polling rate** setting (125, 250, 500 or 1000 Hz). The app remembers it and
  the DPI and re-applies both after a reconnect or wake.
- **Save to onboard profile** for the USB-only G502 X, plus helper commands
  `profile backup-raw` and `profile restore-raw` for a byte-for-byte backup of the
  mouse's profile memory.
- Cmd+W, Cmd+M, Cmd+Q and Ctrl+Cmd+F in the configuration window.

### Changed

- Show Desktop and App Exposé use macOS's own Dock notifications instead of a
  keystroke, so Show Desktop no longer changes the volume.
- A short click on the wheel (G3) or on the swipe button now tolerates 10 points
  of hand movement instead of 3.
- Saving DPI writes to the DPI slot the mouse is running on (USB-only G502 X).
- Quitting the app returns the mouse to onboard mode, so its stored profile and
  built-in DPI buttons work again.

### Fixed

- Previous/Next Space and App Exposé buttons never triggered on macOS.
- Free-scroll did nothing on macOS 27.
- The DPI Apply button showed no status.
- A failed button lookup could leave the mouse in host mode.
- Session DPI changes failed on the USB-only G502 X.
- The version shown in the menu now follows the app's real version.

### Known limits

- While the app runs, the mouse's built-in G6 to G9 functions (DPI shift, DPI
  up/down, profile cycle) are inactive. They work again when the app quits.
- Saving to the onboard profile writes the mouse's flash memory. Make a backup
  first (see the README).
- Not tested on a LIGHTSPEED receiver or POWERPLAY with this release.

## [14.7] - 2026-07-31

Initial public V1 release.

### Added

- Direct G3-G9 button events through HID++ `MouseButtonSpy`.
- Visual macOS action mapping, battery status, DPI control, and diagnostics.
- Automatic detector recovery after sleep, unlock, and receiver reconnect.
- Event-driven hover recovery after clicks with keyboard and drag guards.
- Windows-style vertical and horizontal free-scroll while holding the wheel.
- Local SHA-256-verified update channel.

### Changed

- Removed periodic hover polling and periodic battery reads.
- Added progressive HID++ reconnect backoff and receiver-presence checks.
- Coalesced free-scroll motion over 8 ms to reduce WindowServer pressure.

### Removed

- Window activation-on-hover behavior.
- F13-F19 keyboard interception and automatic onboard remapping.
