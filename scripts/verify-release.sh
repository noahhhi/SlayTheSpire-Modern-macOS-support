#!/bin/bash
# Static safety and architecture gates for an unpacked release directory.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

required=(
  VERSION README.md README.zh-CN.md RELEASE_NOTES.md install.sh uninstall.sh
  supported-versions.sha256 payload.sha256 payload/launcher payload/jar-delete.txt
  payload/jre/arm64/bin/java payload/jre/x86_64/bin/java
)
for path in "${required[@]}"; do
  [ -e "$path" ] || { echo "missing release file: $path" >&2; exit 1; }
done

for script in install.sh uninstall.sh 'Install SlayTheSpire Modern macOS.command'; do
  [ -x "$script" ] || { echo "not executable: $script" >&2; exit 1; }
  /bin/bash -n "$script"
done

[ -z "$(find . \( -name '.DS_Store' -o -name '._*' -o -name '__MACOSX' \) -print -quit)" ] \
  || { echo 'AppleDouble or Finder metadata found' >&2; exit 1; }
[ -z "$(find . \( -name 'desktop-1.0.jar' -o -name '*.app' -o -name '*.save' -o -name 'preferences' -o -name 'saves' \) -print -quit)" ] \
  || { echo 'game content found in release tree' >&2; exit 1; }

(shasum -a 256 -c payload.sha256) >/dev/null
for arch in arm64 x86_64; do
  archs="$(/usr/bin/lipo -archs "payload/jre/$arch/bin/java")"
  case " $archs " in *" $arch "*) ;; *) echo "JRE architecture mismatch: $archs" >&2; exit 1 ;; esac
done

arm_natives=(
  libgdx-controllers-desktop64.dylib libgdx-freetype64.dylib libgdx64.dylib
  liblwjgl.dylib libsteam_api.dylib libsteamworks4j.dylib openal.dylib
)
for native in "${arm_natives[@]}"; do
  [ -f "payload/jar/$native" ] || { echo "missing patch native: $native" >&2; exit 1; }
  archs="$(/usr/bin/lipo -archs "payload/jar/$native")"
  case " $archs " in *" arm64 "*) ;; *) echo "$native has no arm64 slice" >&2; exit 1 ;; esac
done

LWJGL_ARCHS="$(/usr/bin/lipo -archs payload/jar/liblwjgl.dylib)"
case " $LWJGL_ARCHS " in *' x86_64 '*) ;; *) echo 'patched liblwjgl must include x86_64 JNI implementations' >&2; exit 1 ;; esac
for arch in arm64 x86_64; do
  SYMBOLS="$(/usr/bin/nm -arch "$arch" -gU payload/jar/liblwjgl.dylib)"
  for symbol in \
    _Java_org_lwjgl_openal_AL10_initNativeStubs \
    _Java_org_lwjgl_opengl_GL11_nglGetString \
    _Java_org_lwjgl_opengl_MacOSXDisplay_nIsNativeFullscreen; do
    grep -q "$symbol" <<< "$SYMBOLS" \
      || { echo "patched liblwjgl $arch lacks required JNI symbol: $symbol" >&2; exit 1; }
  done
done

echo "release tree verified: no game jar, payload checksums valid, both Zulu JRE architectures present"
