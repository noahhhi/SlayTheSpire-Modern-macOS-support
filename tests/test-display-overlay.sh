#!/bin/bash
# Guard the notch/HiDPI display fix: the published overlay must contain the
# patched LwjglGraphics and DesktopLauncher classes. The two methods are patched
# with javassist, so pin their hashes and fail loudly if either class drifts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -f display-overlay.sha256 ] || { echo 'missing display-overlay.sha256' >&2; exit 1; }

grep -vE '^[[:space:]]*(#|$)' display-overlay.sha256 | while read -r expected path; do
  [ -f "$path" ] || { echo "missing display overlay: $path" >&2; exit 1; }
  actual="$(shasum -a 256 "$path" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || {
    echo "display overlay changed: $path" >&2
    echo "  expected $expected" >&2
    echo "  actual   $actual" >&2
    exit 1
  }
done

echo 'ok: display overlay keeps the fill and borderless-fullscreen patches'
