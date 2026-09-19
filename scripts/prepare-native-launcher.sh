#!/bin/bash
# Build a real Universal Mach-O entry point that Steam can spawn natively.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/launcher/SlayTheSpireLauncher.c"
OUTPUT="${1:-$ROOT/payload/launcher}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sts-launcher.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

[ -f "$SOURCE" ] || { echo "missing launcher source: $SOURCE" >&2; exit 1; }
CLANG="$(xcrun -f clang)"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

for arch in arm64 x86_64; do
  "$CLANG" -Os -Wall -Wextra -Werror -arch "$arch" -isysroot "$SDKROOT" \
    -mmacosx-version-min=11.0 "$SOURCE" -o "$WORK/launcher.$arch"
done

mkdir -p "$(dirname "$OUTPUT")"
/usr/bin/lipo -create "$WORK/launcher.arm64" "$WORK/launcher.x86_64" -output "$OUTPUT"
chmod +x "$OUTPUT"
codesign --force -s - "$OUTPUT"
codesign --verify --strict "$OUTPUT"

ARCHS="$(/usr/bin/lipo -archs "$OUTPUT")"
case " $ARCHS " in *' arm64 '*) ;; *) echo 'launcher lacks arm64' >&2; exit 1 ;; esac
case " $ARCHS " in *' x86_64 '*) ;; *) echo 'launcher lacks x86_64' >&2; exit 1 ;; esac

echo "built Universal Steam-compatible launcher: $OUTPUT ($ARCHS)"
