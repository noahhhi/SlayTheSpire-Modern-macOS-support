#!/bin/bash
# Merge separately built HiDPI/fullscreen outputs into the ARM migration
# overlay. This never copies a complete game jar.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
PATCH_CLASSES="${PATCH_CLASSES:-$WORKSPACE/build/patch-classes}"
LWJGL_CLASSES="${LWJGL_CLASSES:-$WORKSPACE/src/lwjgl/bin}"
LWJGL_NATIVE="${LWJGL_NATIVE:-$WORKSPACE/src/lwjgl/bin/lwjgl/liblwjgl.dylib}"
ARM_STEAM_API="${ARM_STEAM_API:-$WORKSPACE/build/stage/libsteam_api.dylib}"
OVERLAY="$ROOT/payload/jar"

[ -d "$PATCH_CLASSES" ] || { echo "missing patch classes: $PATCH_CLASSES" >&2; exit 1; }
[ -f "$LWJGL_CLASSES/org/lwjgl/opengl/Display.class" ] || { echo 'missing Display.class' >&2; exit 1; }
[ -f "$LWJGL_CLASSES/org/lwjgl/opengl/MacOSXDisplay.class" ] || { echo 'missing MacOSXDisplay.class' >&2; exit 1; }
[ -f "$LWJGL_CLASSES/org/lwjgl/MemoryUtilSun.class" ] || { echo 'missing MemoryUtilSun.class' >&2; exit 1; }
[ -f "$LWJGL_CLASSES/org/lwjgl/MemoryUtilSun\$AccessorUnsafe.class" ] || { echo 'missing MemoryUtilSun$AccessorUnsafe.class' >&2; exit 1; }
[ -f "$LWJGL_NATIVE" ] || { echo "missing LWJGL native: $LWJGL_NATIVE" >&2; exit 1; }
[ -f "$ARM_STEAM_API" ] || { echo "missing arm64 Steam API: $ARM_STEAM_API" >&2; exit 1; }

CLASS_COUNT="$(find "$PATCH_CLASSES" -type f -name '*.class' | wc -l | tr -d ' ')"
[ "$CLASS_COUNT" -eq 37 ] || {
  echo "expected exactly 37 patch classes, found $CLASS_COUNT; refusing an unreviewed overlay" >&2
  exit 1
}
NATIVE_ARCHS="$(/usr/bin/lipo -archs "$LWJGL_NATIVE")"
case " $NATIVE_ARCHS " in *' arm64 '*) ;; *) echo "LWJGL native lacks arm64: $NATIVE_ARCHS" >&2; exit 1 ;; esac
case " $NATIVE_ARCHS " in *' x86_64 '*) ;; *) echo "LWJGL native lacks patched x86_64 JNI: $NATIVE_ARCHS" >&2; exit 1 ;; esac

# This script is rerunnable. Remove only generated Java entries first so a
# prior full LWJGL build cannot leak hundreds of unchanged classes into the
# minimal patch overlay.
find "$OVERLAY" -type f -name '*.class' -delete
mkdir -p "$OVERLAY/org/lwjgl/opengl"
cp -R "$PATCH_CLASSES/." "$OVERLAY/"
cp -p "$LWJGL_CLASSES/org/lwjgl/opengl/Display.class" "$OVERLAY/org/lwjgl/opengl/Display.class"
cp -p "$LWJGL_CLASSES/org/lwjgl/opengl/MacOSXDisplay.class" "$OVERLAY/org/lwjgl/opengl/MacOSXDisplay.class"
# The original jar's MemoryUtilSun references AccessorReflectFast, which is
# unavailable on modern JDKs and is removed by jar-delete.txt. Overlay the
# matching Unsafe-based implementation compiled from this LWJGL source tree.
mkdir -p "$OVERLAY/org/lwjgl"
cp -p "$LWJGL_CLASSES/org/lwjgl/MemoryUtilSun.class" "$OVERLAY/org/lwjgl/MemoryUtilSun.class"
cp -p "$LWJGL_CLASSES/org/lwjgl/MemoryUtilSun\$AccessorUnsafe.class" "$OVERLAY/org/lwjgl/MemoryUtilSun\$AccessorUnsafe.class"
cp -p "$LWJGL_NATIVE" "$OVERLAY/liblwjgl.dylib"
codesign --force -s - "$OVERLAY/liblwjgl.dylib"
codesign --verify --strict "$OVERLAY/liblwjgl.dylib"
printf '%s\r\n' "$(shasum -a 1 "$OVERLAY/liblwjgl.dylib" | awk '{print $1}')" > "$OVERLAY/liblwjgl.dylib.sha1"
rm -f "$OVERLAY/libsteam_api.dylib" "$OVERLAY/libsteam_api.dylib.sha1"

# The migrated arm64 steamworks4j bridge uses a newer Steam API ABI. Ship that
# redistributable under an arm-only name so the installer can pair it with the
# arm64 bridge without redistributing the game's original Steam API.
/usr/bin/lipo -extract arm64 "$ARM_STEAM_API" -output "$OVERLAY/libsteam_api_arm64.dylib"
install_name_tool -id @loader_path/libsteam_api_arm64.dylib "$OVERLAY/libsteam_api_arm64.dylib"
codesign --force -s - "$OVERLAY/libsteam_api_arm64.dylib"
printf '%s\r\n' "$(shasum -a 1 "$OVERLAY/libsteam_api_arm64.dylib" | awk '{print $1}')" > "$OVERLAY/libsteam_api_arm64.dylib.sha1"

# Only LWJGL needs patched code on both architectures. Keep every other patch
# native arm64-only so the installer must source the ABI-matched x86_64 slice
# from the hash-verified original jar.
ARM_ONLY_NATIVES=(
  libgdx-controllers-desktop64.dylib libgdx-freetype64.dylib libgdx64.dylib
  libsteamworks4j.dylib openal.dylib
)
for native in "${ARM_ONLY_NATIVES[@]}"; do
  [ -f "$OVERLAY/$native" ] || { echo "missing patch native: $native" >&2; exit 1; }
  native_archs="$(/usr/bin/lipo -archs "$OVERLAY/$native")"
  case " $native_archs " in
    *' x86_64 '*)
      /usr/bin/lipo -extract arm64 "$OVERLAY/$native" -output "$OVERLAY/$native.arm64"
      mv "$OVERLAY/$native.arm64" "$OVERLAY/$native"
      ;;
    *' arm64 '*) ;;
    *) echo "$native has no arm64 slice: $native_archs" >&2; exit 1 ;;
  esac
  if [ "$native" = libsteamworks4j.dylib ]; then
    install_name_tool -change @loader_path/libsteam_api.dylib \
      @loader_path/libsteam_api_arm64.dylib "$OVERLAY/$native"
  fi
  codesign --force -s - "$OVERLAY/$native"
  printf '%s\r\n' "$(shasum -a 1 "$OVERLAY/$native" | awk '{print $1}')" > "$OVERLAY/$native.sha1"
done

OVERLAY_CLASS_COUNT="$(find "$OVERLAY" -type f -name '*.class' | wc -l | tr -d ' ')"
[ "$OVERLAY_CLASS_COUNT" -eq 41 ] || {
  echo "expected exactly 41 overlay classes after preparation, found $OVERLAY_CLASS_COUNT" >&2
  exit 1
}

# The upstream CardCrawlGame was recompiled without debug info, which breaks
# ModTheSpire patches that bind named locals (BaseMod's CustomRewardLoad reads
# "i"). Rebuild it from the unmodified Steam jar and drop helper classes that
# are identical to the originals.
if [ -n "${ORIGINAL_JAR:-}" ]; then
  "$ROOT/scripts/prepare-cardcrawlgame-overlay.sh" "$ORIGINAL_JAR"
else
  echo 'ORIGINAL_JAR is not set; the CardCrawlGame overlay still needs' >&2
  echo "  ORIGINAL_JAR=<unmodified desktop-1.0.jar> $0" >&2
  python3 "$ROOT/tests/test-overlay-debug-info.py"
fi

echo "Merged overlay classes and Universal liblwjgl into $OVERLAY"
echo "No complete desktop-1.0.jar was copied. Run build.sh to regenerate payload.sha256."
