# Upstream provenance

The helper in this directory is vendored from
[`kasik96/opengcontrol`](https://github.com/kasik96/opengcontrol).

The G502 Stage Mouse V1 started from upstream commit `ddf430b`, the head of the
`g502x` branch fetched from upstream pull request #1. That history includes the
G502 X device work by Louis Abraham and the opengcontrol contributors.

The vendored copy then received local extensions for the G502 X LIGHTSPEED and
POWERPLAY integration used by the macOS app, including long-lived raw button
listening, battery/DPI reliability changes, receiver-slot handling, and tests.

The nested Git metadata is deliberately not distributed. This file, the Cargo
package metadata, `THIRD-PARTY-NOTICES.txt`, and `LICENSES/MIT.txt` preserve the
source and licensing context for the flattened copy.

When updating from upstream:

1. record the exact upstream commit;
2. review local G502/POWERPLAY changes before merging;
3. run `cargo test --workspace --locked` on macOS;
4. rebuild the application and run `work/verify_hover_safety.sh`;
5. update this file and `THIRD-PARTY-NOTICES.txt` if provenance changes.
