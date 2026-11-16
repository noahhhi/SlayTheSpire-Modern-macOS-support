"""Behavior tests for the actual shipped Java 8 class, without native Steam calls.
The real game's Steam ID classes are additionally exercised by the bounded
candidate launcher test documented in the release notes.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ENTRY = Path('com/megacrit/mtslauncher/MtsFinder.class')
JAVA = os.environ['STS_TEST_JAVA']
JAVAC = os.environ['STS_TEST_JAVAC']
with tempfile.TemporaryDirectory(prefix='sts-finder-test-') as tmp:
    work = Path(tmp).resolve()
    src = work / 'src'
    api = src / 'com/codedisaster/steamworks'
    api.mkdir(parents=True)
    (api / 'SteamNativeHandle.java').write_text('''package com.codedisaster.steamworks;
public abstract class SteamNativeHandle {
 long handle; SteamNativeHandle(long h) { handle = h; }
 public static <T extends SteamNativeHandle> long getNativeHandle(T h) { return h.handle; }
}''')
    (api / 'SteamPublishedFileID.java').write_text('''package com.codedisaster.steamworks;
public class SteamPublishedFileID extends SteamNativeHandle {
 public SteamPublishedFileID(long h) { super(h); }
}''')
    harness = src / 'com/megacrit/mtslauncher/Probe.java'
    harness.parent.mkdir(parents=True)
    harness.write_text('''package com.megacrit.mtslauncher;
import com.codedisaster.steamworks.SteamPublishedFileID;
import java.nio.file.Paths;
public class Probe {
 public static void main(String[] args) {
  String actual = new MtsFinder().findModLauncher(Integer.parseInt(args[1]),
    new SteamPublishedFileID(Long.parseLong(args[2])), Paths.get(args[3]));
  if (!String.valueOf(actual).equals(args[0]))
    throw new AssertionError("expected=" + args[0] + "; actual=" + actual);
 }
}''')
    classes = work / 'classes'
    subprocess.run([JAVAC, '--release', '8', '-encoding', 'UTF-8', '-d', str(classes),
                    *map(str, src.rglob('*.java')),
                    str(ROOT / 'launcher/mts-src/com/megacrit/mtslauncher/MtsFinder.java')], check=True)
    shipped = (ROOT / 'launcher/mts-classes' / ENTRY).read_bytes()
    assert (classes / ENTRY).read_bytes() == shipped, 'source and shipped class disagree'
    assert shipped[:8] == bytes.fromhex('cafebabe00000034')
    for forbidden in (b'SteamAPI', b'SteamUGC', b'loadLibrary'):
        assert forbidden not in shipped
    assert list((ROOT / 'launcher/mts-classes').rglob('*.class')) == [ROOT / 'launcher/mts-classes' / ENTRY]
    count = 0

    def case(name, layout=None, target='ModTheSpire.jar', app='646570', item='1605060445', bad_write=False):
        global count
        base = work / name
        home = base / 'home'
        steam = home / 'Library/Application Support/Steam'
        steam.mkdir(parents=True)
        cwd = base / 'cwd'
        cwd.mkdir()
        expected = 'null'
        if layout == 'default':
            library = steam
        else:
            library = base / '外置 library "quoted" \\ drive'
        jar = library / f'steamapps/workshop/content/646570/{item}/ModTheSpire.jar'
        if layout:
            jar.parent.mkdir(parents=True)
            jar.write_bytes(b'fixture')
            expected = str(jar)
        if layout in ('modern', 'legacy', 'config', 'malformed-first'):
            vdf = steam / ('config' if layout in ('legacy', 'config') else 'steamapps') / 'libraryfolders.vdf'
            vdf.parent.mkdir(exist_ok=True)
            escaped = str(library).replace('\\', '\\\\').replace('"', '\\"')
            key = '1' if layout == 'legacy' else 'path'
            vdf.write_text('"libraryfolders"\n{\n "0"\n {\n  "'+key+'" "'+escaped+'"\n }\n}\n')
            if layout == 'malformed-first':
                vdf.write_text('not valid VDF\n')
                other = steam / 'config/libraryfolders.vdf'
                other.parent.mkdir()
                other.write_text('"path" "'+escaped+'"\n')
        if layout == 'own-library':
            cwd = library / 'steamapps/common/Game.app/Contents/Resources'
            cwd.mkdir(parents=True)
        if bad_write:
            (cwd / 'steam_appid.txt').mkdir()
            expected = 'null'
        env = {k:v for k,v in os.environ.items() if k not in ('JAVA_TOOL_OPTIONS','_JAVA_OPTIONS','JDK_JAVA_OPTIONS')}
        result = subprocess.run([JAVA, '-Duser.home='+str(home), '-cp', str(classes),
                                 'com.megacrit.mtslauncher.Probe', expected, app, item, target],
                                cwd=cwd, env=env, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, (name,result.stdout,result.stderr)
        assert 'UnsatisfiedLinkError' not in result.stderr
        if app == '646570' and not bad_write and target == 'ModTheSpire.jar':
            assert (cwd / 'steam_appid.txt').read_text() == '646570'
        count += 1
        print('PASS', name, flush=True)

    case('default', 'default')
    case('modern-spaces-unicode-escapes', 'modern')
    case('legacy-numeric-library', 'legacy')
    case('config-path-library', 'config')
    case('fallback-from-malformed-list', 'malformed-first')
    case('game-own-library', 'own-library')
    case('missing-subscription')
    case('different-workshop-id', 'default', item='123456789')
    case('reject-parent-traversal', target='../bad.jar')
    case('reject-absolute-target', target='/tmp/bad.jar')
    case('reject-other-app', app='1')
    case('appid-write-failure', 'default', bad_write=True)
    print(f'{count}/{count} Java 8 finder cases passed; source matches shipped bytecode.')
