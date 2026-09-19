#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sts-launcher-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

APP="$WORK/SlayTheSpire.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
OUTPUT="$WORK/java-arguments.txt"
mkdir -p "$MACOS" "$RESOURCES/jre/bin"

"$ROOT/scripts/prepare-native-launcher.sh" "$MACOS/SlayTheSpire" >/dev/null
printf '%s\n' \
  '#!/bin/bash' \
  'printf "%s\n" "$PWD" > "$STS_LAUNCHER_TEST_OUTPUT"' \
  'printf "%s\n" "$@" >> "$STS_LAUNCHER_TEST_OUTPUT"' \
  > "$RESOURCES/jre/bin/java"
chmod +x "$RESOURCES/jre/bin/java"
RESOURCES_REAL="$(cd "$RESOURCES" && pwd -P)"

STS_LAUNCHER_TEST_OUTPUT="$OUTPUT" SteamAppId=646570 \
  "$MACOS/SlayTheSpire" --forwarded-option

EXPECTED="$WORK/expected.txt"
printf '%s\n' \
  "$RESOURCES_REAL" \
  '-Xdock:icon=icons.icns' \
  '-Xdock:name=Slay the Spire' \
  '-Xmx1G' \
  '-Dsun.java2d.dpiaware=true' \
  '-Dorg.lwjgl.opengl.Display.enableHighDPI=true' \
  '-jar' \
  'desktop-1.0.jar' \
  '--forwarded-option' \
  > "$EXPECTED"
diff -u "$EXPECTED" "$OUTPUT"

ARCHS="$(/usr/bin/lipo -archs "$MACOS/SlayTheSpire")"
case " $ARCHS " in *' arm64 '*) ;; *) exit 1 ;; esac
case " $ARCHS " in *' x86_64 '*) ;; *) exit 1 ;; esac

echo 'native launcher test passed: Universal Mach-O, Resources lookup, and argument forwarding'
