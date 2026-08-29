#!/bin/bash
# Slay the Spire - Apple Silicon (ARM64) patch installer
#
# Replaces the x86_64 JRE + LWJGL natives of the Steam version with native
# ARM64 builds and applies the HiDPI/fullscreen patches. The original files
# are moved to SlayTheSpire-ARM64-backup/ next to the game folder so the
# patch can be fully reverted with uninstall.sh.
#
# Usage:
#   ./install.sh [--force] [path/to/SlayTheSpire.app]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD="$SCRIPT_DIR/payload"
FORCE=0
APP_ARG=""

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help)
      echo "Usage: $0 [--force] [path/to/SlayTheSpire.app]"
      exit 0 ;;
    *) APP_ARG="$arg" ;;
  esac
done

log()  { printf '[sts-arm64] %s\n' "$*"; }
fail() { printf '[sts-arm64] ERROR: %s\n' "$*" >&2; exit 1; }

# ---------- environment checks ----------
[ "$(uname -s)" = "Darwin" ] || fail "this patch only supports macOS"
[ "$(uname -m)" = "arm64" ] || fail "this Mac is not Apple Silicon (uname -m = $(uname -m))"
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 11 ] 2>/dev/null || fail "macOS 11 or later is required"
command -v zip >/dev/null || fail "zip not found"
[ -d "$PAYLOAD/jar" ] || fail "payload/jar missing - run this script from the unpacked release folder"
[ -d "$PAYLOAD/jre" ] || fail "payload/jre missing"
[ -f "$PAYLOAD/launcher" ] || fail "payload/launcher missing"
[ -f "$PAYLOAD/jar-delete.txt" ] || fail "payload/jar-delete.txt missing"
[ -f "$PAYLOAD/version.txt" ] || fail "payload/version.txt missing"
VANILLA_SHA="$(sed -n 's/^vanilla-jar-sha256=//p' "$PAYLOAD/version.txt")"
PATCH_VERSION="$(sed -n 's/^patch-version=//p' "$PAYLOAD/version.txt")"
[ -n "$VANILLA_SHA" ] || fail "version.txt is missing vanilla-jar-sha256"

# ---------- locate the game ----------
find_app() {
  local candidates=()
  if [ -n "$APP_ARG" ]; then
    candidates+=("$APP_ARG")
  else
    candidates+=("$HOME/Library/Application Support/Steam/steamapps/common/SlayTheSpire/SlayTheSpire.app")
    local vdf="$HOME/Library/Application Support/Steam/config/libraryfolders.vdf"
    if [ -f "$vdf" ]; then
      while IFS= read -r line; do
        candidates+=("$line/steamapps/common/SlayTheSpire/SlayTheSpire.app")
      done < <(sed -n 's/.*"path"[[:space:]]*"\([^"]*\)".*/\1/p' "$vdf")
    fi
  fi
  local c
  for c in "${candidates[@]}"; do
    if [ -d "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

APP="$(find_app)" || fail "SlayTheSpire.app not found. Pass the path: $0 /path/to/SlayTheSpire.app"
APP="$(cd "$APP" && pwd)"
log "found game: $APP"

CONTENTS="$APP/Contents"
RES="$CONTENTS/Resources"
MACOS_DIR="$CONTENTS/MacOS"
JAR="$RES/desktop-1.0.jar"
GAME_DIR="$(dirname "$APP")"
BACKUP="$GAME_DIR/SlayTheSpire-ARM64-backup"

[ -f "$JAR" ] || fail "desktop-1.0.jar not found inside the app - is this the Steam version?"
[ -d "$RES/jre" ] || fail "Resources/jre not found inside the app"
[ -f "$MACOS_DIR/SlayTheSpire" ] || fail "Contents/MacOS/SlayTheSpire not found"

if pgrep -f "desktop-1.0.jar" >/dev/null 2>&1; then
  fail "the game is currently running - please quit it first"
fi

# ---------- already patched? ----------
if unzip -l "$JAR" 2>/dev/null | grep -q "com/megacrit/cardcrawl/desktop/StsDisplay.class"; then
  log "this copy is already patched - nothing to do"
  log "(run uninstall.sh first if you want to re-install)"
  exit 0
fi

# ---------- vanilla version check ----------
log "verifying game version (sha256 of desktop-1.0.jar)..."
ACTUAL_SHA="$(shasum -a 256 "$JAR" | cut -d' ' -f1)"
if [ "$ACTUAL_SHA" != "$VANILLA_SHA" ]; then
  if [ "$FORCE" = "1" ]; then
    log "WARNING: game version differs from the tested build (--force given, continuing)"
  else
    fail "game version does not match the tested Steam build.
       expected sha256: $VANILLA_SHA
       actual sha256:   $ACTUAL_SHA
       The game was probably updated. Re-run with --force to patch anyway (at your own risk)."
  fi
fi

# ---------- backup (move, zero extra disk for the big files) ----------
if [ -e "$BACKUP" ]; then
  fail "backup folder already exists: $BACKUP
       Another patch installation seems to be in progress or was interrupted.
       Remove or restore that folder before continuing."
fi

rollback() {
  log "install failed - rolling back..."
  if [ -d "$BACKUP/jre" ]; then
    rm -rf "$RES/jre" 2>/dev/null || true
    mv "$BACKUP/jre" "$RES/jre" 2>/dev/null || true
  fi
  if [ -f "$BACKUP/desktop-1.0.jar" ]; then
    rm -f "$JAR" 2>/dev/null || true
    mv "$BACKUP/desktop-1.0.jar" "$JAR" 2>/dev/null || true
  fi
  [ -f "$BACKUP/SlayTheSpire" ] && cp "$BACKUP/SlayTheSpire" "$MACOS_DIR/SlayTheSpire" 2>/dev/null || true
  [ -f "$BACKUP/Info.plist" ] && cp "$BACKUP/Info.plist" "$CONTENTS/Info.plist" 2>/dev/null || true
  rmdir "$BACKUP" 2>/dev/null || true
  fail "rolled back to the original state"
}
trap rollback ERR

log "backing up original files to: $BACKUP"
mkdir "$BACKUP"
mv "$RES/jre" "$BACKUP/jre"
mv "$JAR" "$BACKUP/desktop-1.0.jar"
cp "$MACOS_DIR/SlayTheSpire" "$BACKUP/SlayTheSpire"
cp "$CONTENTS/Info.plist" "$BACKUP/Info.plist"
printf 'patch-version=%s\n' "$PATCH_VERSION" > "$BACKUP/patch-version.txt"

# ---------- patch the jar ----------
# Clone the original jar back into place (APFS copy-on-write: instant, no
# extra disk), then update the patched entries in place.
log "patching desktop-1.0.jar (793 entries)..."
cp -c "$BACKUP/desktop-1.0.jar" "$JAR" 2>/dev/null || cp "$BACKUP/desktop-1.0.jar" "$JAR"
(
  cd "$PAYLOAD/jar"
  zip -q -r "$JAR" . -x '*.DS_Store'
)
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  zip -d "$JAR" "$entry" >/dev/null 2>&1 || true
done < "$PAYLOAD/jar-delete.txt"

unzip -l "$JAR" 2>/dev/null | grep -q "com/megacrit/cardcrawl/desktop/StsDisplay.class" \
  || fail "jar verification failed after patching"

# ---------- install ARM64 JRE + launcher ----------
log "installing ARM64 JRE..."
cp -R "$PAYLOAD/jre" "$RES/jre"
chmod +x "$RES/jre/bin/java" 2>/dev/null || true

log "installing launcher..."
cp "$PAYLOAD/launcher" "$MACOS_DIR/SlayTheSpire"
chmod +x "$MACOS_DIR/SlayTheSpire"

# ---------- Info.plist: HiDPI + minimum system ----------
plutil -replace NSHighResolutionCapable -bool true "$CONTENTS/Info.plist"
plutil -replace LSMinimumSystemVersion -string "11.0" "$CONTENTS/Info.plist"

# ---------- quarantine + ad-hoc re-sign ----------
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
log "re-signing (ad-hoc)..."
codesign --force --deep -s - "$APP" 2>/dev/null || \
  log "WARNING: codesign failed - the game may still run, but report this if it does not start"

# ---------- sanity check ----------
JAVA_ARCH="$("$RES/jre/bin/java" -version 2>&1 | head -1 || true)"
[ -n "$JAVA_ARCH" ] || fail "the installed JRE does not start"
case "$("$RES/jre/bin/java" -version 2>&1)" in
  *aarch64*|*arm64*|*Zulu*) : ;;
  *) log "WARNING: could not confirm JRE architecture" ;;
esac

trap - ERR
log "done! patch $PATCH_VERSION installed."
log "original files are in: $BACKUP"
log "launch the game from Steam as usual. To revert, run uninstall.sh"
