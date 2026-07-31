#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
APP_NAME="G502 Stage Mouse"
APP_VERSION="14.7"
BUILD_NUMBER="147"
BUILD_DIR="$SCRIPT_DIR/build"
STAGING_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/g502-stage-mouse-build.XXXXXX")
APP_DIR="$STAGING_DIR/$APP_NAME.app"
MODULE_CACHE="$BUILD_DIR/module-cache"
ARCHIVE_NAME="G502X-v14.7-V1.zip"
ARCHIVE="$BUILD_DIR/$ARCHIVE_NAME"
MANIFEST="$BUILD_DIR/manifest.json"
LOCAL_UPDATE_DIR="$HOME/Library/Application Support/G502StageMouse/Updates"
SDK=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
HELPER_BIN="$SCRIPT_DIR/work/opengcontrol/target/release/opengcontrol"

if [[ ! -x "$HELPER_BIN" ]]; then
  echo "Module HID++ manquant : $HELPER_BIN"
  exit 1
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" /usr/bin/swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macosx13.0 \
  -O \
  -framework AppKit \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -framework SceneKit \
  "$SCRIPT_DIR"/Sources/G502StageMouse/*.swift \
  -o "$APP_DIR/Contents/MacOS/G502StageMouse"

/bin/cp "$HELPER_BIN" "$APP_DIR/Contents/MacOS/opengcontrol"
/bin/chmod 755 "$APP_DIR/Contents/MacOS/opengcontrol"
/bin/cp "$SCRIPT_DIR/THIRD-PARTY-NOTICES.txt" "$APP_DIR/Contents/Resources/THIRD-PARTY-NOTICES.txt"
/bin/cp "$SCRIPT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE.txt"
/bin/cp "$SCRIPT_DIR/ASSET-LICENSES.md" "$APP_DIR/Contents/Resources/ASSET-LICENSES.md"
/bin/cp "$SCRIPT_DIR/work/opengcontrol/LICENSES/MIT.txt" "$APP_DIR/Contents/Resources/opengcontrol-LICENSE-MIT.txt"
/bin/cp "$SCRIPT_DIR/Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
/bin/cp "$SCRIPT_DIR/Assets/mouse.usdz" "$APP_DIR/Contents/Resources/mouse.usdz"

/usr/libexec/PlistBuddy -c "Clear dict" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string fr.remy.g502stagemouse" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string G502StageMouse" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string Utilitaire local G502" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSInputMonitoringUsageDescription string Nécessaire pour lire et configurer les boutons de la G502 X LIGHTSPEED." "$APP_DIR/Contents/Info.plist"

/usr/bin/xattr -cr "$APP_DIR"
/usr/bin/codesign --force --sign - "$APP_DIR/Contents/MacOS/opengcontrol"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
/bin/mkdir -p "$BUILD_DIR"
/bin/rm -f "$ARCHIVE"
(
  cd "$STAGING_DIR"
  /usr/bin/zip -qry -X "$ARCHIVE" "$APP_NAME.app"
)
CHECKSUM=$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/cut -d ' ' -f 1)
/usr/bin/printf '{\n  "version": "%s",\n  "archive": "%s",\n  "sha256": "%s",\n  "notes": "V1 événementielle : survol sans timer, protection de la saisie, défilement libre à la molette, reconnexion sobre et reprise après veille."\n}\n' \
  "$APP_VERSION" "$ARCHIVE_NAME" "$CHECKSUM" > "$MANIFEST"

"$SCRIPT_DIR/work/verify_hover_safety.sh" \
  "$SCRIPT_DIR/Sources/G502StageMouse/main.swift" \
  "$ARCHIVE" \
  "$APP_VERSION"

if [[ "${PUBLISH_LOCAL_UPDATE:-0}" != "1" ]]; then
  echo "Canal de mise à jour inchangé (canary non publiée)."
elif /bin/mkdir -p "$LOCAL_UPDATE_DIR" 2>/dev/null \
  && /bin/cp -f "$ARCHIVE" "$LOCAL_UPDATE_DIR/$ARCHIVE_NAME" 2>/dev/null \
  && /bin/cp -f "$MANIFEST" "$LOCAL_UPDATE_DIR/manifest.json.tmp" 2>/dev/null \
  && /bin/mv -f "$LOCAL_UPDATE_DIR/manifest.json.tmp" "$LOCAL_UPDATE_DIR/manifest.json" 2>/dev/null; then
  echo "Canal de mise à jour local actualisé explicitement."
else
  echo "Canal de mise à jour local inaccessible ; l’archive reste disponible dans build."
fi
echo "Archive $APP_VERSION créée : $ARCHIVE"
echo "Décompressez-la, glissez l’app dans /Applications, puis accordez l’autorisation Accessibilité."
