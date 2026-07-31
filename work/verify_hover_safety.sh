#!/bin/zsh
set -euo pipefail

SOURCE=${1:-Sources/G502StageMouse/main.swift}
ARCHIVE=${2:-build/G502X-v14.7-V1.zip}
EXPECTED_VERSION=${3:-14.7}

for FORBIDDEN in \
  'activateAllWindows' \
  'startHoverPolling' \
  'pollHoverPointer' \
  'hoverRecoveryTimer' \
  'hoverRecoveryInterval' \
  'kAXRaiseAction' \
  'CGWarpMouseCursorPosition' \
  'CGDisplayMoveCursorToPoint' \
  'NSCursor.hide' \
  'CGDisplayHideCursor'; do
  if /usr/bin/grep -q "$FORBIDDEN" "$SOURCE"; then
    echo "FAIL: ancien comportement dangereux ou périodique détecté: $FORBIDDEN"
    exit 1
  fi
done

if /usr/bin/grep -Eq 'NSRunningApplication.*activate|\.activate\(options:' "$SOURCE"; then
  echo "FAIL: activation explicite d’application détectée."
  exit 1
fi

for REQUIRED in \
  'hoverRecoveryKeyboardQuietPeriod' \
  'startHoverEventTap' \
  'options: .listenOnly' \
  'keyboardInputIsRecent' \
  'anyMouseButtonPressed' \
  'otherMouseDragged' \
  'freeScrollActivationDistance' \
  'handleFreeScrollDrag' \
  'postFreeScroll' \
  'resetFreeScrollTracking' \
  'syntheticMouseEventMarker'; do
  if ! /usr/bin/grep -q "$REQUIRED" "$SOURCE"; then
    echo "FAIL: garde-fou ou fonction V1 manquante: $REQUIRED"
    exit 1
  fi
done

HOVER_SECTION=$(/usr/bin/sed -n \
  '/private func scheduleHoverRecoveryAfterClick/,/private func handleFreeScrollButton/p' \
  "$SOURCE")
if /usr/bin/printf '%s\n' "$HOVER_SECTION" \
  | /usr/bin/grep -Eq 'mouseDown|mouseUp|scrollWheel|activate|kAXRaise|Warp|HideCursor'; then
  echo "FAIL: le chemin de récupération du survol contient une interaction interdite."
  exit 1
fi

/usr/bin/unzip -t "$ARCHIVE" >/dev/null
TEMP_DIR=$(/usr/bin/mktemp -d /private/tmp/g502-v1-safety.XXXXXX)
trap '/bin/rm -rf "$TEMP_DIR"' EXIT
/usr/bin/ditto -x -k "$ARCHIVE" "$TEMP_DIR"
APP="$TEMP_DIR/G502 Stage Mouse.app"

/usr/bin/codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
if [[ "$VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "FAIL: archive inattendue, version $VERSION au lieu de $EXPECTED_VERSION."
  exit 1
fi

echo "PASS: v$EXPECTED_VERSION événementielle, sans activation de fenêtre ni timer hover; scroll molette et protections clavier/drag présents."
