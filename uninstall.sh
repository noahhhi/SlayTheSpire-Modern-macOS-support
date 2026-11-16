#!/bin/bash
# Restores the exact Steam files preserved by install.sh.
set -euo pipefail

APP_ARG="${1:-}"
log()  { printf '[sts-modern] %s\n' "$*"; }
fail() { printf '[sts-modern] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "this uninstaller only supports macOS"

find_app() {
  local candidates=()
  local vdf path c
  if [ -n "$APP_ARG" ]; then
    candidates+=("$APP_ARG")
  else
    candidates+=("$HOME/Library/Application Support/Steam/steamapps/common/SlayTheSpire/SlayTheSpire.app")
    vdf="$HOME/Library/Application Support/Steam/config/libraryfolders.vdf"
    if [ -f "$vdf" ]; then
      while IFS= read -r path; do
        path="${path//\\\\/\\}"
        candidates+=("$path/steamapps/common/SlayTheSpire/SlayTheSpire.app")
      done < <(sed -n 's/.*"path"[[:space:]]*"\([^"]*\)".*/\1/p' "$vdf")
    fi
  fi
  for c in "${candidates[@]}"; do
    [ -d "$c/Contents/Resources" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

APP="$(find_app)" || fail "SlayTheSpire.app was not found; pass its full path"
APP="$(cd "$APP" && pwd -P)"
CONTENTS="$APP/Contents"
RES="$CONTENTS/Resources"
MACOS_DIR="$CONTENTS/MacOS"
GAME_DIR="$(dirname "$APP")"
BACKUP="$GAME_DIR/SlayTheSpire-Modern-backup"

[ -d "$BACKUP" ] || fail "no Universal patch backup exists at $BACKUP"
[ -f "$BACKUP/desktop-1.0.jar" ] || fail "backup is incomplete: desktop-1.0.jar is missing"
[ -d "$BACKUP/jre" ] || fail "backup is incomplete: jre is missing"
[ -f "$BACKUP/SlayTheSpire" ] || fail "backup is incomplete: launcher is missing"
[ -f "$BACKUP/Info.plist" ] || fail "backup is incomplete: Info.plist is missing"

if /usr/sbin/lsof -t -- "$RES/desktop-1.0.jar" "$RES/mts-launcher.jar" >/dev/null 2>&1; then
  fail "the game is running; quit it before uninstalling"
fi

# Validate the new optional backup before moving any live files. Older releases
# have no MTS backup and must leave the user's launcher untouched.
MTS_EXPECTED="$(sed -n 's/^original-mts-launcher-sha256=//p' "$BACKUP/install-manifest.txt")"
if [ -n "$MTS_EXPECTED" ]; then
  [ -f "$BACKUP/mts-launcher.jar" ] && [ ! -L "$BACKUP/mts-launcher.jar" ] \
    || fail "original mts-launcher.jar backup is missing or invalid"
  [ "$(shasum -a 256 "$BACKUP/mts-launcher.jar" | awk '{print $1}')" = "$MTS_EXPECTED" ] \
    || fail "original mts-launcher.jar backup checksum mismatch"
fi

TRASH="$GAME_DIR/.SlayTheSpire-Modern-remove.$$"
[ ! -e "$TRASH" ] || fail "temporary restore path already exists: $TRASH"
mkdir "$TRASH"

RESTORE_NEEDED=1
cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  set +e
  if [ "$RESTORE_NEEDED" = "1" ]; then
    log "restore did not complete; returning to the patched state..."
    [ -e "$TRASH/jre" ] && { rm -rf "$RES/jre"; mv "$TRASH/jre" "$RES/jre"; }
    [ -e "$TRASH/desktop-1.0.jar" ] && { rm -f "$RES/desktop-1.0.jar"; mv "$TRASH/desktop-1.0.jar" "$RES/desktop-1.0.jar"; }
    [ ! -f "$TRASH/mts-launcher.jar" ] || cp -p "$TRASH/mts-launcher.jar" "$RES/mts-launcher.jar"
    [ -f "$TRASH/SlayTheSpire" ] && cp -p "$TRASH/SlayTheSpire" "$MACOS_DIR/SlayTheSpire"
    [ -f "$TRASH/Info.plist" ] && cp -p "$TRASH/Info.plist" "$CONTENTS/Info.plist"
    rm -rf "$CONTENTS/_CodeSignature"
    rm -f "$CONTENTS/CodeResources"
    [ -d "$TRASH/_CodeSignature" ] && cp -R "$TRASH/_CodeSignature" "$CONTENTS/_CodeSignature"
    [ -f "$TRASH/CodeResources" ] && cp -p "$TRASH/CodeResources" "$CONTENTS/CodeResources"
  fi
  rm -rf "$TRASH"
  exit "$rc"
}
trap cleanup EXIT INT TERM HUP

log "restoring the exact original Steam files from $BACKUP"
mv "$RES/jre" "$TRASH/jre"
mv "$RES/desktop-1.0.jar" "$TRASH/desktop-1.0.jar"
cp -p "$MACOS_DIR/SlayTheSpire" "$TRASH/SlayTheSpire"
cp -p "$CONTENTS/Info.plist" "$TRASH/Info.plist"
[ ! -d "$CONTENTS/_CodeSignature" ] || cp -R "$CONTENTS/_CodeSignature" "$TRASH/_CodeSignature"
[ ! -f "$CONTENTS/CodeResources" ] || cp -p "$CONTENTS/CodeResources" "$TRASH/CodeResources"

if [ -n "$MTS_EXPECTED" ]; then
  cp -p "$RES/mts-launcher.jar" "$TRASH/mts-launcher.jar"
  cp -p "$BACKUP/mts-launcher.jar" "$RES/mts-launcher.jar"
fi
# Copy preserved originals until the complete restore has passed verification.
cp -R "$BACKUP/jre" "$RES/jre"
cp -p "$BACKUP/desktop-1.0.jar" "$RES/desktop-1.0.jar"
cp -p "$BACKUP/SlayTheSpire" "$MACOS_DIR/SlayTheSpire"
chmod +x "$MACOS_DIR/SlayTheSpire"
cp -p "$BACKUP/Info.plist" "$CONTENTS/Info.plist"
rm -rf "$CONTENTS/_CodeSignature"
rm -f "$CONTENTS/CodeResources"
[ ! -d "$BACKUP/_CodeSignature" ] || cp -R "$BACKUP/_CodeSignature" "$CONTENTS/_CodeSignature"
[ ! -f "$BACKUP/CodeResources" ] || cp -p "$BACKUP/CodeResources" "$CONTENTS/CodeResources"

if [ "${STS_TEST_FAIL_AFTER_RESTORE:-0}" = 1 ]; then
  fail 'injected restore failure for rollback verification'
fi

if [ -f "$BACKUP/BaseMod.jar" ]; then
  BASEMOD_JAR="$(dirname "$(dirname "$GAME_DIR")")/workshop/content/646570/1605833019/BaseMod.jar"
  [ ! -f "$BASEMOD_JAR" ] || cp -p "$BACKUP/BaseMod.jar" "$BASEMOD_JAR"
fi

EXPECTED_SHA="$(sed -n 's/^original-jar-sha256=//p' "$BACKUP/install-manifest.txt" 2>/dev/null || true)"
RESTORED_SHA="$(shasum -a 256 "$RES/desktop-1.0.jar" | awk '{print $1}')"
[ -z "$EXPECTED_SHA" ] || [ "$RESTORED_SHA" = "$EXPECTED_SHA" ] \
  || fail "restored jar checksum mismatch; patched state will be put back"

RESTORE_NEEDED=0
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ ! -x "$LSREGISTER" ] || "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
rm -rf "$BACKUP" "$TRASH"
trap - EXIT INT TERM HUP
log "uninstall complete; the original Steam version has been restored"
