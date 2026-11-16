#!/bin/bash
# Build the Universal (arm64 + x86_64) Cocoa window bridge used by the overlay.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAVA_HOME_GUESS="${JAVA_HOME:-}"
if [ -z "$JAVA_HOME_GUESS" ] || [ ! -f "$JAVA_HOME_GUESS/include/jni.h" ]; then
  for candidate in /opt/homebrew/opt/openjdk /opt/homebrew/opt/openjdk@17 /opt/homebrew/opt/openjdk@21; do
    if [ -f "$candidate/include/jni.h" ]; then JAVA_HOME_GUESS="$candidate"; break; fi
  done
fi
[ -f "$JAVA_HOME_GUESS/include/jni.h" ] || {
  echo 'JNI headers not found; set JAVA_HOME to a JDK' >&2
  exit 1
}

OUT="$ROOT/payload/jar/libstsmacwindow.dylib"
clang -dynamiclib -O2 -fobjc-arc -mmacosx-version-min=11.0 \
  -arch arm64 -arch x86_64 \
  -I "$JAVA_HOME_GUESS/include" -I "$JAVA_HOME_GUESS/include/darwin" \
  -framework Cocoa \
  -install_name @rpath/libstsmacwindow.dylib \
  -o "$OUT" "$ROOT/native/StsMacWindow.m"
chmod 644 "$OUT"
codesign --force -s - "$OUT"
codesign --verify --strict "$OUT"
echo "built: $OUT ($(lipo -archs "$OUT"))"
