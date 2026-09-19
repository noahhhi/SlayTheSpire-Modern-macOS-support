#!/bin/bash
# Offline regression for exact-build idempotency and safe refusal.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/install-state.sh"
PATCH_VERSION="$(tr -d '\r\n' < "$ROOT/VERSION")"
HOST_ARCH="$(uname -m)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sts-install-state-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

PAYLOAD="$WORK/payload"
APP="$WORK/SlayTheSpire.app"
CONTENTS="$APP/Contents"
RES="$CONTENTS/Resources"
MACOS_DIR="$CONTENTS/MacOS"
INFO="$CONTENTS/Info.plist"
DISPLAY_CONFIG="$RES/info.displayconfig"
BACKUP="$WORK/SlayTheSpire-Modern-backup"
OVERLAY="$WORK/overlay"
ORIGINAL_ROOT="$WORK/original-jar"
mkdir -p "$PAYLOAD/jre/$HOST_ARCH/bin" "$RES/jre/bin" "$MACOS_DIR" \
  "$BACKUP/jre" "$OVERLAY/patch" "$ORIGINAL_ROOT"

printf '#!/bin/bash\n[ "${1:-}" = "-version" ] || exit 2\nprintf "run\\n" >> "${STS_TEST_JAVA_LOG:?}"\n' \
  > "$PAYLOAD/jre/$HOST_ARCH/bin/java"
"$ROOT/scripts/prepare-native-launcher.sh" "$PAYLOAD/launcher" >/dev/null
printf 'patched-class\n' > "$OVERLAY/patch/Example.class"
printf 'base\n' > "$ORIGINAL_ROOT/base.txt"
printf 'delete-me\n' > "$ORIGINAL_ROOT/remove.me"
printf 'remove.me\n' > "$PAYLOAD/jar-delete.txt"
chmod +x "$PAYLOAD/jre/$HOST_ARCH/bin/java"
cp "$PAYLOAD/jre/$HOST_ARCH/bin/java" "$RES/jre/bin/java"
/usr/bin/lipo -extract "$HOST_ARCH" "$PAYLOAD/launcher" -output "$MACOS_DIR/SlayTheSpire"
chmod +x "$MACOS_DIR/SlayTheSpire"
printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0"><dict>' \
  '<key>CFBundleExecutable</key><string>SlayTheSpire</string>' \
  '<key>CFBundleIdentifier</key><string>io.github.noahhhi.sts-idempotency-test</string>' \
  '<key>NSHighResolutionCapable</key><true/>' \
  '<key>LSMinimumSystemVersion</key><string>11.0</string>' \
  '</dict></plist>' > "$INFO"
printf '1440\n900\n60\nfalse\nfalse\ntrue\n' > "$DISPLAY_CONFIG"

(
  cd "$ORIGINAL_ROOT"
  zip -q "$BACKUP/desktop-1.0.jar" base.txt remove.me
)
cp "$BACKUP/desktop-1.0.jar" "$RES/desktop-1.0.jar"
(
  cd "$OVERLAY"
  zip -q -r "$RES/desktop-1.0.jar" .
)
zip -dq "$RES/desktop-1.0.jar" remove.me
printf 'original-launcher\n' > "$BACKUP/SlayTheSpire"
printf 'original-info\n' > "$BACKUP/Info.plist"
export STS_TEST_JAVA_LOG="$WORK/java-version.log"
/usr/bin/codesign --force --deep -s - "$APP"

(
  cd "$WORK"
  find payload -type f -print | LC_ALL=C sort | while IFS= read -r path; do
    shasum -a 256 "$path"
  done > payload.sha256
)
PAYLOAD_FINGERPRINT="$(shasum -a 256 "$WORK/payload.sha256" | awk '{print $1}')"
ORIGINAL_SHA="$(shasum -a 256 "$BACKUP/desktop-1.0.jar" | awk '{print $1}')"

sts_record_install_state "$BACKUP" "$PATCH_VERSION" "$PAYLOAD_FINGERPRINT" \
  "$ORIGINAL_SHA" "$RES/desktop-1.0.jar" "$RES/jre" \
  "$MACOS_DIR/SlayTheSpire" "$INFO" "$OVERLAY"
[ -s "$BACKUP/install-manifest.txt" ] \
  && [ -s "$BACKUP/installed-jre.sha256" ] \
  && [ -s "$BACKUP/installed-overlay.sha256" ]
echo 'first install: state recorded successfully'

sts_verify_installed_state "$BACKUP" "$PATCH_VERSION" "$PAYLOAD_FINGERPRINT" \
  "$WORK/payload.sha256" "$PAYLOAD" "$RES/desktop-1.0.jar" "$RES" \
  "$MACOS_DIR" "$APP" "$INFO" "$HOST_ARCH" "$PAYLOAD/jar-delete.txt"
[ "$(wc -l < "$STS_TEST_JAVA_LOG" | tr -d ' ')" -eq 1 ]
echo 'same build repeat: accepted as already installed'

sts_verify_recorded_install_state "$BACKUP" "$RES/desktop-1.0.jar" "$RES" \
  "$MACOS_DIR" "$INFO" "$HOST_ARCH"
[ "$(wc -l < "$STS_TEST_JAVA_LOG" | tr -d ' ')" -eq 2 ]
echo 'recorded prior build: accepted for a verified upgrade'

if sts_verify_installed_state "$BACKUP" "$PATCH_VERSION" \
  'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff' \
  "$WORK/payload.sha256" "$PAYLOAD" "$RES/desktop-1.0.jar" "$RES" \
  "$MACOS_DIR" "$APP" "$INFO" "$HOST_ARCH" "$PAYLOAD/jar-delete.txt"; then
  echo 'different build was incorrectly accepted' >&2
  exit 1
fi
[ "$STS_STATE_ERROR" = 'installed payload fingerprint differs' ]
echo 'same version different build: safely refused'

printf '1280\n800\n60\ntrue\nfalse\ntrue\n' > "$DISPLAY_CONFIG"
sts_verify_installed_state "$BACKUP" "$PATCH_VERSION" "$PAYLOAD_FINGERPRINT" \
  "$WORK/payload.sha256" "$PAYLOAD" "$RES/desktop-1.0.jar" "$RES" \
  "$MACOS_DIR" "$APP" "$INFO" "$HOST_ARCH" "$PAYLOAD/jar-delete.txt"
echo 'mutable game display config: accepted after launch'

cp "$INFO" "$WORK/installed-Info.plist"
printf '<!-- tampered -->\n' >> "$INFO"
if sts_verify_installed_state "$BACKUP" "$PATCH_VERSION" "$PAYLOAD_FINGERPRINT" \
  "$WORK/payload.sha256" "$PAYLOAD" "$RES/desktop-1.0.jar" "$RES" \
  "$MACOS_DIR" "$APP" "$INFO" "$HOST_ARCH" "$PAYLOAD/jar-delete.txt"; then
  echo 'tampered Info.plist was incorrectly accepted' >&2
  exit 1
fi
[ "$STS_STATE_ERROR" = 'installed Info.plist differs from the completed install' ]
echo 'tampered Info.plist: safely refused'
cp "$WORK/installed-Info.plist" "$INFO"

rm "$MACOS_DIR/SlayTheSpire"
if sts_verify_installed_state "$BACKUP" "$PATCH_VERSION" "$PAYLOAD_FINGERPRINT" \
  "$WORK/payload.sha256" "$PAYLOAD" "$RES/desktop-1.0.jar" "$RES" \
  "$MACOS_DIR" "$APP" "$INFO" "$HOST_ARCH" "$PAYLOAD/jar-delete.txt"; then
  echo 'partial install was incorrectly accepted' >&2
  exit 1
fi
[ "$STS_STATE_ERROR" = 'installed launcher differs' ]
echo 'partial install: safely refused'
echo 'install idempotency offline regression passed'
