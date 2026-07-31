# Architecture

G502 Stage Mouse is intentionally split into a native macOS process and a small
HID++ command-line helper.

```text
G502 X / receiver / POWERPLAY
              │ HID++ and IOHID
              ▼
    vendored Rust opengcontrol helper
              │ line-delimited button events / commands
              ▼
      Swift/AppKit menu bar app
       ├─ visual configuration
       ├─ macOS shortcut actions
       ├─ hover recovery listener
       ├─ middle-button free-scroll
       └─ sleep/session lifecycle
```

## Swift application

`Sources/G502StageMouse/main.swift` owns the application lifecycle, status menu,
event listeners, button routing, helper process, sleep and session recovery,
local updater, and diagnostics.

`Sources/G502StageMouse/VisualConfig.swift` owns the SceneKit mouse view and the
visual mapping/DPI window. SceneKit rendering pauses when the window closes.

The hover listener uses a separate `.listenOnly` event tap. It never consumes
the user's click. Recovery work is scheduled only after left or right mouse-up
and is cancelled during a drag, held button, session transition, or recent
keyboard input.

## Rust helper

`work/opengcontrol` is based on
[`kasik96/opengcontrol`](https://github.com/kasik96/opengcontrol), with G502 X
and application-specific HID++ extensions. The app embeds its release binary.

The helper opens the matching HID interface, resolves HID++ features, reads
battery/DPI/profile state, and exposes a long-lived `buttons listen` stream
using feature `0x8110` (`MouseButtonSpy`).

## Reconnect lifecycle

The helper stops during sleep or an inactive user session. On wake or unlock,
the app recreates the macOS event listeners and reconnects HID++. Ordinary
connection failures use progressive backoff. When the receiver is physically
absent, retrying pauses until IOHID reports its return or a relevant button
event provides a new signal.

## Update model

The updater is deliberately local. A manifest in
`~/Library/Application Support/G502StageMouse/Updates` names a ZIP and its
SHA-256 digest. The app validates the digest and code signature before replacing
its copy in `/Applications`.
