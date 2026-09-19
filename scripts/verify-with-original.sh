#!/bin/bash
# Release gate requiring the user's hash-verified original Steam backup.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIGINAL="${1:-}"
PREVIOUS_ZIP="${2:-}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
CURRENT_ZIP="$ROOT/dist/SlayTheSpire-Modern-macOS-v${VERSION}-universal.zip"

[ -d "$ORIGINAL/jre" ] \
  && [ -f "$ORIGINAL/desktop-1.0.jar" ] \
  && [ -f "$ORIGINAL/SlayTheSpire" ] \
  && [ -f "$ORIGINAL/Info.plist" ] || {
  echo 'usage: verify-with-original.sh ORIGINAL_BACKUP_DIR [PREVIOUS_RELEASE_ZIP]' >&2
  exit 2
}
[ -f "$CURRENT_ZIP" ] || { echo "build the current release first: $CURRENT_ZIP" >&2; exit 2; }
[ -z "$PREVIOUS_ZIP" ] || [ -f "$PREVIOUS_ZIP" ] \
  || { echo "previous release ZIP not found: $PREVIOUS_ZIP" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sts-original-gate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
unzip -q "$CURRENT_ZIP" -d "$WORK/current"

make_original_app() {
  local app="$1"
  mkdir -p "$app/Contents/Resources" "$app/Contents/MacOS"
  cp -c "$ORIGINAL/desktop-1.0.jar" "$app/Contents/Resources/desktop-1.0.jar" \
    2>/dev/null || cp -p "$ORIGINAL/desktop-1.0.jar" "$app/Contents/Resources/desktop-1.0.jar"
  cp -cR "$ORIGINAL/jre" "$app/Contents/Resources/jre" 2>/dev/null \
    || cp -R "$ORIGINAL/jre" "$app/Contents/Resources/jre"
  cp -p "$ORIGINAL/SlayTheSpire" "$app/Contents/MacOS/SlayTheSpire"
  cp -p "$ORIGINAL/Info.plist" "$app/Contents/Info.plist"
}

for arch in arm64 x86_64; do
  app="$WORK/dry-run-$arch/SlayTheSpire.app"
  make_original_app "$app"
  STS_TEST_HOST_ARCH="$arch" "$WORK/current/install.sh" --dry-run "$app"
done

if [ -n "$PREVIOUS_ZIP" ]; then
  unzip -q "$PREVIOUS_ZIP" -d "$WORK/previous-release"
  upgrade_app="$WORK/upgrade/SlayTheSpire.app"
  make_original_app "$upgrade_app"
  "$WORK/previous-release/install.sh" "$upgrade_app"
  backup="$WORK/upgrade/SlayTheSpire-Modern-backup"
  original_sha="$(shasum -a 256 "$backup/desktop-1.0.jar" | awk '{print $1}')"
  before_digest="$({
    cd "$WORK/upgrade"
    find . -type f -print | LC_ALL=C sort | while IFS= read -r path; do
      shasum -a 256 "$path"
    done
  } | shasum -a 256 | awk '{print $1}')"
  set +e
  STS_TEST_FAIL_AFTER_REPLACEMENT=1 "$WORK/current/install.sh" "$upgrade_app"
  rollback_status=$?
  set -e
  [ "$rollback_status" -ne 0 ] || { echo 'rollback injection unexpectedly succeeded' >&2; exit 1; }
  after_digest="$({
    cd "$WORK/upgrade"
    find . -type f -print | LC_ALL=C sort | while IFS= read -r path; do
      shasum -a 256 "$path"
    done
  } | shasum -a 256 | awk '{print $1}')"
  [ "$after_digest" = "$before_digest" ] \
    || { echo 'failed upgrade did not restore the previous tree exactly' >&2; exit 1; }
  "$WORK/previous-release/install.sh" "$upgrade_app"
  "$WORK/current/install.sh" "$upgrade_app"
  [ "$(shasum -a 256 "$backup/desktop-1.0.jar" | awk '{print $1}')" = "$original_sha" ]
  [ "$(sed -n 's/^patch-version=//p' "$backup/install-manifest.txt")" = "$VERSION" ]
  "$ROOT/scripts/test-host-native-jar.sh" \
    "$upgrade_app/Contents/Resources/desktop-1.0.jar" "$(uname -m)"
  "$WORK/current/install.sh" "$upgrade_app"
fi

echo 'original-Steam release gate passed for arm64, x86_64, and requested upgrade path'
