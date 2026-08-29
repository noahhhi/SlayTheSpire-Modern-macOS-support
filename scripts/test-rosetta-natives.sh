#!/bin/bash
# Verify that the candidate jar preserves Steam API and that Rosetta can load
# every x86_64 native without an AOT code-signature supplement failure.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CANDIDATE_JAR="${1:-}"
ORIGINAL_JAR="${2:-}"
[ -f "$CANDIDATE_JAR" ] || { echo 'candidate jar argument is missing' >&2; exit 2; }
[ -f "$ORIGINAL_JAR" ] || { echo 'original jar argument is missing' >&2; exit 2; }
[ "$(uname -m)" = arm64 ] || { echo 'Rosetta test is only needed on Apple Silicon'; exit 0; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sts-rosetta.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
mkdir "$WORK/candidate" "$WORK/original"
unzip -q "$CANDIDATE_JAR" libsteam_api.dylib libsteamworks4j.dylib liblwjgl.dylib -d "$WORK/candidate"
unzip -q "$ORIGINAL_JAR" libsteam_api.dylib -d "$WORK/original"

CANDIDATE_STEAM_SHA="$(shasum -a 256 "$WORK/candidate/libsteam_api.dylib" | awk '{print $1}')"
ORIGINAL_STEAM_SHA="$(shasum -a 256 "$WORK/original/libsteam_api.dylib" | awk '{print $1}')"
[ "$CANDIDATE_STEAM_SHA" = "$ORIGINAL_STEAM_SHA" ] || {
  echo 'candidate replaced the signed original libsteam_api.dylib' >&2
  exit 1
}

for native in "$WORK/candidate"/*.dylib; do
  archs="$(/usr/bin/lipo -archs "$native")"
  case " $archs " in *' x86_64 '*) ;; *) echo "missing x86_64: $native" >&2; exit 1 ;; esac
  codesign --verify --strict "$native"
done

xcrun clang -arch x86_64 -mmacosx-version-min=11.0 \
  "$ROOT/tests/dlopen_natives.c" -o "$WORK/dlopen-natives"
codesign --force -s - "$WORK/dlopen-natives"
arch -x86_64 "$WORK/dlopen-natives" \
  "$WORK/candidate/libsteam_api.dylib" \
  "$WORK/candidate/libsteamworks4j.dylib"

echo 'Rosetta native-load test passed; original Steam API bytes were preserved'
