#!/bin/bash
# Slay the Spire modern macOS patch installer (Intel + Apple Silicon).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD="$SCRIPT_DIR/payload"
SUPPORTED_HASHES="$SCRIPT_DIR/supported-versions.sha256"
SUPPORTED_UPGRADES="$SCRIPT_DIR/supported-upgrades.sha256"
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
# Release verification may exercise the non-host branch without executing its
# binaries. The override is deliberately restricted to a no-write dry run.
if [ "$DRY_RUN" = 1 ] && [ -n "${STS_TEST_HOST_ARCH:-}" ]; then
  HOST_ARCH="$STS_TEST_HOST_ARCH"
fi
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
[ -f "$PAYLOAD/mts/com/megacrit/mtslauncher/MtsFinder.class" ] || fail "local Workshop shim is missing"
[ -f "$SCRIPT_DIR/supported-mts-launchers.sha256" ] || fail "supported-mts-launchers.sha256 is missing"
[ -f "$PAYLOAD/launcher" ] || fail "payload/launcher is missing"
[ -f "$PAYLOAD/jar-delete.txt" ] || fail "payload/jar-delete.txt is missing"
[ -f "$SCRIPT_DIR/VERSION" ] || fail "VERSION is missing"
[ -f "$SUPPORTED_HASHES" ] || fail "supported-versions.sha256 is missing"
[ -f "$SUPPORTED_UPGRADES" ] || fail "supported-upgrades.sha256 is missing"
[ -f "$PAYLOAD_MANIFEST" ] || fail "payload.sha256 is missing; use a packaged Release asset"
[ -f "$SCRIPT_DIR/install-state.sh" ] || fail "install-state.sh is missing"
. "$SCRIPT_DIR/install-state.sh"

log "verifying patch payload..."
(cd "$SCRIPT_DIR" && shasum -a 256 -c "$(basename "$PAYLOAD_MANIFEST")") >/dev/null \
  || fail "patch payload checksum verification failed; download the Release asset again"
PAYLOAD_FINGERPRINT="$(shasum -a 256 "$PAYLOAD_MANIFEST" | awk '{print $1}')"

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
INSTALL_MODE=fresh
SOURCE_JAR="$JAR"
MTS_JAR="$RES/mts-launcher.jar"
SOURCE_MTS="$MTS_JAR"
MTS_PRESENT=0
MTS_BACKUP_ADDED=0

log "found game: $APP"
[ -f "$JAR" ] || fail "desktop-1.0.jar is missing; this is not the supported Steam app"
if [ -e "$MTS_JAR" ] || [ -L "$MTS_JAR" ]; then
  [ -f "$MTS_JAR" ] && [ ! -L "$MTS_JAR" ] \
    || fail "mts-launcher.jar is not a regular file"
  MTS_PRESENT=1
fi
[ -d "$RES/jre" ] || fail "the original Resources/jre is missing"
[ -f "$MACOS_DIR/SlayTheSpire" ] || fail "the original launcher is missing"
[ -f "$CONTENTS/Info.plist" ] || fail "Info.plist is missing"
[ ! -e "$LEGACY_BACKUP" ] || fail "the legacy ARM64 patch is installed; run its uninstall.sh before installing this Universal release"
[ ! -e "$WORK" ] || fail "stale installer work directory exists: $WORK"

if [ -e "$BACKUP" ]; then
  if sts_verify_installed_state "$BACKUP" "$PATCH_VERSION" "$PAYLOAD_FINGERPRINT" \
    "$PAYLOAD_MANIFEST" "$PAYLOAD" "$JAR" "$RES" "$MACOS_DIR" "$APP" \
    "$CONTENTS/Info.plist" "$HOST_ARCH" "$PAYLOAD/jar-delete.txt"; then
    log "patch $PATCH_VERSION from this exact build is already installed; nothing to do"
    exit 0
  fi
  PRIOR_VERSION="$(sts_manifest_value patch-version "$BACKUP/install-manifest.txt" 2>/dev/null || true)"
  PRIOR_FINGERPRINT="$(sts_manifest_value payload-manifest-sha256 "$BACKUP/install-manifest.txt" 2>/dev/null || true)"
  if ! awk -v version="$PRIOR_VERSION" -v fingerprint="$PRIOR_FINGERPRINT" \
    '$1 == fingerprint && $2 == version { found=1 } END { exit !found }' "$SUPPORTED_UPGRADES"; then
    fail "a different or unknown patch build is installed. Run its uninstall.sh first; the original backup was left untouched."
  fi
  if ! sts_verify_recorded_install_state "$BACKUP" "$JAR" "$RES" "$MACOS_DIR" \
    "$CONTENTS/Info.plist" "$HOST_ARCH"; then
    fail "the existing $PRIOR_VERSION patch cannot be upgraded safely ($STS_STATE_ERROR). Run its uninstall.sh first; the original backup was left untouched."
  fi
  INSTALL_MODE=upgrade
  SOURCE_JAR="$BACKUP/desktop-1.0.jar"
  if [ -f "$BACKUP/mts-launcher.jar" ]; then
    MTS_PRESENT=1
    SOURCE_MTS="$BACKUP/mts-launcher.jar"
  fi
  log "verified installed patch $PRIOR_VERSION; preparing an in-place upgrade to $PATCH_VERSION"
fi

LSOF_TARGETS=("$JAR")
[ "$MTS_PRESENT" = 0 ] || LSOF_TARGETS+=("$MTS_JAR")
if /usr/sbin/lsof -t -- "${LSOF_TARGETS[@]}" >/dev/null 2>&1; then
  fail "the game is running; quit it before installing"
fi

log "verifying the preserved unmodified Steam jar..."
ACTUAL_SHA="$(shasum -a 256 "$SOURCE_JAR" | awk '{print $1}')"
if ! awk -v hash="$ACTUAL_SHA" '$1 == hash { found=1 } END { exit !found }' "$SUPPORTED_HASHES"; then
  fail "unsupported or modified desktop-1.0.jar (sha256: $ACTUAL_SHA). Use Steam > Properties > Installed Files > Verify integrity, then retry."
fi

if [ "$MTS_PRESENT" = 1 ]; then
  MTS_ORIGINAL_SHA="$(shasum -a 256 "$SOURCE_MTS" | awk '{print $1}')"
  awk -v hash="$MTS_ORIGINAL_SHA" '$1 == hash { found=1 } END { exit !found }' \
    "$SCRIPT_DIR/supported-mts-launchers.sha256" \
    || fail "unsupported or modified mts-launcher.jar; originals left untouched"
fi

ROLLBACK_NEEDED=0
cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  set +e
  if [ "$ROLLBACK_NEEDED" = "1" ]; then
    if [ "$INSTALL_MODE" = upgrade ]; then
      log "upgrade did not complete; restoring the previously installed patch..."
      [ -e "$WORK/previous/jre" ] && { rm -rf "$RES/jre"; mv "$WORK/previous/jre" "$RES/jre"; }
      [ -e "$WORK/previous/desktop-1.0.jar" ] && { rm -f "$JAR"; mv "$WORK/previous/desktop-1.0.jar" "$JAR"; }
      [ "$MTS_PRESENT" = 0 ] || cp -p "$WORK/previous/mts-launcher.jar" "$MTS_JAR"
      [ "$MTS_BACKUP_ADDED" != 1 ] || rm -f "$BACKUP/mts-launcher.jar"
      [ -f "$WORK/previous/SlayTheSpire" ] && cp -p "$WORK/previous/SlayTheSpire" "$MACOS_DIR/SlayTheSpire"
      [ -f "$WORK/previous/Info.plist" ] && cp -p "$WORK/previous/Info.plist" "$CONTENTS/Info.plist"
      rm -rf "$CONTENTS/_CodeSignature"
      rm -f "$CONTENTS/CodeResources"
      [ -d "$WORK/previous/_CodeSignature" ] && cp -R "$WORK/previous/_CodeSignature" "$CONTENTS/_CodeSignature"
      [ -f "$WORK/previous/CodeResources" ] && cp -p "$WORK/previous/CodeResources" "$CONTENTS/CodeResources"
      for state_file in install-manifest.txt installed-jre.sha256 installed-overlay.sha256; do
        [ -f "$WORK/previous/$state_file" ] && cp -p "$WORK/previous/$state_file" "$BACKUP/$state_file"
      done
    else
      log "installation did not complete; restoring the original files..."
      [ -e "$BACKUP/jre" ] && { rm -rf "$RES/jre"; mv "$BACKUP/jre" "$RES/jre"; }
      [ -e "$BACKUP/desktop-1.0.jar" ] && { rm -f "$JAR"; mv "$BACKUP/desktop-1.0.jar" "$JAR"; }
      [ "$MTS_PRESENT" = 0 ] || cp -p "$BACKUP/mts-launcher.jar" "$MTS_JAR"
      [ -f "$BACKUP/SlayTheSpire" ] && cp -p "$BACKUP/SlayTheSpire" "$MACOS_DIR/SlayTheSpire"
      [ -f "$BACKUP/Info.plist" ] && cp -p "$BACKUP/Info.plist" "$CONTENTS/Info.plist"
      rm -rf "$CONTENTS/_CodeSignature"
      rm -f "$CONTENTS/CodeResources"
      [ -d "$BACKUP/_CodeSignature" ] && cp -R "$BACKUP/_CodeSignature" "$CONTENTS/_CodeSignature"
      [ -f "$BACKUP/CodeResources" ] && cp -p "$BACKUP/CodeResources" "$CONTENTS/CodeResources"
      rm -rf "$BACKUP"
    fi
  fi
  rm -rf "$WORK"
  exit "$rc"
}
trap cleanup EXIT INT TERM HUP

mkdir -p "$WORK/jar-overlay" "$WORK/original-natives" "$WORK/staged"
cp -R "$PAYLOAD/jar/." "$WORK/jar-overlay/"

# The verified Steam jar supplies its Steam API locally; the public patch does
# not redistribute that game binary.
rm -f "$WORK/jar-overlay/libsteam_api.dylib" "$WORK/jar-overlay/libsteam_api.dylib.sha1"

# One Release supports both Mac families, but the installed runtime must be
# host-native only. In particular, this game's Steam metadata prefers x86_64
# whenever that slice exists, which prevents launch on an arm64 Mac without
# Rosetta. Patch-built arm64 code comes from the payload; x86_64 code comes
# from the user's hash-verified original, except for the patched LWJGL slice.
if [ "$HOST_ARCH" = arm64 ]; then
  ARCH_NATIVE_FILES=(
    libgdx-controllers-desktop.dylib
    libgdx-controllers-desktop64.dylib
    libgdx-freetype.dylib
    libgdx-freetype64.dylib
    libgdx.dylib
    libgdx64.dylib
    liblwjgl.dylib
    libstsmacwindow.dylib
    libsteamworks4j.dylib
    openal.dylib
  )
  HOST_DELETE_ENTRIES=()
else
  # The unsuffixed libGDX natives in the original Steam jar are i386-only.
  # macOS 11 cannot run them, and keeping them would violate the x86_64-only
  # installed-runtime guarantee. The 64-bit JVM loads the *64 variants.
  ARCH_NATIVE_FILES=(
    libgdx-controllers-desktop64.dylib
    libgdx-freetype64.dylib
    libgdx64.dylib
    liblwjgl.dylib
    libstsmacwindow.dylib
    libsteamworks4j.dylib
    openal.dylib
  )
  HOST_DELETE_ENTRIES=(
    libgdx-controllers-desktop.dylib
    libgdx-controllers-desktop.dylib.sha1
    libgdx-freetype.dylib
    libgdx-freetype.dylib.sha1
    libgdx.dylib
    libgdx.dylib.sha1
  )
  rm -f "${HOST_DELETE_ENTRIES[@]/#/$WORK/jar-overlay/}"
fi
log "assembling host-native $HOST_ARCH LWJGL/libGDX/OpenAL/Steamworks files..."
for native in "${ARCH_NATIVE_FILES[@]}"; do
  patched="$WORK/jar-overlay/$native"
  [ -f "$patched" ] || fail "patch native is missing: $native"
  patched_archs="$(/usr/bin/lipo -archs "$patched" 2>/dev/null || true)"

  if [ "$HOST_ARCH" = 'arm64' ]; then
    case " $patched_archs " in *" arm64 "*) ;; *) fail "$native has no arm64 slice" ;; esac
    /usr/bin/lipo -extract arm64 "$patched" -output "$patched.native"
  else
    if [ "$native" = 'liblwjgl.dylib' ] || [ "$native" = 'libstsmacwindow.dylib' ]; then
      case " $patched_archs " in *" x86_64 "*) ;; *) fail "patched liblwjgl.dylib has no x86_64 slice" ;; esac
      /usr/bin/lipo -extract x86_64 "$patched" -output "$patched.native"
    else
      unzip -p "$SOURCE_JAR" "$native" > "$WORK/original-natives/$native" \
        || fail "the verified Steam jar has no $native"
      original_archs="$(/usr/bin/lipo -archs "$WORK/original-natives/$native" 2>/dev/null || true)"
      case " $original_archs " in *" x86_64 "*) ;; *) fail "original $native has no x86_64 slice" ;; esac
      /usr/bin/lipo -extract x86_64 "$WORK/original-natives/$native" -output "$patched.native"
    fi
  fi
  mv "$patched.native" "$patched"

  final_archs="$(/usr/bin/lipo -archs "$patched")"
  [ "$final_archs" = "$HOST_ARCH" ] \
    || fail "$native is not host-native-only $HOST_ARCH: $final_archs"
  codesign --force -s - "$patched"
  codesign --verify --strict "$patched" || fail "$native ad-hoc signature verification failed"
  printf '%s\r\n' "$(shasum -a 1 "$patched" | awk '{print $1}')" > "$patched.sha1"
done

# Thin the original Steam API locally as well. The arm64 bridge uses its newer
# ABI-matched companion name; Intel continues to use the original x86_64 code.
unzip -p "$SOURCE_JAR" libsteam_api.dylib > "$WORK/original-natives/libsteam_api.dylib" \
  || fail 'the verified Steam jar has no libsteam_api.dylib'
STEAM_API_ARCHS="$(/usr/bin/lipo -archs "$WORK/original-natives/libsteam_api.dylib" 2>/dev/null || true)"
case " $STEAM_API_ARCHS " in *" $HOST_ARCH "*) ;; *) fail "original Steam API has no $HOST_ARCH slice" ;; esac
/usr/bin/lipo -extract "$HOST_ARCH" "$WORK/original-natives/libsteam_api.dylib" \
  -output "$WORK/jar-overlay/libsteam_api.dylib"
codesign --force -s - "$WORK/jar-overlay/libsteam_api.dylib"
codesign --verify --strict "$WORK/jar-overlay/libsteam_api.dylib" \
  || fail 'host-native Steam API signature verification failed'
printf '%s\r\n' "$(shasum -a 1 "$WORK/jar-overlay/libsteam_api.dylib" | awk '{print $1}')" \
  > "$WORK/jar-overlay/libsteam_api.dylib.sha1"

if [ "$HOST_ARCH" = 'x86_64' ]; then
  rm -f "$WORK/jar-overlay/libsteam_api_arm64.dylib" \
    "$WORK/jar-overlay/libsteam_api_arm64.dylib.sha1"
fi

log "building and testing the candidate patched jar..."
cp -c "$SOURCE_JAR" "$WORK/staged/desktop-1.0.jar" 2>/dev/null \
  || cp -p "$SOURCE_JAR" "$WORK/staged/desktop-1.0.jar"
(
  cd "$WORK/jar-overlay"
  zip -q -r "$WORK/staged/desktop-1.0.jar" . -x '*.DS_Store' -x '._*'
)
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  zip -d "$WORK/staged/desktop-1.0.jar" "$entry" >/dev/null 2>&1 || true
done < "$PAYLOAD/jar-delete.txt"
if [ "$HOST_ARCH" = x86_64 ]; then
  for entry in "${HOST_DELETE_ENTRIES[@]}"; do
    zip -d "$WORK/staged/desktop-1.0.jar" "$entry" >/dev/null 2>&1 || true
  done
fi
unzip -tq "$WORK/staged/desktop-1.0.jar" >/dev/null || fail "candidate jar integrity test failed"

mkdir "$WORK/staged/native-audit"
(
  cd "$WORK/staged/native-audit"
  unzip -q "$WORK/staged/desktop-1.0.jar" '*.dylib' '*.jnilib' 2>/dev/null || true
)
while IFS= read -r native_path; do
  native_archs="$(/usr/bin/lipo -archs "$native_path" 2>/dev/null || true)"
  [ "$native_archs" = "$HOST_ARCH" ] \
    || fail "candidate contains a non-$HOST_ARCH macOS native: ${native_path#"$WORK/staged/native-audit/"} ($native_archs)"
done < <(find "$WORK/staged/native-audit" -type f \( -name '*.dylib' -o -name '*.jnilib' \) -print)
rm -rf "$WORK/staged/native-audit"

if [ "$MTS_PRESENT" = 1 ]; then
  # Replace exactly one entry. Never swap the legacy launcher's native libraries.
  cp -p "$SOURCE_MTS" "$WORK/staged/mts-launcher.jar"
  (cd "$PAYLOAD/mts" && zip -q "$WORK/staged/mts-launcher.jar" com/megacrit/mtslauncher/MtsFinder.class)
  unzip -tq "$WORK/staged/mts-launcher.jar" >/dev/null || fail "candidate mts-launcher.jar is corrupt"
  MTS_CLASS_SHA="$(unzip -p "$WORK/staged/mts-launcher.jar" com/megacrit/mtslauncher/MtsFinder.class | shasum -a 256 | awk '{print $1}')"
  [ "$MTS_CLASS_SHA" = "$(shasum -a 256 "$PAYLOAD/mts/com/megacrit/mtslauncher/MtsFinder.class" | awk '{print $1}')" ] \
    || fail "candidate local Workshop shim differs"
fi

mkdir "$WORK/staged/jre"
cp -R "$PAYLOAD/jre/$HOST_ARCH/." "$WORK/staged/jre/"
chmod +x "$WORK/staged/jre/bin/java"
JRE_ARCHS="$(/usr/bin/lipo -archs "$WORK/staged/jre/bin/java" 2>/dev/null || true)"
case " $JRE_ARCHS " in *" $HOST_ARCH "*) ;; *) fail "bundled Zulu JRE does not support $HOST_ARCH" ;; esac

# Steam's legacy launch metadata for this game prefers the x86_64 slice when
# one is present. On an Apple Silicon Mac without Rosetta, installing the fat
# launcher would therefore fail before our code can run. The Release remains
# Universal, while each installation receives only its native launcher slice,
# just like the architecture-specific JRE selected above.
/usr/bin/lipo -extract "$HOST_ARCH" "$PAYLOAD/launcher" \
  -output "$WORK/staged/SlayTheSpire"
chmod +x "$WORK/staged/SlayTheSpire"
LAUNCHER_ARCHS="$(/usr/bin/lipo -archs "$WORK/staged/SlayTheSpire" 2>/dev/null || true)"
[ "$LAUNCHER_ARCHS" = "$HOST_ARCH" ] \
  || fail "native launcher slice verification failed: $LAUNCHER_ARCHS"
codesign --verify --strict "$WORK/staged/SlayTheSpire" \
  || fail "native launcher slice signature verification failed"

if [ "$DRY_RUN" = "1" ]; then
  log "dry run passed: supported Steam jar and native-only $HOST_ARCH launcher/JRE/game natives verified"
  exit 0
fi

if [ "$INSTALL_MODE" = upgrade ]; then
  log "preserving the current patch state for automatic upgrade rollback"
  mkdir "$WORK/previous"
  cp -p "$MACOS_DIR/SlayTheSpire" "$WORK/previous/SlayTheSpire"
  cp -p "$CONTENTS/Info.plist" "$WORK/previous/Info.plist"
  cp -p "$BACKUP/install-manifest.txt" "$BACKUP/installed-jre.sha256" \
    "$BACKUP/installed-overlay.sha256" "$WORK/previous/"
  [ ! -d "$CONTENTS/_CodeSignature" ] || cp -R "$CONTENTS/_CodeSignature" "$WORK/previous/_CodeSignature"
  [ ! -f "$CONTENTS/CodeResources" ] || cp -p "$CONTENTS/CodeResources" "$WORK/previous/CodeResources"
  [ "$MTS_PRESENT" = 0 ] || cp -p "$MTS_JAR" "$WORK/previous/mts-launcher.jar"
  ROLLBACK_NEEDED=1
  if [ "$MTS_PRESENT" = 1 ] && [ ! -e "$BACKUP/mts-launcher.jar" ]; then
    MTS_BACKUP_ADDED=1
    cp -p "$MTS_JAR" "$BACKUP/mts-launcher.jar"
  fi
  mv "$RES/jre" "$WORK/previous/jre"
  mv "$JAR" "$WORK/previous/desktop-1.0.jar"
else
  log "backing up original runtime, jar, launcher, and Info.plist to $BACKUP"
  mkdir "$BACKUP"
  ROLLBACK_NEEDED=1
  [ "$MTS_PRESENT" = 0 ] || cp -p "$MTS_JAR" "$BACKUP/mts-launcher.jar"
  mv "$RES/jre" "$BACKUP/jre"
  mv "$JAR" "$BACKUP/desktop-1.0.jar"
  cp -p "$MACOS_DIR/SlayTheSpire" "$BACKUP/SlayTheSpire"
  cp -p "$CONTENTS/Info.plist" "$BACKUP/Info.plist"
  [ ! -d "$CONTENTS/_CodeSignature" ] || cp -R "$CONTENTS/_CodeSignature" "$BACKUP/_CodeSignature"
  [ ! -f "$CONTENTS/CodeResources" ] || cp -p "$CONTENTS/CodeResources" "$BACKUP/CodeResources"
fi
mv "$WORK/staged/jre" "$RES/jre"
mv "$WORK/staged/desktop-1.0.jar" "$JAR"
[ "$MTS_PRESENT" = 0 ] || mv "$WORK/staged/mts-launcher.jar" "$MTS_JAR"
cp -p "$WORK/staged/SlayTheSpire" "$MACOS_DIR/SlayTheSpire"
chmod +x "$MACOS_DIR/SlayTheSpire"
plutil -replace NSHighResolutionCapable -bool true "$CONTENTS/Info.plist"
plutil -replace LSMinimumSystemVersion -string '11.0' "$CONTENTS/Info.plist"
# Built against an older SDK, so macOS otherwise letterboxes every native
# full-screen Space below the camera housing (visible as bars on all sides).
# Opt out so the game fills the whole area below the notch strip.
plutil -replace NSPrefersDisplaySafeAreaCompatibilityMode -bool false "$CONTENTS/Info.plist"

if [ "${STS_TEST_FAIL_AFTER_REPLACEMENT:-0}" = 1 ]; then
  fail 'injected post-replacement failure for rollback verification'
fi

XATTR_TARGETS=("$RES/jre" "$JAR" "$MACOS_DIR/SlayTheSpire")
[ "$MTS_PRESENT" = 0 ] || XATTR_TARGETS+=("$MTS_JAR")
xattr -dr com.apple.quarantine "${XATTR_TARGETS[@]}" 2>/dev/null || true
log "applying an ad-hoc signature..."
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ ! -x "$LSREGISTER" ] || "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
"$RES/jre/bin/java" -version >/dev/null 2>&1 || fail "installed $HOST_ARCH JRE failed its launch test"
sts_record_install_state "$BACKUP" "$PATCH_VERSION" "$PAYLOAD_FINGERPRINT" \
  "$ACTUAL_SHA" "$JAR" "$RES/jre" "$MACOS_DIR/SlayTheSpire" \
  "$CONTENTS/Info.plist" "$WORK/jar-overlay" "$WORK/new-state" \
  || fail "could not record installed build state"
for state_file in install-manifest.txt installed-jre.sha256 installed-overlay.sha256; do
  mv "$WORK/new-state/$state_file" "$BACKUP/$state_file"
done

# BaseMod's screen post-processor renders every frame into a logical-size FBO
# even when no post-processor is registered. On a 2x backing that means a
# 1470x895 buffer is upscaled to 2940x1790 and text turns soft. Patch the
# Workshop jar in place and keep the original beside the other backups.
STEAMAPPS="$(dirname "$(dirname "$GAME_DIR")")"
BASEMOD_JAR="$STEAMAPPS/workshop/content/646570/1605833019/BaseMod.jar"
BASEMOD_MTS="$STEAMAPPS/workshop/content/646570/1605060445/ModTheSpire.jar"
if [ -f "$BASEMOD_JAR" ] && [ -f "$BASEMOD_MTS" ]; then
  BASEMOD_SHA="$(shasum -a 256 "$BASEMOD_JAR" | awk '{print $1}')"
  BASEMOD_CLASS="basemod/patches/com/megacrit/cardcrawl/core/CardCrawlGame/ApplyScreenPostProcessor.class"
  BASEMOD_CLASS_SHA="$(unzip -p "$BASEMOD_JAR" "$BASEMOD_CLASS" | shasum -a 256 | awk '{print $1}')"
  if awk -v hash="$BASEMOD_CLASS_SHA" '$1 == hash { found=1 } END { exit !found }' \
    "$SCRIPT_DIR/patched-basemod.sha256"; then
    log "BaseMod HiDPI screen fix is already applied"
  elif awk -v hash="$BASEMOD_SHA" '$1 == hash { found=1 } END { exit !found }' \
    "$SCRIPT_DIR/supported-basemod.sha256"; then
    [ -f "$BACKUP/BaseMod.jar" ] || cp -p "$BASEMOD_JAR" "$BACKUP/BaseMod.jar"
    if "$RES/jre/bin/java" -cp "$PAYLOAD/basemod:$BASEMOD_MTS:$JAR" \
      BaseModPatch "$BASEMOD_JAR" >/dev/null 2>&1; then
      log "applied the BaseMod HiDPI screen fix"
    else
      cp -p "$BACKUP/BaseMod.jar" "$BASEMOD_JAR"
      log "WARNING: BaseMod could not be patched; left unchanged"
    fi
  else
    log "WARNING: unsupported BaseMod build; skipped the HiDPI screen fix"
  fi
fi

ROLLBACK_NEEDED=0
log "patch $PATCH_VERSION installed successfully for $HOST_ARCH"
log "the original files are preserved at: $BACKUP"
log "launch the game from Steam; run uninstall.sh to restore the exact originals"
