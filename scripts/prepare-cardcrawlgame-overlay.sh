#!/bin/bash
# Rebuild payload/jar/com/megacrit/cardcrawl/core/CardCrawlGame.class from the
# unmodified Steam jar.
#
# The upstream HiDPI build recompiled this class from decompiled source. That
# removed its LocalVariableTable and shifted every source line number, so
# ModTheSpire patches that bind a named local fail; BaseMod's CustomRewardLoad
# reads the loop variable "i" and aborts with:
#     javassist.CannotCompileException: [source error] no such field: i
#
# The game only needs one change here: CardCrawlGame.resize(int, int) must tell
# StsDisplay that the window size changed. Keeping the original bytecode and
# inserting just that call preserves line numbers and locals, so the same
# BaseMod release works on Intel and Apple silicon.
#
# Usage: scripts/prepare-cardcrawlgame-overlay.sh <original desktop-1.0.jar>
# JAVASSIST_JAR may point at any jar bundling javassist (defaults to the
# Steam Workshop ModTheSpire.jar).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIGINAL_JAR="${1:-}"
MTS_JAR="${JAVASSIST_JAR:-$HOME/Library/Application Support/Steam/steamapps/workshop/content/646570/1605060445/ModTheSpire.jar}"
JAVAC="${JAVAC:-javac}"
JAVA="${JAVA:-java}"

[ -n "$ORIGINAL_JAR" ] || {
  echo "usage: $0 <original desktop-1.0.jar>" >&2
  exit 2
}
[ -f "$ORIGINAL_JAR" ] || { echo "missing jar: $ORIGINAL_JAR" >&2; exit 1; }
[ -f "$MTS_JAR" ] || { echo "missing javassist jar: $MTS_JAR" >&2; exit 1; }
command -v "$JAVAC" >/dev/null 2>&1 || { echo "javac not found: $JAVAC" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sts-cardcrawlgame.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
mkdir -p "$WORK/original" "$WORK/classes" "$WORK/out"

(
  cd "$WORK/original"
  unzip -o -q "$ORIGINAL_JAR" 'com/megacrit/cardcrawl/core/CardCrawlGame.class'
)

cat > "$WORK/AddResizeHook.java" <<'JAVA'
import javassist.ClassPool;
import javassist.CtClass;
import javassist.CtMethod;

public final class AddResizeHook {
    public static void main(String[] args) throws Exception {
        ClassPool pool = new ClassPool(true);
        pool.appendClassPath(args[1]);
        pool.insertClassPath(args[0]);
        CtClass cc = pool.get("com.megacrit.cardcrawl.core.CardCrawlGame");
        CtMethod resize = cc.getDeclaredMethod("resize",
                new CtClass[] { CtClass.intType, CtClass.intType });
        resize.insertBefore(
                "com.megacrit.cardcrawl.desktop.StsDisplay.onWindowResize($1, $2);");
        cc.writeFile(args[2]);
    }
}
JAVA

"$JAVAC" -cp "$MTS_JAR" -d "$WORK/classes" "$WORK/AddResizeHook.java"
"$JAVA" -cp "$WORK/classes:$MTS_JAR" AddResizeHook \
  "$WORK/original" "$ROOT/payload/jar" "$WORK/out"

TARGET="$ROOT/payload/jar/com/megacrit/cardcrawl/core/CardCrawlGame.class"
cp -p "$WORK/out/com/megacrit/cardcrawl/core/CardCrawlGame.class" "$TARGET"

# The upstream tree also emitted recompiled copies of helper classes that are
# instruction-identical to the Steam originals. Shipping them only removes
# debug metadata, so leave the originals in the game jar untouched. The list is
# shared with tests/test-overlay-debug-info.py.
while IFS= read -r helper; do
  case "$helper" in ''|'#'*) continue ;; esac
  [ ! -e "$ROOT/payload/jar/$helper" ] || rm "$ROOT/payload/jar/$helper"
done < "$ROOT/overlay-drop.txt"

python3 "$ROOT/tests/test-overlay-debug-info.py"
shasum -a 256 "$TARGET"
