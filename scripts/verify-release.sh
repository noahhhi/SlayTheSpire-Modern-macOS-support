#!/bin/bash
# Static safety and architecture gates for an unpacked release directory.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

required=(
  VERSION README.md README.zh-CN.md RELEASE_NOTES.md install.sh install-state.sh uninstall.sh
  supported-versions.sha256 payload.sha256 payload/launcher payload/jar-delete.txt
  payload/jar/com/badlogic/gdx/backends/lwjgl/LwjglDisplayGeometry.class
  payload/jre/arm64/bin/java payload/jre/x86_64/bin/java
)
for path in "${required[@]}"; do
  [ -e "$path" ] || { echo "missing release file: $path" >&2; exit 1; }
done

for script in install.sh uninstall.sh 'Install SlayTheSpire Modern macOS.command'; do
  [ -x "$script" ] || { echo "not executable: $script" >&2; exit 1; }
  /bin/bash -n "$script"
done
/bin/bash -n install-state.sh

[ -z "$(find . \( -name '.DS_Store' -o -name '._*' -o -name '__MACOSX' \) -print -quit)" ] \
  || { echo 'AppleDouble or Finder metadata found' >&2; exit 1; }
[ -z "$(find . \( -name 'desktop-1.0.jar' -o -name '*.app' -o -name '*.save' -o -name 'preferences' -o -name 'saves' \) -print -quit)" ] \
  || { echo 'game content found in release tree' >&2; exit 1; }

OVERLAY_CLASS_COUNT="$(find payload/jar -type f -name '*.class' | wc -l | tr -d ' ')"
[ "$OVERLAY_CLASS_COUNT" -eq 42 ] \
  || { echo "unexpected Java overlay size: $OVERLAY_CLASS_COUNT classes (expected 42)" >&2; exit 1; }

(shasum -a 256 -c payload.sha256) >/dev/null
for arch in arm64 x86_64; do
  archs="$(/usr/bin/lipo -archs "payload/jre/$arch/bin/java")"
  case " $archs " in *" $arch "*) ;; *) echo "JRE architecture mismatch: $archs" >&2; exit 1 ;; esac
done

arm_natives=(
  libgdx-controllers-desktop64.dylib libgdx-freetype64.dylib libgdx64.dylib
  liblwjgl.dylib libsteam_api_arm64.dylib libsteamworks4j.dylib openal.dylib
)
for native in "${arm_natives[@]}"; do
  [ -f "payload/jar/$native" ] || { echo "missing patch native: $native" >&2; exit 1; }
  archs="$(/usr/bin/lipo -archs "payload/jar/$native")"
  case " $archs " in *" arm64 "*) ;; *) echo "$native has no arm64 slice" >&2; exit 1 ;; esac
  if [ "$native" != liblwjgl.dylib ]; then
    case " $archs " in *" x86_64 "*) echo "$native must not ship an x86_64 slice; installer uses the verified original" >&2; exit 1 ;; esac
  fi
done

LWJGL_ARCHS="$(/usr/bin/lipo -archs payload/jar/liblwjgl.dylib)"
case " $LWJGL_ARCHS " in *' x86_64 '*) ;; *) echo 'patched liblwjgl must include x86_64 JNI implementations' >&2; exit 1 ;; esac
[ ! -e payload/jar/libsteam_api.dylib ] || { echo 'Steam API must come from the verified original jar, not the patch payload' >&2; exit 1; }
/usr/bin/nm -arch arm64 -gU payload/jar/libsteam_api_arm64.dylib | grep -q _SteamInternal_SteamAPI_Init \
  || { echo 'arm64 Steam API lacks the ABI required by the migrated Steamworks bridge' >&2; exit 1; }
otool -L payload/jar/libsteamworks4j.dylib | grep -q '@loader_path/libsteam_api_arm64.dylib' \
  || { echo 'arm64 Steamworks bridge is not bound to its architecture-specific API' >&2; exit 1; }
for arch in arm64 x86_64; do
  SYMBOLS="$(/usr/bin/nm -arch "$arch" -gU payload/jar/liblwjgl.dylib)"
  for symbol in \
    _Java_org_lwjgl_openal_AL10_initNativeStubs \
    _Java_org_lwjgl_opengl_GL11_nglGetString \
    _Java_org_lwjgl_opengl_MacOSXDisplay_nGetPhysicalDisplayHeight \
    _Java_org_lwjgl_opengl_MacOSXDisplay_nGetPhysicalDisplayWidth \
    _Java_org_lwjgl_opengl_MacOSXDisplay_nIsNativeFullscreen \
    _Java_org_lwjgl_opengl_MacOSXDisplay_nUpdateSurfaceBackingScale; do
    grep -q "$symbol" <<< "$SYMBOLS" \
      || { echo "patched liblwjgl $arch lacks required JNI symbol: $symbol" >&2; exit 1; }
  done
done

echo "release tree verified: no game jar, payload checksums valid, both Zulu JRE architectures present"
