#!/bin/bash
# Offline end-to-end regression for PackageKit postinstall status propagation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POSTINSTALL="$ROOT/pkg-scripts/postinstall"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sts-postinstall-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
mkdir "$WORK/bin"

# Minimal stand-ins for the macOS account/session commands. The copied
# postinstall still executes the production status runner and payload script.
printf '#!/bin/bash\nprintf "offline-user\\n"\n' > "$WORK/bin/stat"
printf '#!/bin/bash\nprintf "NFSHomeDirectory: /tmp/offline-user\\n"\n' > "$WORK/bin/dscl"
printf '#!/bin/bash\nprintf "501\\n"\n' > "$WORK/bin/id"
printf '#!/bin/bash\nshift 2\nexec "$@"\n' > "$WORK/bin/launchctl"
printf '#!/bin/bash\nshift 2\nexec "$@"\n' > "$WORK/bin/sudo"
chmod +x "$WORK/bin/"*

run_case() {
  local name="$1"
  local installer_status="$2"
  local expected_status="$3"
  local payload="$WORK/payload-$name"
  local test_postinstall="$WORK/postinstall-$name"
  local actual_status

  mkdir "$payload"
  printf '#!/bin/bash\nexit %s\n' "$installer_status" > "$payload/install.sh"
  chmod +x "$payload/install.sh"
  sed \
    -e "s#^DIR=.*#DIR='$payload'#" \
    -e "s#^SCRIPT_DIR=.*#SCRIPT_DIR='$ROOT/pkg-scripts'#" \
    "$POSTINSTALL" > "$test_postinstall"
  chmod +x "$test_postinstall"

  set +e
  PATH="$WORK/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$test_postinstall"
  actual_status=$?
  set -e

  [ "$actual_status" -eq "$expected_status" ] || {
    echo "$name: expected exit $expected_status, got $actual_status" >&2
    exit 1
  }
  [ ! -e "$payload" ] || {
    echo "$name: temporary package payload was not cleaned up" >&2
    exit 1
  }
  echo "$name: exit $actual_status and cleanup verified"
}

run_case success 0 0
run_case existing-backup-refusal 1 1
echo 'postinstall offline regression passed'
