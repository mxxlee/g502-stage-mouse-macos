# Troubleshooting

## Extra buttons are not detected

1. Quit G HUB and other mouse remappers temporarily.
2. Confirm Input Monitoring is enabled for G502 Stage Mouse.
3. Use **Restart detection**.
4. Open **Diagnostic POWERPLAY / HID++…** and check that the expected receiver
   VID/PID appears.
5. Disconnect and reconnect the receiver or POWERPLAY USB cable.

After sleep, wait a few seconds: the app retries with progressive backoff while
the receiver becomes available.

## Permissions are requested again after an update

The public community build is ad hoc signed. Its identity can change after a
rebuild, so macOS may treat it as a new binary. A stable Developer ID signature
and notarization are the long-term fix.

## Hover still stops updating

First reproduce the problem with G502 Stage Mouse closed. Then launch it and use
**Wake hover now** while the issue is visible. If this does not help, leave the
automatic stabilizer disabled: the underlying cause may be different.

If the manual action helps but the automatic mode does not, record whether the
failure followed a drag, keyboard input, full-screen transition, display wake,
or click. Those guards are intentional and useful in a bug report.

## Middle click triggers instead of scrolling

Free-scroll activates only after the pointer moves at least 3 points while the
wheel is held. Confirm **Free-scroll while holding the wheel** is enabled.

## macOS blocks the app

Community releases are not notarized. Building from source is the clearest trust
path. Do not disable Gatekeeper globally.
