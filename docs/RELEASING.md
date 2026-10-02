# Releasing

A release is a tagged commit on `main` plus a zip built from exactly that commit.

## Before tagging

1. Merge the work into `main`. Release from `main`, never from a feature branch.
2. Set the version in `build.command` (`APP_VERSION`, `BUILD_NUMBER`,
   `ARCHIVE_NAME`) and in `work/verify_hover_safety.sh`. Nothing else hardcodes it.
3. Add a `CHANGELOG.md` entry that describes what a user gets, including known
   limits and what was not tested.

## Build from a clean checkout

```sh
git worktree add /tmp/g502-release <commit>
cd /tmp/g502-release/work/opengcontrol
cargo test --workspace --locked
RUSTFLAGS="--remap-path-prefix=$HOME=~ --remap-path-prefix=/tmp/g502-release=." \
  cargo build --release --locked
cd /tmp/g502-release
RELEASE_BUILD=1 ./build.command
```

The `--remap-path-prefix` flags matter. Without them the helper embeds your home
directory and username from build-time source paths. With `RELEASE_BUILD=1` the
build script refuses to package a helper that still contains `$HOME`.

## Check the artifact

- `codesign --verify --deep --strict` passes and the version in `Info.plist`
  matches.
- The license files are in `Contents/Resources`.
- Publish the SHA-256 next to the zip: `shasum -a 256 G502X-vX.Y-V1.zip`.

The app is signed ad hoc, so macOS shows a Gatekeeper warning and every rebuild
has a new identity; say so in the release notes and give the first-launch steps.
A Developer ID signature with notarization removes both problems.

## Publish

Tag after the artifact is checked, create a draft release first, review it, then
publish. Never move or delete a published tag; ship a new patch release instead.

```sh
git tag -a vX.Y -m "G502 Stage Mouse X.Y"
git push origin vX.Y
gh release create vX.Y G502X-vX.Y-V1.zip G502X-vX.Y-V1.zip.sha256 \
  --draft --title "G502 Stage Mouse X.Y" --notes-file notes.md
```

After publishing, download the asset and test it on a clean account or another
Mac, not from your build folder. Keep the previous release available as a
rollback.
