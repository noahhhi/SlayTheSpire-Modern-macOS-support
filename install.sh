#!/bin/bash
# Slay the Spire modern macOS patch installer (Intel + Apple Silicon).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD="$SCRIPT_DIR/payload"
SUPPORTED_HASHES="$SCRIPT_DIR/supported-versions.sha256"
PAYLOAD_MANIFEST="$SCRIPT_DIR/payload.sha256"
APP_ARG=""
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh [--dry-run] [path/to/SlayTheSpire.app]

  --dry-run  Locate and validate the game and build a candidate patched jar,
             but do not modify the application.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    --*) printf 'Unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
    *)
      [ -z "$APP_ARG" ] || { printf 'Only one app path may be supplied.\n' >&2; exit 2; }
      APP_ARG="$arg"
      ;;
  esac
done

log()  { printf '[sts-modern] %s\n' "$*"; }
fail() { printf '[sts-modern] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "this patch only supports macOS"
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  arm64|x86_64) ;;
  *) fail "unsupported Mac architecture: $HOST_ARCH" ;;
esac

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 11 ] 2>/dev/null || fail "macOS 11 or later is required"
for tool in codesign plutil shasum unzip zip; do
  tool_path="$(command -v "$tool" 2>/dev/null || true)"
  [ -n "$tool_path" ] && [ -x "$tool_path" ] || fail "required executable tool not found: $tool"
done
[ -x /usr/bin/lipo ] || fail "required system tool is missing: /usr/bin/lipo"
[ -x /usr/sbin/lsof ] || fail "required system tool is missing: /usr/sbin/lsof"
[ -d "$PAYLOAD/jar" ] || fail "payload/jar is missing; use the complete release archive"
[ -d "$PAYLOAD/jre/$HOST_ARCH" ] || fail "payload/jre/$HOST_ARCH is missing"
[ -f "$PAYLOAD/launcher" ] || fail "payload/launcher is missing"
[ -f "$PAYLOAD/jar-delete.txt" ] || fail "payload/jar-delete.txt is missing"
[ -f "$SCRIPT_DIR/VERSION" ] || fail "VERSION is missing"
[ -f "$SUPPORTED_HASHES" ] || fail "supported-versions.sha256 is missing"
[ -f "$PAYLOAD_MANIFEST" ] || fail "payload.sha256 is missing; use a packaged Release asset"

log "verifying patch payload..."
(cd "$SCRIPT_DIR" && shasum -a 256 -c "$(basename "$PAYLOAD_MANIFEST")") >/dev/null \
  || fail "patch payload checksum verification failed; download the Release asset again"

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
    if [ -d "$c/Contents/Resources" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

APP="$(find_app)" || fail "SlayTheSpire.app was not found; pass its full path to install.sh"
APP="$(cd "$APP" && pwd -P)"
CONTENTS="$APP/Contents"
RES="$CONTENTS/Resources"
MACOS_DIR="$CONTENTS/MacOS"
JAR="$RES/desktop-1.0.jar"
GAME_DIR="$(dirname "$APP")"
BACKUP="$GAME_DIR/SlayTheSpire-Modern-backup"
LEGACY_BACKUP="$GAME_DIR/SlayTheSpire-ARM64-backup"
WORK="$GAME_DIR/.SlayTheSpire-Modern-install.$$"
PATCH_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"

log "found game: $APP"
[ -f "$JAR" ] || fail "desktop-1.0.jar is missing; this is not the supported Steam app"
[ -d "$RES/jre" ] || fail "the original Resources/jre is missing"
[ -f "$MACOS_DIR/SlayTheSpire" ] || fail "the original launcher is missing"
[ -f "$CONTENTS/Info.plist" ] || fail "Info.plist is missing"
[ ! -e "$BACKUP" ] || fail "the patch is already installed (backup exists at $BACKUP); run uninstall.sh first"
[ ! -e "$LEGACY_BACKUP" ] || fail "the legacy ARM64 patch is installed; run its uninstall.sh before installing this Universal release"
[ ! -e "$WORK" ] || fail "stale installer work directory exists: $WORK"

if /usr/sbin/lsof -t -- "$JAR" >/dev/null 2>&1; then
  fail "the game is running; quit it before installing"
fi

log "verifying the unmodified Steam jar..."
ACTUAL_SHA="$(shasum -a 256 "$JAR" | awk '{print $1}')"
if ! awk -v hash="$ACTUAL_SHA" '$1 == hash { found=1 } END { exit !found }' "$SUPPORTED_HASHES"; then
  fail "unsupported or modified desktop-1.0.jar (sha256: $ACTUAL_SHA). Use Steam > Properties > Installed Files > Verify integrity, then retry."
fi

ROLLBACK_NEEDED=0
cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  set +e
  if [ "$ROLLBACK_NEEDED" = "1" ]; then
    log "installation did not complete; restoring the original files..."
    [ -e "$BACKUP/jre" ] && { rm -rf "$RES/jre"; mv "$BACKUP/jre" "$RES/jre"; }
    [ -e "$BACKUP/desktop-1.0.jar" ] && { rm -f "$JAR"; mv "$BACKUP/desktop-1.0.jar" "$JAR"; }
    [ -f "$BACKUP/SlayTheSpire" ] && cp -p "$BACKUP/SlayTheSpire" "$MACOS_DIR/SlayTheSpire"
    [ -f "$BACKUP/Info.plist" ] && cp -p "$BACKUP/Info.plist" "$CONTENTS/Info.plist"
    rm -rf "$CONTENTS/_CodeSignature"
    rm -f "$CONTENTS/CodeResources"
    [ -d "$BACKUP/_CodeSignature" ] && cp -R "$BACKUP/_CodeSignature" "$CONTENTS/_CodeSignature"
    [ -f "$BACKUP/CodeResources" ] && cp -p "$BACKUP/CodeResources" "$CONTENTS/CodeResources"
    rm -rf "$BACKUP"
  fi
  rm -rf "$WORK"
  exit "$rc"
}
trap cleanup EXIT INT TERM HUP

mkdir -p "$WORK/jar-overlay" "$WORK/original-natives" "$WORK/staged"
cp -R "$PAYLOAD/jar/." "$WORK/jar-overlay/"

# The verified Steam jar already ships a signed i386/x86_64/arm64 Steam API.
# Preserve those exact bytes and its hardened-runtime signature. Replacing it
# with a locally thinned/ad-hoc copy breaks Rosetta's AOT signature supplement.
rm -f "$WORK/jar-overlay/libsteam_api.dylib" "$WORK/jar-overlay/libsteam_api.dylib.sha1"

# Public release assets contain only patch-native arm64 slices. The x86_64
# slices are taken from this user's hash-verified Steam jar and combined into
# Universal binaries locally, so no original game binary is redistributed.
UNIVERSAL_NATIVES=(
  libgdx-controllers-desktop64.dylib
  libgdx-freetype64.dylib
  libgdx64.dylib
  liblwjgl.dylib
  libsteamworks4j.dylib
  openal.dylib
)
log "assembling Universal LWJGL/libGDX natives from patch + verified original slices..."
for native in "${UNIVERSAL_NATIVES[@]}"; do
  patched="$WORK/jar-overlay/$native"
  [ -f "$patched" ] || fail "patch native is missing: $native"
  patched_archs="$(/usr/bin/lipo -archs "$patched" 2>/dev/null || true)"
  case " $patched_archs " in *" arm64 "*) ;; *) fail "$native has no arm64 slice" ;; esac

  if [ "$native" = 'liblwjgl.dylib' ]; then
    printf ' %s ' "$patched_archs" | grep -q ' x86_64 ' \
      || fail "patched liblwjgl.dylib is not Universal; its new fullscreen JNI requires patched arm64 and x86_64 slices"
  else
    unzip -p "$JAR" "$native" > "$WORK/original-natives/$native" \
      || fail "the verified Steam jar has no $native"
    original_archs="$(/usr/bin/lipo -archs "$WORK/original-natives/$native" 2>/dev/null || true)"
    case " $original_archs " in *" x86_64 "*) ;; *) fail "original $native has no x86_64 slice" ;; esac
    /usr/bin/lipo -extract arm64 "$patched" -output "$WORK/jar-overlay/$native.arm64"
    /usr/bin/lipo -extract x86_64 "$WORK/original-natives/$native" -output "$WORK/jar-overlay/$native.x86_64"
    /usr/bin/lipo -create "$WORK/jar-overlay/$native.arm64" "$WORK/jar-overlay/$native.x86_64" \
      -output "$WORK/jar-overlay/$native.universal"
    rm -f "$WORK/jar-overlay/$native.arm64" "$WORK/jar-overlay/$native.x86_64"
    mv "$WORK/jar-overlay/$native.universal" "$patched"
  fi

  final_archs="$(/usr/bin/lipo -archs "$patched")"
  case " $final_archs " in *" arm64 "*) ;; *) fail "$native Universal verification lost arm64" ;; esac
  case " $final_archs " in *" x86_64 "*) ;; *) fail "$native Universal verification lost x86_64" ;; esac
  codesign --force -s - "$patched"
  codesign --verify --strict "$patched" || fail "$native ad-hoc signature verification failed"
  printf '%s\r\n' "$(shasum -a 1 "$patched" | awk '{print $1}')" > "$patched.sha1"
done

log "building and testing the candidate patched jar..."
cp -c "$JAR" "$WORK/staged/desktop-1.0.jar" 2>/dev/null || cp -p "$JAR" "$WORK/staged/desktop-1.0.jar"
(
  cd "$WORK/jar-overlay"
  zip -q -r "$WORK/staged/desktop-1.0.jar" . -x '*.DS_Store' -x '._*'
)
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  zip -d "$WORK/staged/desktop-1.0.jar" "$entry" >/dev/null 2>&1 || true
done < "$PAYLOAD/jar-delete.txt"
unzip -tq "$WORK/staged/desktop-1.0.jar" >/dev/null || fail "candidate jar integrity test failed"

mkdir "$WORK/staged/jre"
cp -R "$PAYLOAD/jre/$HOST_ARCH/." "$WORK/staged/jre/"
chmod +x "$WORK/staged/jre/bin/java"
JRE_ARCHS="$(/usr/bin/lipo -archs "$WORK/staged/jre/bin/java" 2>/dev/null || true)"
case " $JRE_ARCHS " in *" $HOST_ARCH "*) ;; *) fail "bundled Zulu JRE does not support $HOST_ARCH" ;; esac

if [ "$DRY_RUN" = "1" ]; then
  log "dry run passed: supported Steam jar, $HOST_ARCH Zulu JRE, and Universal native slices verified"
  exit 0
fi

log "backing up original runtime, jar, launcher, and Info.plist to $BACKUP"
mkdir "$BACKUP"
ROLLBACK_NEEDED=1
mv "$RES/jre" "$BACKUP/jre"
mv "$JAR" "$BACKUP/desktop-1.0.jar"
cp -p "$MACOS_DIR/SlayTheSpire" "$BACKUP/SlayTheSpire"
cp -p "$CONTENTS/Info.plist" "$BACKUP/Info.plist"
[ ! -d "$CONTENTS/_CodeSignature" ] || cp -R "$CONTENTS/_CodeSignature" "$BACKUP/_CodeSignature"
[ ! -f "$CONTENTS/CodeResources" ] || cp -p "$CONTENTS/CodeResources" "$BACKUP/CodeResources"
printf 'patch-version=%s\noriginal-jar-sha256=%s\n' "$PATCH_VERSION" "$ACTUAL_SHA" > "$BACKUP/install-manifest.txt"

mv "$WORK/staged/jre" "$RES/jre"
mv "$WORK/staged/desktop-1.0.jar" "$JAR"
cp -p "$PAYLOAD/launcher" "$MACOS_DIR/SlayTheSpire"
chmod +x "$MACOS_DIR/SlayTheSpire"
plutil -replace NSHighResolutionCapable -bool true "$CONTENTS/Info.plist"
plutil -replace LSMinimumSystemVersion -string '11.0' "$CONTENTS/Info.plist"

xattr -dr com.apple.quarantine "$RES/jre" "$JAR" "$MACOS_DIR/SlayTheSpire" 2>/dev/null || true
log "applying an ad-hoc signature..."
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"
"$RES/jre/bin/java" -version >/dev/null 2>&1 || fail "installed $HOST_ARCH JRE failed its launch test"

ROLLBACK_NEEDED=0
log "patch $PATCH_VERSION installed successfully for $HOST_ARCH"
log "the original files are preserved at: $BACKUP"
log "launch the game from Steam; run uninstall.sh to restore the exact originals"
