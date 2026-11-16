#!/bin/bash
# Download the official patch release; the user must already own the game.
# Keep the work inside main so a truncated curl stream cannot start a download.
set -euo pipefail

log() { printf '[sts-download] %s\n' "$*"; }
fail() { printf '[sts-download] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: bash install-oneline.sh [--dry-run]
       curl -fsSL <published-script-url> | bash -s -- [--dry-run]

Downloads and verifies the v1.2.8 Universal patch for macOS 11+.
Set STS_APP_PATH on the bash process to select a custom SlayTheSpire.app.
--dry-run is passed to install.sh; it validates and stages a candidate without
replacing game files. The existing installer creates temporary files beside
the game. Without --dry-run, install.sh backs up and modifies the game.
USAGE
}

cleanup() {
  local rc=$1
  trap - EXIT HUP INT TERM
  if [ -n "${temp_dir:-}" ] && [ -d "$temp_dir" ]; then
    if ! rm -rf -- "$temp_dir"; then
      printf '[sts-download] WARNING: could not remove temporary directory: %s\n' "$temp_dir" >&2
      [ "$rc" -ne 0 ] || rc=1
    fi
  fi
  exit "$rc"
}

main() {
  local version=v1.2.8
  local archive_sha256='ea3801e0b1f46afa75110c03c4d9b5a50910d59a5f34acc2fc1ede84cdf969a1'
  local asset base_url archive checksum unpack_dir expected actual tool arg rc
  local dry_run=0

  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=1 ;;
      -h|--help) usage; return 0 ;;
      *) printf '[sts-download] ERROR: unknown argument: %s\n' "$arg" >&2
         usage >&2; return 2 ;;
    esac
  done

  [ "$(uname -s)" = Darwin ] || fail 'only macOS is supported'
  for tool in curl shasum unzip mktemp mkdir awk rm; do
    command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
  done

  asset="SlayTheSpire-Modern-macOS-${version}-universal.zip"
  base_url="https://github.com/noahhhi/SlayTheSpire-Modern-macOS-support/releases/download/${version}"
  temp_dir=''
  trap 'cleanup "$?"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sts-modern.XXXXXXXX")" \
    || fail 'could not create a temporary directory'
  archive="$temp_dir/$asset"
  checksum="$archive.sha256"
  unpack_dir="$temp_dir/release"

  log "Downloading the ${version} checksum..."
  # -q must be first: ignore curlrc settings. Require HTTPS across redirects.
  curl -q -fL --proto '=https' --proto-redir '=https' \
    --retry 2 --connect-timeout 20 --max-time 600 \
    "$base_url/$asset.sha256" -o "$checksum" \
    || fail 'checksum download failed; refusing to install without verification'

  # Accept exactly one shasum-format record for this exact asset. Never feed
  # unchecked filenames from a remote manifest to shasum -c.
  expected="$(awk -v name="$asset" '
    { sub(/\r$/, "") }
    NR == 1 && NF == 2 && length($1) == 64 && $1 !~ /[^0-9a-fA-F]/ &&
      ($2 == name || $2 == "*" name) { hash=tolower($1); valid=1 }
    END { if (NR != 1 || !valid) exit 1; print hash }
  ' "$checksum")" || fail 'invalid checksum file (expected one SHA-256 record for the release ZIP)'

  [ "$expected" = "$archive_sha256" ] \
    || fail 'release checksum differs from the SHA-256 pinned in this installer'

  log "Downloading $asset (about 83 MB)..."
  curl -q -fL --proto '=https' --proto-redir '=https' \
    --retry 2 --connect-timeout 20 --max-time 600 \
    "$base_url/$asset" -o "$archive" \
    || fail 'release ZIP download failed'

  log 'Verifying SHA-256...'
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')" \
    || fail 'could not calculate ZIP SHA-256'
  [ "$actual" = "$expected" ] \
    || fail "SHA-256 mismatch; refusing to extract or run the installer (expected $expected; got $actual)"
  log 'SHA-256 verified.'

  mkdir "$unpack_dir" || fail 'could not create extraction directory'
  unzip -q "$archive" -d "$unpack_dir" || fail 'release ZIP extraction failed'
  # v1.2.8 puts install.sh at the ZIP root. Refuse other layouts explicitly.
  [ -f "$unpack_dir/install.sh" ] && [ ! -L "$unpack_dir/install.sh" ] \
    || fail 'release ZIP has no regular install.sh at its root'

  if [ -n "${STS_APP_PATH:-}" ]; then
    set -- "$@" "$STS_APP_PATH"
    log "Selected app: $STS_APP_PATH"
  else
    log 'Using the installer Steam-library auto-detection.'
  fi
  if [ "$dry_run" = 1 ]; then
    log 'Running install.sh --dry-run (no replacement of game files)...'
  else
    log 'Running install.sh; it will back up and modify the installed game...'
  fi

  # Keep stdin separate from a curl | bash script stream. Do not exec: EXIT
  # must run after the installer finishes to remove the downloaded payload.
  # Do not wrap main itself in an if/||: that would disable errexit inside it.
  rc=0
  /bin/bash "$unpack_dir/install.sh" "$@" </dev/null || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '[sts-download] ERROR: install.sh failed (exit %s).\n' "$rc" >&2
    return "$rc"
  fi
  if [ "$dry_run" = 1 ]; then
    log 'Dry run completed. Temporary download files will now be removed.'
  else
    log 'Installation completed. Launch the game from Steam.'
    log 'Temporary downloads will be removed; download the ZIP again if you need uninstall.sh.'
  fi
}

# Parse the complete invocation before running it, including when streamed.
{
  main "$@"
}
