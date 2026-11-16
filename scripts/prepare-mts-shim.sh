#!/bin/bash
# Compile only our replacement, against the user's original launcher API.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIGINAL="${1:?usage: prepare-mts-shim.sh ORIGINAL_MTS_LAUNCHER_JAR}"
JAVAC="${JAVAC:-/opt/homebrew/opt/openjdk@17/bin/javac}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sts-mts-compile.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
"$JAVAC" --release 8 -encoding UTF-8 -cp "$ORIGINAL" -d "$WORK" \
  "$ROOT/launcher/mts-src/com/megacrit/mtslauncher/MtsFinder.java"
mkdir -p "$ROOT/launcher/mts-classes/com/megacrit/mtslauncher"
cp "$WORK/com/megacrit/mtslauncher/MtsFinder.class" \
  "$ROOT/launcher/mts-classes/com/megacrit/mtslauncher/MtsFinder.class"
