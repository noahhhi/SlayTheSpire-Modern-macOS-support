#!/bin/bash
# Slay the Spire - Apple Silicon (ARM64) patch uninstaller
#
# Restores the original x86_64 JRE, jar, launcher and Info.plist from the
# SlayTheSpire-ARM64-backup folder created by install.sh.
#
# Usage:
#   ./uninstall.sh [path/to/SlayTheSpire.app]
set -euo pipefail

APP_ARG="${1:-}"

log()  { printf '[sts-arm64] %s\n' "$*"; }
fail() { printf '[sts-arm64] ERROR: %s\n' "$*" >&2; exit 1; }

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
CONTENTS="$APP/Contents"
RES="$CONTENTS/Resources"
MACOS_DIR="$CONTENTS/MacOS"
GAME_DIR="$(dirname "$APP")"
BACKUP="$GAME_DIR/SlayTheSpire-ARM64-backup"

[ -d "$BACKUP" ] || fail "no backup found at $BACKUP - is the patch installed?"
[ -f "$BACKUP/desktop-1.0.jar" ] || fail "backup is incomplete (desktop-1.0.jar missing)"
[ -d "$BACKUP/jre" ] || fail "backup is incomplete (jre missing)"

if pgrep -f "desktop-1.0.jar" >/dev/null 2>&1; then
  fail "the game is currently running - please quit it first"
fi

log "restoring original files from: $BACKUP"
rm -rf "$RES/jre"
mv "$BACKUP/jre" "$RES/jre"
rm -f "$RES/desktop-1.0.jar"
mv "$BACKUP/desktop-1.0.jar" "$RES/desktop-1.0.jar"
[ -f "$BACKUP/SlayTheSpire" ] && cp "$BACKUP/SlayTheSpire" "$MACOS_DIR/SlayTheSpire" && chmod +x "$MACOS_DIR/SlayTheSpire"
[ -f "$BACKUP/Info.plist" ] && cp "$BACKUP/Info.plist" "$CONTENTS/Info.plist"

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --deep -s - "$APP" 2>/dev/null || true

rm -rf "$BACKUP"
log "done - the original Steam version has been restored."
