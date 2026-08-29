#!/bin/bash
# Build and verify the Universal ZIP and component PKG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' < VERSION)"
[ -n "$VERSION" ] || { echo 'VERSION is empty' >&2; exit 1; }

DIST="$ROOT/dist"
WORK="$(mktemp -d "$ROOT/.release-build.XXXXXX")"
STAGE="$WORK/stage"
PKGROOT="$WORK/pkgroot"
PKGSCRIPTS="$WORK/pkg-scripts"
PKG_EXPANDED="$WORK/pkg-expanded"
INSTALL_LOCATION='/Library/Application Support/SlayTheSpire-Modern-Installer'
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

[ -x payload/jre/arm64/bin/java ] || { echo 'run scripts/prepare-zulu-jres.sh first' >&2; exit 1; }
[ -x payload/jre/x86_64/bin/java ] || { echo 'run scripts/prepare-zulu-jres.sh first' >&2; exit 1; }
[ -d payload/jar ] || { echo 'payload/jar is missing' >&2; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST" "$STAGE" "$PKGROOT$INSTALL_LOCATION" "$PKGSCRIPTS"
cp install.sh uninstall.sh 'Install SlayTheSpire Modern macOS.command' \
  install-state.sh README.md README.zh-CN.md RELEASE_NOTES.md VERSION \
  supported-versions.sha256 "$STAGE/"
cp -R payload "$STAGE/payload"
rm -f "$STAGE/payload/version.txt"
rm -f "$STAGE/payload/jar/libsteam_api.dylib" "$STAGE/payload/jar/libsteam_api.dylib.sha1"
find "$STAGE" -name '.DS_Store' -delete
find "$STAGE" -name '._*' -delete
chmod +x "$STAGE/install.sh" "$STAGE/uninstall.sh" \
  "$STAGE/Install SlayTheSpire Modern macOS.command" "$STAGE/payload/launcher"
find "$STAGE/payload/jre" -path '*/bin/*' -type f -exec chmod +x {} +

(
  cd "$STAGE"
  find payload -type f -print | LC_ALL=C sort | while IFS= read -r path; do
    shasum -a 256 "$path"
  done > payload.sha256
)

"$ROOT/scripts/verify-release.sh" "$STAGE"

ZIP="$DIST/SlayTheSpire-Modern-macOS-v${VERSION}-universal.zip"
(
  cd "$STAGE"
  zip -q -X -r -y "$ZIP" . -x '*.DS_Store' -x '._*' -x '__MACOSX/*'
)
unzip -tq "$ZIP" >/dev/null
unzip -Z1 "$ZIP" | grep -Eq '(^|/)(desktop-1\.0\.jar|SlayTheSpire\.app)(/|$)' \
  && { echo 'game content found in ZIP' >&2; exit 1; } || true
unzip -Z1 "$ZIP" | grep -Eq '(^|/)(\._|__MACOSX)' \
  && { echo 'AppleDouble content found in ZIP' >&2; exit 1; } || true

cp -R "$STAGE/." "$PKGROOT$INSTALL_LOCATION/"
# pkgbuild normalizes metadata while archiving. Give the temporary package
# root owner write access so read-only files inside the upstream JRE do not
# produce misleading "write: Permission denied" diagnostics.
chmod -R u+w "$PKGROOT"
cp pkg-scripts/postinstall "$PKGSCRIPTS/postinstall"
cp pkg-scripts/run-installer.sh "$PKGSCRIPTS/run-installer.sh"
chmod +x "$PKGSCRIPTS/postinstall" "$PKGSCRIPTS/run-installer.sh"
PKG="$DIST/SlayTheSpire-Modern-macOS-v${VERSION}-universal.pkg"
pkgbuild --root "$PKGROOT" --scripts "$PKGSCRIPTS" \
  --component-plist packaging/components.plist \
  --identifier io.github.noahhhi.slaythespire-modern \
  --version "$VERSION" --ownership recommended --install-location / "$PKG"

pkgutil --expand "$PKG" "$PKG_EXPANDED"
[ -z "$(find "$PKG_EXPANDED" \( -name '._*' -o -name '.DS_Store' \) -print -quit)" ] \
  || { echo 'AppleDouble content found in PKG' >&2; exit 1; }
pkgutil --payload-files "$PKG" | grep -Eq '(^|/)(desktop-1\.0\.jar|SlayTheSpire\.app)(/|$)' \
  && { echo 'game content found in PKG' >&2; exit 1; } || true

for artifact in "$PKG" "$ZIP"; do
  (cd "$DIST" && shasum -a 256 "$(basename "$artifact")" > "$(basename "$artifact").sha256")
done

echo 'Built and verified:'
ls -lh "$DIST"
