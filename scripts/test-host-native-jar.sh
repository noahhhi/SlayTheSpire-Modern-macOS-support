#!/bin/bash
# Verify that an installed candidate jar contains only the selected host slice.
set -euo pipefail

CANDIDATE_JAR="${1:-}"
EXPECTED_ARCH="${2:-$(uname -m)}"

[ -f "$CANDIDATE_JAR" ] || {
  echo 'candidate jar argument is missing' >&2
  exit 2
}
case "$EXPECTED_ARCH" in
  arm64|x86_64) ;;
  *) echo "unsupported expected architecture: $EXPECTED_ARCH" >&2; exit 2 ;;
esac

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sts-host-native.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
mkdir -p "$WORK/native"
while IFS= read -r entry; do
  case "$entry" in
    *.dylib|*.jnilib)
      mkdir -p "$WORK/native/$(dirname "$entry")"
      unzip -p "$CANDIDATE_JAR" "$entry" > "$WORK/native/$entry"
      ;;
  esac
done < <(unzip -Z1 "$CANDIDATE_JAR")

count=0
while IFS= read -r -d '' native; do
  count=$((count + 1))
  archs="$(/usr/bin/lipo -archs "$native" 2>/dev/null || true)"
  [ "$archs" = "$EXPECTED_ARCH" ] || {
    echo "not $EXPECTED_ARCH-only: ${native#"$WORK/native/"} ($archs)" >&2
    exit 1
  }
  codesign --verify --strict "$native"
done < <(find "$WORK/native" -type f \( -name '*.dylib' -o -name '*.jnilib' \) -print0)

[ "$count" -gt 0 ] || { echo 'candidate jar contains no macOS native libraries' >&2; exit 1; }

if [ "$EXPECTED_ARCH" = arm64 ]; then
  [ -f "$WORK/native/libsteam_api_arm64.dylib" ] || {
    echo 'arm64 candidate is missing libsteam_api_arm64.dylib' >&2
    exit 1
  }
else
  [ ! -e "$WORK/native/libsteam_api_arm64.dylib" ] || {
    echo 'x86_64 candidate must not contain libsteam_api_arm64.dylib' >&2
    exit 1
  }
fi

echo "host-native jar test passed: $count signed macOS natives are $EXPECTED_ARCH-only"
