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

for LANGUAGE in en fr; do
  /bin/mkdir -p "$APP_DIR/Contents/Resources/$LANGUAGE.lproj"
  for TABLE in Localizable InfoPlist; do
    SOURCE_TABLE="$SCRIPT_DIR/Resources/$LANGUAGE.lproj/$TABLE.strings"
    /usr/bin/plutil -lint "$SOURCE_TABLE"
    /bin/cp "$SOURCE_TABLE" "$APP_DIR/Contents/Resources/$LANGUAGE.lproj/$TABLE.strings"
  done
done

for TABLE in Localizable InfoPlist; do
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" /usr/bin/xcrun swift "$SCRIPT_DIR/work/verify_localizations.swift" \
    "$SCRIPT_DIR/Resources/en.lproj/$TABLE.strings" \
    "$SCRIPT_DIR/Resources/fr.lproj/$TABLE.strings"
done

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" /usr/bin/swiftc \
  -parse-as-library \
  "$SCRIPT_DIR/work/verify_mouse_device.swift" \
  "$SCRIPT_DIR/Sources/G502StageMouse/MouseDevice.swift" \
  -o "$MODULE_CACHE/verify_mouse_device"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" /usr/bin/swiftc \
  -parse-as-library \
  "$SCRIPT_DIR/work/verify_desktop_swipe_gesture.swift" \
  "$SCRIPT_DIR/Sources/G502StageMouse/DesktopSwipeGesture.swift" \
  -o "$MODULE_CACHE/verify_desktop_swipe_gesture"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" /usr/bin/swiftc \
  -parse-as-library \
  "$SCRIPT_DIR/work/verify_action.swift" \
  "$SCRIPT_DIR/Sources/G502StageMouse/Action.swift" \
  "$SCRIPT_DIR/Sources/G502StageMouse/Localization.swift" \
  "$SCRIPT_DIR/Sources/G502StageMouse/DesktopSwipeGesture.swift" \
  "$SCRIPT_DIR/Sources/G502StageMouse/DockNotification.swift" \
  -o "$MODULE_CACHE/verify_action"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" /usr/bin/swiftc \
  -parse-as-library \
  -sdk "$SDK" \
  -framework AppKit \
  -framework SceneKit \
  "$SCRIPT_DIR/work/verify_visual_dpi_layout.swift" \
  "$SCRIPT_DIR/Sources/G502StageMouse/VisualConfig.swift" \
  "$SCRIPT_DIR/Sources/G502StageMouse/Action.swift" \
  "$SCRIPT_DIR/Sources/G502StageMouse/DesktopSwipeGesture.swift" \
  -o "$MODULE_CACHE/verify_visual_dpi_layout"
"$MODULE_CACHE/verify_visual_dpi_layout" "$SCRIPT_DIR/Resources/fr.lproj/Localizable.strings"
"$MODULE_CACHE/verify_action"
"$MODULE_CACHE/verify_desktop_swipe_gesture"
"$MODULE_CACHE/verify_mouse_device"

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
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations array" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations:0 string en" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations:1 string fr" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string Local G502 utility" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSInputMonitoringUsageDescription string Required to read and configure buttons on the G502 X." "$APP_DIR/Contents/Info.plist"

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
/usr/bin/printf '{\n  "version": "%s",\n  "archive": "%s",\n  "sha256": "%s",\n  "notes": "Event-driven V1: timer-free hover, typing safeguards, free wheel scrolling, measured reconnection, and wake-from-sleep recovery."\n}\n' \
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
