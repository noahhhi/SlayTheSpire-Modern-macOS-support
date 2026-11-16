#!/bin/bash
# Static safety and architecture gates for an unpacked release directory.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

required=(
  supported-mts-launchers.sha256
  payload/mts/com/megacrit/mtslauncher/MtsFinder.class
  payload/mts-source/com/megacrit/mtslauncher/MtsFinder.java
  VERSION README.md README.zh-CN.md RELEASE_NOTES.md install.sh install-state.sh uninstall.sh
  supported-versions.sha256 payload.sha256 payload/launcher payload/jar-delete.txt
  overlay-drop.txt
  display-overlay.sha256
  supported-basemod.sha256 patched-basemod.sha256
  payload/basemod/BaseModPatch.class
  payload/jar/com/megacrit/cardcrawl/desktop/StsWindow.class
  payload/jar/com/megacrit/cardcrawl/desktop/StsViewport.class
  payload/jar/libstsmacwindow.dylib
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

[ "$(find payload/mts -type f | wc -l | tr -d ' ')" -eq 1 ] \
  || { echo 'MTS overlay must contain exactly one replacement class' >&2; exit 1; }
MTS_CLASS=payload/mts/com/megacrit/mtslauncher/MtsFinder.class
[ "$(od -An -tx1 -N8 "$MTS_CLASS" | tr -d ' \n')" = cafebabe00000034 ] \
  || { echo 'MTS shim must be Java 8 bytecode' >&2; exit 1; }
if LC_ALL=C grep -a -Eq 'SteamAPI|SteamUGC|loadLibrary' "$MTS_CLASS"; then
  echo 'MTS shim must not invoke native Steam discovery' >&2; exit 1
fi

OVERLAY_CLASS_COUNT="$(find payload/jar -type f -name '*.class' | wc -l | tr -d ' ')"
# 42 upstream classes minus the helpers listed in overlay-drop.txt that are
# instruction-identical to the Steam originals (shipping them would only drop
# LocalVariableTable data that ModTheSpire patches rely on), plus the two new
# StsWindow/StsViewport classes.
EXPECTED_OVERLAY=$((42 - $(grep -vcE '^\s*(#|$)' overlay-drop.txt) + 2))
[ "$OVERLAY_CLASS_COUNT" -eq "$EXPECTED_OVERLAY" ] \
  || { echo "unexpected Java overlay size: $OVERLAY_CLASS_COUNT classes (expected $EXPECTED_OVERLAY)" >&2; exit 1; }

GEOMETRY_CLASS='payload/jar/com/badlogic/gdx/backends/lwjgl/LwjglDisplayGeometry.class'
GRAPHICS_CLASS='payload/jar/com/badlogic/gdx/backends/lwjgl/LwjglGraphics.class'
LC_ALL=C grep -a -q 'fitViewport' "$GEOMETRY_CLASS" \
  || { echo 'safe fitted-viewport helper is missing from the GDX overlay' >&2; exit 1; }
if LC_ALL=C grep -a -q 'capLogicalSize' "$GEOMETRY_CLASS" \
  || LC_ALL=C grep -a -q 'getPhysicalDisplayWidth\|getPhysicalDisplayHeight' "$GRAPHICS_CLASS"; then
  echo 'stale physical-panel Retina cap found in the GDX overlay; full 2x backing is required' >&2
  exit 1
fi

(shasum -a 256 -c payload.sha256) >/dev/null
LAUNCHER_ARCHS="$(/usr/bin/lipo -archs payload/launcher 2>/dev/null || true)"
case " $LAUNCHER_ARCHS " in *' arm64 '*) ;; *) echo 'native launcher lacks arm64' >&2; exit 1 ;; esac
case " $LAUNCHER_ARCHS " in *' x86_64 '*) ;; *) echo 'native launcher lacks x86_64' >&2; exit 1 ;; esac
file payload/launcher | grep -q 'Mach-O universal binary' \
  || { echo 'Steam entry point must be a Universal Mach-O binary, not a shell script' >&2; exit 1; }
LAUNCHER_MINOS="$(otool -l payload/launcher | awk '$1 == "minos" { print $2 }' | sort -u)"
[ "$LAUNCHER_MINOS" = '11.0' ] \
  || { echo "native launcher deployment target must be macOS 11.0 (found: $LAUNCHER_MINOS)" >&2; exit 1; }
for arch in arm64 x86_64; do
  archs="$(/usr/bin/lipo -archs "payload/jre/$arch/bin/java")"
  case " $archs " in *" $arch "*) ;; *) echo "JRE architecture mismatch: $archs" >&2; exit 1 ;; esac
done

arm_natives=(
  libgdx-controllers-desktop.dylib libgdx-controllers-desktop64.dylib
  libgdx-freetype.dylib libgdx-freetype64.dylib libgdx.dylib libgdx64.dylib
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

for native_path in payload/jar/*.dylib; do
  native_minos="$(otool -l "$native_path" | awk '$1 == "minos" { print $2 }' | sort -u)"
  [ "$native_minos" = '11.0' ] \
    || { echo "$(basename "$native_path") deployment target must be macOS 11.0 (found: $native_minos)" >&2; exit 1; }
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
