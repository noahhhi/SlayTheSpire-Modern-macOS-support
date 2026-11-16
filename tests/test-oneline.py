#!/usr/bin/env python3
"""Offline integration tests. Never reads or executes the real release installer.

Uses macOS /bin/bash, real shasum, and real unzip against generated tiny ZIPs.
The curl shim has no network implementation; every request uses a local file.
"""
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "install-oneline.sh"
ASSET = "SlayTheSpire-Modern-macOS-v1.2.3-universal.zip"
BASE = "https://github.com/noahhhi/SlayTheSpire-Modern-macOS-support/releases/download/v1.2.3/"
REAL_UNZIP = shutil.which("unzip")
REAL_SHASUM = shutil.which("shasum")
assert REAL_UNZIP and REAL_SHASUM

INSTALLER = r'''#!/bin/bash
set -euo pipefail
printf '%s\0' "$@" > "$FIXTURE_DIR/args"
printf '%s\n' "$#" > "$FIXTURE_DIR/argc"
printf '%s\n' "$0" > "$FIXTURE_DIR/executed"
if IFS= read -r line; then
  printf 'unexpected stdin: %s\n' "$line" >&2
  exit 91
fi
exit "${FIXTURE_INSTALL_EXIT:-0}"
'''


def executable(path, content):
    path.write_text(content)
    path.chmod(0o755)


def run_case(root, name, *, args=(), app=None, checksum_mode="normal",
             archive_mode="normal", env_extra=None, expected_rc=0,
             called=False, expected_message=None, pipe=False, missing_tool=False,
             script_bytes=None, wrong_pin=False):
    case = root / name
    case.mkdir()
    fake_bin = case / "bin"
    fake_bin.mkdir()
    temp = case / "temp with spaces"
    temp.mkdir()
    archive = case / ASSET
    if archive_mode == "invalid":
        archive.write_bytes(b"this is not a ZIP")
    else:
        with zipfile.ZipFile(archive, "w") as z:
            if archive_mode == "missing":
                z.writestr("README.txt", "No installer")
            elif archive_mode == "nested":
                z.writestr("nested/install.sh", INSTALLER)
            elif archive_mode == "symlink":
                z.writestr("real-install.sh", INSTALLER)
                info = zipfile.ZipInfo("install.sh")
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                z.writestr(info, "real-install.sh")
            else:
                z.writestr("install.sh", INSTALLER)
                z.writestr("payload/fixture.txt", "Not a real patch")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = f"{digest}  {ASSET}\n"
    variants = {
        "mismatch": f"{'0' * 64}  {ASSET}\n",
        "wrong-name": f"{digest}  other.zip\n",
        "path-traversal": f"{digest}  ../../other.zip\n",
        "malformed": f"{'g' * 64}  {ASSET}\n",
        "short-hash": f"{digest[:-1]}  {ASSET}\n",
        "empty": "",
        "extra-line": checksum + checksum,
        "html": "<html>error</html>\n",
        "crlf": checksum.replace("\n", "\r\n"),
        "binary": f"{digest.upper()} *{ASSET}\n",
    }
    (case / (ASSET + ".sha256")).write_text(variants.get(checksum_mode, checksum))

    # No real curl fallback: the fixture transport can only copy these two files.
    executable(fake_bin / "curl", f"#!{sys.executable}\n" + r'''
import json, os, pathlib, shutil, signal, sys
p = pathlib.Path(os.environ['FIXTURE_DIR'])
a = sys.argv[1:]
assert a[:2] == ['-q', '-fL'], a
assert a[a.index('--proto')+1] == '=https'
assert a[a.index('--proto-redir')+1] == '=https'
url = a[-3]
assert a[-2] == '-o'
assert url.startswith(os.environ['FIXTURE_BASE'])
name = url.removeprefix(os.environ['FIXTURE_BASE'])
assert name in [os.environ['FIXTURE_ASSET'], os.environ['FIXTURE_ASSET']+'.sha256']
with (p/'downloads').open('a') as f:
    f.write(json.dumps(a)+'\n')
kind = 'checksum' if name.endswith('.sha256') else 'zip'
if os.environ.get('FIXTURE_SIGNAL'):
    os.kill(os.getppid(), getattr(signal, os.environ['FIXTURE_SIGNAL']))
    sys.exit(0)
if os.environ.get('FIXTURE_CURL_FAILURE') == kind:
    pathlib.Path(a[-1]).write_bytes(b'partial download')
    sys.exit(22)
shutil.copyfile(p/name, a[-1])
''')
    executable(fake_bin / "uname", '#!/bin/bash\nprintf "%s\\n" "${FIXTURE_OS:-Darwin}"\n')
    executable(fake_bin / "unzip", '''#!/bin/bash
printf 'unzip\n' >> "$FIXTURE_DIR/extraction"
[ "${FIXTURE_UNZIP_FAILURE:-0}" = 0 ] || exit 9
exec "$FIXTURE_REAL_UNZIP" "$@"
''')
    executable(fake_bin / "shasum", '''#!/bin/bash
[ "${FIXTURE_HASH_FAILURE:-0}" = 0 ] || exit 9
exec "$FIXTURE_REAL_SHASUM" "$@"
''')
    # Isolate inherited installer/test settings and default game discovery.
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('STS_', 'FIXTURE_')) and k not in ('BASH_ENV', 'ENV')}
    env.update(PATH=f"{fake_bin}:/usr/bin:/bin:/usr/sbin:/sbin", TMPDIR=str(temp),
               FIXTURE_DIR=str(case), FIXTURE_BASE=BASE, FIXTURE_ASSET=ASSET,
               FIXTURE_REAL_UNZIP=REAL_UNZIP, FIXTURE_REAL_SHASUM=REAL_SHASUM)
    if app is not None:
        env['STS_APP_PATH'] = app
    if env_extra:
        env.update(env_extra)
    if missing_tool:
        # uname exists, but curl is intentionally absent and PATH has no fallback.
        (fake_bin / 'curl').unlink()
        env['PATH'] = str(fake_bin)
    # Only the local test copy substitutes its tiny fixture digest for the
    # production release pin. The production script has no override switch.
    source = script_bytes if script_bytes is not None else SCRIPT.read_bytes()
    fixture_pin = 'f' * 64 if wrong_pin else digest
    source = re.sub(rb"local archive_sha256='[0-9a-f]{64}'",
                    ("local archive_sha256='"+fixture_pin+"'").encode(), source)
    fixture_script = case / 'install-oneline.sh'
    fixture_script.write_bytes(source)
    command = ['/bin/bash' , '-s', '--', *args] if pipe else ['/bin/bash', str(fixture_script), *args]
    result = subprocess.run(command, input=source if pipe else b'',
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            env=env, cwd=case, timeout=20)
    output = result.stdout.decode()
    assert result.returncode == expected_rc, (name, result.returncode, output)
    assert (case / 'executed').exists() == called, (name, output)
    assert not list(temp.iterdir()), (name, 'temporary directory leaked', output)
    if expected_message:
        assert expected_message in output, (name, output)
    if called:
        expected_args = list(args) + ([app] if app else [])
        count = int((case / 'argc').read_text())
        actual_args = (case / 'args').read_bytes().split(b'\0')[:count]
        assert actual_args == [a.encode() for a in expected_args], (name, actual_args)
        assert str(temp) in (case / 'executed').read_text()
        assert not Path((case / 'executed').read_text().strip()).exists()
    if checksum_mode in ('mismatch', 'wrong-name', 'path-traversal', 'malformed',
                         'short-hash', 'empty', 'extra-line', 'html'):
        assert not (case / 'extraction').exists(), (name, 'extracted before verification')
    if expected_rc == 2 or missing_tool or (env_extra or {}).get('FIXTURE_OS') == 'Linux' or '--help' in args:
        assert not (case / 'downloads').exists(), (name, 'downloaded before preflight')
    print(f'PASS {name}', flush=True)


def main():
    count = 0
    with tempfile.TemporaryDirectory(prefix='fixture run ', dir=ROOT / 'tests') as tmp:
        root = Path(tmp)

        def test(name, **kw):
            nonlocal count
            run_case(root, name, **kw)
            count += 1

        test('default-install-fixture', called=True)
        test('dry-run', args=['--dry-run'], called=True, expected_message='Dry run completed')
        test('app-path-spaces-unicode', args=['--dry-run'],
             app='/Volumes/游戏盘/My Steam/SlayTheSpire.app', called=True)
        test('app-path-shell-metacharacters', app='/fake/$(touch NEVER) ; quote\' ".app', called=True)
        test('empty-app-autodiscovery', app='', called=True)
        test('pipe-style', pipe=True, args=['--dry-run'], app='/fake/Steam Games/Game.app', called=True)
        stream = SCRIPT.read_bytes()
        test('truncated-before-final-brace', pipe=True, args=['--dry-run'],
             script_bytes=stream.rsplit(b'}', 1)[0], expected_rc=2)
        test('truncated-at-main-invocation', pipe=True, args=['--dry-run'],
             script_bytes=stream.rsplit(b'  main', 1)[0] + b'  main', expected_rc=2)
        test('truncated-mid-function', pipe=True, script_bytes=stream[:len(stream)//2], expected_rc=2)
        test('help', args=['--help'], expected_message='Usage:')
        test('unknown-option', args=['--force'], expected_rc=2, expected_message='unknown argument')
        test('positional-arg', args=['/fake/game.app'], expected_rc=2)
        test('non-macos', env_extra={'FIXTURE_OS': 'Linux'}, expected_rc=1, expected_message='only macOS')
        test('missing-curl', missing_tool=True, expected_rc=1, expected_message='required tool not found: curl')
        for kind in ['checksum', 'zip']:
            test(f'download-failure-{kind}', env_extra={'FIXTURE_CURL_FAILURE': kind},
                 expected_rc=1, expected_message='download failed')
        for mode in ['mismatch', 'wrong-name', 'path-traversal', 'malformed', 'short-hash', 'empty', 'extra-line', 'html']:
            test(f'checksum-{mode}', checksum_mode=mode, expected_rc=1,
                 expected_message='checksum differs' if mode == 'mismatch' else 'invalid checksum file')
        for mode in ['crlf', 'binary']:
            test(f'checksum-{mode}', checksum_mode=mode, called=True)
        test('release-pin-mismatch', wrong_pin=True, expected_rc=1, expected_message='checksum differs')
        test('hash-tool-failure', env_extra={'FIXTURE_HASH_FAILURE': '1'}, expected_rc=1,
             expected_message='could not calculate')
        test('unzip-failure', env_extra={'FIXTURE_UNZIP_FAILURE': '1'}, expected_rc=1,
             expected_message='extraction failed')
        test('invalid-zip-correct-hash', archive_mode='invalid', expected_rc=1,
             expected_message='extraction failed')
        for mode in ['missing', 'nested', 'symlink']:
            test(f'installer-{mode}', archive_mode=mode, expected_rc=1,
                 expected_message='no regular install.sh at its root')
        test('installer-failure-status', env_extra={'FIXTURE_INSTALL_EXIT': '37'},
             called=True, expected_rc=37, expected_message='failed (exit 37)')
        for sig, rc in [('SIGHUP', 129), ('SIGINT', 130), ('SIGTERM', 143)]:
            test(f'signal-{sig}', env_extra={'FIXTURE_SIGNAL': sig}, expected_rc=rc)
    print(f'{count}/{count} fixture cases passed; no real installer executed.')


if __name__ == '__main__':
    main()
