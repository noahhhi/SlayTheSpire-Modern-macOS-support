#!/bin/bash
# Builds the distributable zip and pkg into dist/.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(sed -n 's/^patch-version=//p' payload/version.txt)"
[ -n "$VERSION" ] || { echo "version.txt missing patch-version"; exit 1; }

DIST=dist
STAGE="$DIST/stage"
rm -rf "$DIST" pkgtmp
mkdir -p "$STAGE" pkgtmp/root pkgtmp/scripts

# zip staging: scripts + docs + payload
cp install.sh uninstall.sh "Install SlayTheSpire ARM64.command" README.md "$STAGE/"
cp -R payload "$STAGE/payload"
find "$STAGE" -name '.DS_Store' -delete
chmod +x "$STAGE/install.sh" "$STAGE/uninstall.sh" "$STAGE/Install SlayTheSpire ARM64.command" "$STAGE/payload/launcher"
chmod +x "$STAGE/payload/jre/bin/"* 2>/dev/null || true
find "$STAGE/payload/jre" -name '*.dylib' -exec chmod +x {} + 2>/dev/null || true
( cd "$STAGE" && zip -q -r -y "../SlayTheSpire-ARM64-macOS-v${VERSION}.zip" . )

# pkg: payload lands in /private/tmp/sts-arm64-install, postinstall runs install.sh
cp -R "$STAGE"/. pkgtmp/root/
cp pkg-scripts/postinstall pkgtmp/scripts/postinstall
chmod +x pkgtmp/scripts/postinstall
pkgbuild --root pkgtmp/root --scripts pkgtmp/scripts \
  --identifier io.github.noahhhi.slaythespire-arm64 \
  --version "$VERSION" \
  --ownership recommended \
  --install-location /private/tmp/sts-arm64-install \
  "$DIST/SlayTheSpire-ARM64-macOS-v${VERSION}.pkg"

rm -rf pkgtmp "$STAGE"
echo "built:"
ls -lh "$DIST"
