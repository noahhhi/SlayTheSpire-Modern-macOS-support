#!/bin/bash
# Re-apply the two display fixes to the upstream overlay classes.
#
# 1. LwjglGraphics.setupDisplay: the upstream port keeps the logical canvas at
#    the saved window size while the real window is clamped to the visible
#    screen area. The FitViewport then preserves the wrong aspect and pillarboxes
#    the game (the thick left/right black bars on notch MacBooks). After the
#    window exists, copy its real size into the logical fields so the viewport
#    fills the whole drawable area.
# 2. DesktopLauncher.loadSettings: fullscreen / borderless-fullscreen requests an
#    undecorated window, so no title bar is wasted and the game fills everything
#    below the menu-bar/notch strip.
#
# Usage: scripts/prepare-display-overlay.sh <upstream-overlay-class-dir> <game desktop-1.0.jar>
# JAVASSIST_JAR may point at any jar bundling javassist (defaults to the Steam
# Workshop ModTheSpire.jar).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="${1:-}"
GAME_JAR="${2:-}"
MTS_JAR="${JAVASSIST_JAR:-$HOME/Library/Application Support/Steam/steamapps/workshop/content/646570/1605060445/ModTheSpire.jar}"
JAVAC="${JAVAC:-javac}"
JAVA="${JAVA:-java}"

[ -n "$INPUT" ] && [ -n "$GAME_JAR" ] || {
  echo "usage: $0 <upstream-overlay-class-dir> <game desktop-1.0.jar>" >&2
  exit 2
}
[ -f "$INPUT/com/badlogic/gdx/backends/lwjgl/LwjglGraphics.class" ] \
  || { echo "missing LwjglGraphics.class under $INPUT" >&2; exit 1; }
[ -f "$INPUT/com/megacrit/cardcrawl/desktop/DesktopLauncher.class" ] \
  || { echo "missing DesktopLauncher.class under $INPUT" >&2; exit 1; }
[ -f "$GAME_JAR" ] || { echo "missing game jar: $GAME_JAR" >&2; exit 1; }
[ -f "$MTS_JAR" ] || { echo "missing javassist jar: $MTS_JAR" >&2; exit 1; }
command -v "$JAVAC" >/dev/null 2>&1 || { echo "javac not found: $JAVAC" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sts-display.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
mkdir -p "$WORK/classes" "$WORK/out"

cat > "$WORK/PrepareDisplayOverlay.java" <<'JAVA'
import javassist.ClassPool;
import javassist.CtClass;
import javassist.CtMethod;

public final class PrepareDisplayOverlay {
    public static void main(String[] args) throws Exception {
        ClassPool pool = new ClassPool(true);
        pool.appendClassPath(args[1]);
        pool.insertClassPath(args[0]);

        CtClass graphics = pool.get("com.badlogic.gdx.backends.lwjgl.LwjglGraphics");
        CtMethod setup = graphics.getDeclaredMethod("setupDisplay", new CtClass[0]);
        setup.insertAfter(
                "this.logicalWidth = this.windowWidth;" +
                "this.logicalHeight = this.windowHeight;" +
                "this.updateBackBufferViewport();");

        CtClass launcher = pool.get("com.megacrit.cardcrawl.desktop.DesktopLauncher");
        CtMethod load = launcher.getDeclaredMethod("loadSettings",
                new CtClass[] { pool.get("com.badlogic.gdx.backends.lwjgl.LwjglApplicationConfiguration") });
        load.insertAfter(
                "com.megacrit.cardcrawl.core.DisplayConfig __config =" +
                " com.megacrit.cardcrawl.core.DisplayConfig.readConfig();" +
                "if (__config.getIsFullscreen() || __config.getWFS()) {" +
                "  System.setProperty(\"org.lwjgl.opengl.Window.undecorated\", \"true\");" +
                "}");

        graphics.writeFile(args[2]);
        launcher.writeFile(args[2]);
    }
}
JAVA

"$JAVAC" -cp "$MTS_JAR" -d "$WORK/classes" "$WORK/PrepareDisplayOverlay.java"
"$JAVA" -cp "$WORK/classes:$MTS_JAR" PrepareDisplayOverlay \
  "$INPUT" "$GAME_JAR" "$WORK/out"

cp -p "$WORK/out/com/badlogic/gdx/backends/lwjgl/LwjglGraphics.class" \
  "$ROOT/payload/jar/com/badlogic/gdx/backends/lwjgl/LwjglGraphics.class"
cp -p "$WORK/out/com/megacrit/cardcrawl/desktop/DesktopLauncher.class" \
  "$ROOT/payload/jar/com/megacrit/cardcrawl/desktop/DesktopLauncher.class"

bash "$ROOT/tests/test-display-overlay.sh"
