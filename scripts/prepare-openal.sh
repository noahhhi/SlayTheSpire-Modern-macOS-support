#!/bin/bash
# Build the redistributable arm64 OpenAL Soft runtime for macOS 11+.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION='1.25.2'
SOURCE_URL="https://openal-soft.org/openal-releases/openal-soft-${VERSION}.tar.bz2"
SOURCE_SHA256='1dbaac44e7579d5bc8847ca8db4b2e8b9fd3961041f35ee20def4958301e1089'
OUTPUT="${1:-$ROOT/payload/jar/openal.dylib}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sts-openal.XXXXXX")"
JOBS="${JOBS:-$(sysctl -n hw.perflevel0.physicalcpu)}"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

for tool in cmake ninja; do
  command -v "$tool" >/dev/null 2>&1 \
    || { echo "missing OpenAL build tool: $tool" >&2; exit 1; }
done

ARCHIVE="$WORK/openal-soft.tar.bz2"
/usr/bin/curl --fail --location --silent --show-error "$SOURCE_URL" -o "$ARCHIVE"
ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
[ "$ACTUAL_SHA256" = "$SOURCE_SHA256" ] \
  || { echo "OpenAL Soft source checksum mismatch: $ACTUAL_SHA256" >&2; exit 1; }

tar -xjf "$ARCHIVE" -C "$WORK"
SOURCE="$WORK/openal-soft-${VERSION}"
BUILD="$WORK/build"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

cmake -S "$SOURCE" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DCMAKE_OSX_SYSROOT="$SDKROOT" \
  -DHAVE_WFUNCTION_EFFECTS=OFF \
  -DLIBTYPE=SHARED \
  -DALSOFT_UTILS=OFF \
  -DALSOFT_EXAMPLES=OFF \
  -DALSOFT_TESTS=OFF \
  -DALSOFT_INSTALL=OFF
cmake --build "$BUILD" --parallel "$JOBS"

BUILT="$(find "$BUILD" -type f -name 'libopenal*.dylib' -print | head -n 1)"
[ -n "$BUILT" ] || { echo 'OpenAL Soft build produced no dylib' >&2; exit 1; }
mkdir -p "$(dirname "$OUTPUT")"
cp -p "$BUILT" "$OUTPUT"
install_name_tool -id openal.dylib "$OUTPUT"
codesign --force -s - "$OUTPUT"
codesign --verify --strict "$OUTPUT"

ARCHS="$(/usr/bin/lipo -archs "$OUTPUT")"
[ "$ARCHS" = 'arm64' ] || { echo "OpenAL payload must be arm64-only: $ARCHS" >&2; exit 1; }
MINOS="$(otool -l "$OUTPUT" | awk '$1 == "minos" { print $2 }' | sort -u)"
[ "$MINOS" = '11.0' ] || { echo "OpenAL deployment target mismatch: $MINOS" >&2; exit 1; }
printf '%s\r\n' "$(shasum -a 1 "$OUTPUT" | awk '{print $1}')" > "$OUTPUT.sha1"

echo "built OpenAL Soft $VERSION for arm64 macOS $MINOS: $OUTPUT"
