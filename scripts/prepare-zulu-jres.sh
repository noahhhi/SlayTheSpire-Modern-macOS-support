#!/bin/bash
# Fetch the pinned Azul Zulu OpenJDK 8 JREs used by the Universal release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/payload/jre"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sts-zulu.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

ARM_URL='https://cdn.azul.com/zulu/bin/zulu8.96.0.205-ca-jre8.0.504-macosx_aarch64.zip'
ARM_SHA='1769ea082fa13ba29403363425716451b04b10f5ae6dba07f7f0a69666197f15'
X64_URL='https://cdn.azul.com/zulu/bin/zulu8.96.0.205-ca-jre8.0.504-macosx_x64.zip'
X64_SHA='b2a195c418fe926e5c2032bfd3fb23ed93b1133f50b99cb2c0e47dc618130e5d'

fetch_one() {
  local arch="$1"
  local url="$2"
  local expected="$3"
  local archive="$WORK/$arch.zip"
  local extract="$WORK/extract-$arch"
  local home actual java_archs

  echo "Downloading Zulu JRE for $arch..."
  curl -fL --retry 3 --output "$archive" "$url"
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || {
    echo "Zulu $arch archive checksum mismatch: $actual" >&2
    exit 1
  }
  mkdir "$extract"
  unzip -q "$archive" -d "$extract"
  home="$(find "$extract" -type d -path '*/Contents/Home' -print -quit)"
  [ -n "$home" ] && [ -x "$home/bin/java" ] || {
    echo "Zulu $arch archive has an unexpected layout" >&2
    exit 1
  }
  mkdir -p "$WORK/staged/$arch"
  cp -R "$home/." "$WORK/staged/$arch/"
  java_archs="$(/usr/bin/lipo -archs "$WORK/staged/$arch/bin/java")"
  case " $java_archs " in *" $arch "*) ;; *) echo "Zulu java is not $arch: $java_archs" >&2; exit 1 ;; esac
}

fetch_one arm64 "$ARM_URL" "$ARM_SHA"
fetch_one x86_64 "$X64_URL" "$X64_SHA"

rm -rf "$TARGET"
mkdir -p "$(dirname "$TARGET")"
mv "$WORK/staged" "$TARGET"
echo "Prepared matching Azul Zulu 8.96.0.205 JREs in $TARGET"
