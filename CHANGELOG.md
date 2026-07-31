# Changelog

All notable changes to G502 Stage Mouse are documented here.

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
