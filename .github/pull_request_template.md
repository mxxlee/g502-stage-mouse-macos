## What changed

Describe the user-visible behavior and why it is needed.

## Verification

- [ ] `cargo fmt --all -- --check`
- [ ] `cargo test --workspace --locked`
- [ ] `./build.command`
- [ ] Tested on real hardware, or clearly marked as untested

## Safety

- [ ] No window activation, focus, pointer warp, cursor hiding, or synthetic click was added to hover recovery.
- [ ] Onboard profile writes are explicit and backed up.
- [ ] Logs and screenshots contain no serial numbers or personal paths.
