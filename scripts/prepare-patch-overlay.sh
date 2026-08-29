#!/bin/bash
# Merge separately built HiDPI/fullscreen outputs into the ARM migration
# overlay. This never copies a complete game jar.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
PATCH_CLASSES="${PATCH_CLASSES:-$WORKSPACE/build/patch-classes}"
LWJGL_CLASSES="${LWJGL_CLASSES:-$WORKSPACE/src/lwjgl/bin}"
LWJGL_NATIVE="${LWJGL_NATIVE:-$WORKSPACE/src/lwjgl/bin/lwjgl/liblwjgl.dylib}"
OVERLAY="$ROOT/payload/jar"

[ -d "$PATCH_CLASSES" ] || { echo "missing patch classes: $PATCH_CLASSES" >&2; exit 1; }
[ -f "$LWJGL_CLASSES/org/lwjgl/opengl/Display.class" ] || { echo 'missing Display.class' >&2; exit 1; }
[ -f "$LWJGL_CLASSES/org/lwjgl/opengl/MacOSXDisplay.class" ] || { echo 'missing MacOSXDisplay.class' >&2; exit 1; }
[ -f "$LWJGL_NATIVE" ] || { echo "missing LWJGL native: $LWJGL_NATIVE" >&2; exit 1; }

CLASS_COUNT="$(find "$PATCH_CLASSES" -type f -name '*.class' | wc -l | tr -d ' ')"
[ "$CLASS_COUNT" -eq 37 ] || {
  echo "expected exactly 37 patch classes, found $CLASS_COUNT; refusing an unreviewed overlay" >&2
  exit 1
}
NATIVE_ARCHS="$(/usr/bin/lipo -archs "$LWJGL_NATIVE")"
case " $NATIVE_ARCHS " in *' arm64 '*) ;; *) echo "LWJGL native lacks arm64: $NATIVE_ARCHS" >&2; exit 1 ;; esac
case " $NATIVE_ARCHS " in *' x86_64 '*) ;; *) echo "LWJGL native lacks patched x86_64 JNI: $NATIVE_ARCHS" >&2; exit 1 ;; esac

mkdir -p "$OVERLAY/org/lwjgl/opengl"
cp -R "$PATCH_CLASSES/." "$OVERLAY/"
cp -p "$LWJGL_CLASSES/org/lwjgl/opengl/Display.class" "$OVERLAY/org/lwjgl/opengl/Display.class"
cp -p "$LWJGL_CLASSES/org/lwjgl/opengl/MacOSXDisplay.class" "$OVERLAY/org/lwjgl/opengl/MacOSXDisplay.class"
cp -p "$LWJGL_NATIVE" "$OVERLAY/liblwjgl.dylib"
printf '%s\r\n' "$(shasum -a 1 "$OVERLAY/liblwjgl.dylib" | awk '{print $1}')" > "$OVERLAY/liblwjgl.dylib.sha1"

echo "Merged 39 class files and Universal liblwjgl into $OVERLAY"
echo "No complete desktop-1.0.jar was copied. Run build.sh to regenerate payload.sha256."
