#!/usr/bin/env bash
# Confirm an IPA is an unsigned arm64 iOS-device app with the widget extension.
# Exits non-zero for a simulator slice, a missing widget, or a broken zip.
set -euo pipefail

IPA="${1:-}"
if [[ -z "$IPA" || ! -f "$IPA" ]]; then
  echo "usage: verify-device-ipa.sh Classday-v1.ipa" >&2
  exit 2
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
unzip -t "$IPA" >/dev/null
unzip -q "$IPA" -d "$WORKDIR"

APP="$WORKDIR/Payload/Classday.app"
BIN="$APP/Classday"
APPEX="$APP/PlugIns/ClassdayWidget.appex"
WBIN="$APPEX/ClassdayWidget"

test -d "$APP"
test -x "$BIN"
test -d "$APPEX"
test -f "$WBIN"

echo "== layout =="
find "$WORKDIR/Payload" -maxdepth 3 -print | sort

echo "== file =="
file "$BIN"
file "$WBIN"
file "$BIN" | grep -q "arm64"
file "$WBIN" | grep -q "arm64"
if file "$BIN" | grep -qi "simulator"; then
  echo "app binary looks like a simulator build" >&2
  exit 1
fi

echo "== platform =="
vtool -show-build "$BIN"
vtool -show-build "$WBIN"
python3 - "$BIN" "$WBIN" <<'PY'
import subprocess, sys
for path in sys.argv[1:]:
    out = subprocess.check_output(["vtool", "-show-build", path], text=True)
    if "IOSSIMULATOR" in out:
        sys.exit(f"{path} is an iOS simulator binary")
    if "platform IOS" not in out:
        sys.exit(f"{path} has no iOS device platform")
print("platform IOS device confirmed")
PY

echo "== Info.plist =="
plutil -p "$APP/Info.plist"
plutil -p "$APPEX/Info.plist"
plutil -extract CFBundleIdentifier raw "$APP/Info.plist"
plutil -extract CFBundleIdentifier raw "$APPEX/Info.plist"
plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw "$APP/Info.plist" | grep -qx classday
plutil -extract NSExtension.NSExtensionPointIdentifier raw "$APPEX/Info.plist" | grep -qx com.apple.widgetkit-extension

echo "== signature =="
set +e
codesign -dv "$APP" 2> "$WORKDIR/app-sign.txt"
codesign -dv "$APPEX" 2> "$WORKDIR/appex-sign.txt"
set -e
cat "$WORKDIR/app-sign.txt"
cat "$WORKDIR/appex-sign.txt"
if ! grep -q "not signed" "$WORKDIR/app-sign.txt"; then
  echo "expected the app to be unsigned" >&2
  exit 1
fi
if ! grep -q "not signed" "$WORKDIR/appex-sign.txt"; then
  echo "expected the widget appex to be unsigned" >&2
  exit 1
fi

echo "unsigned arm64 iOS device IPA verified"
