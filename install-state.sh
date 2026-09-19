#!/bin/bash
# Record and verify the exact state of an installed patch build.

STS_STATE_ERROR=''

sts_state_error() {
  STS_STATE_ERROR="$1"
  return 1
}

sts_manifest_value() {
  local key="$1"
  local manifest="$2"
  sed -n "s/^${key}=//p" "$manifest" | head -1
}

sts_checksum_value() {
  local checksum_file="$1"
  local wanted_path="$2"
  local hash path line

  while IFS= read -r line; do
    hash="${line%% *}"
    path="${line#* }"
    path="${path# }"
    if [ "$path" = "$wanted_path" ]; then
      printf '%s\n' "$hash"
      return 0
    fi
  done < "$checksum_file"
  return 1
}

# Validate an already installed build against the state recorded beside its
# original-file backup. This is intentionally independent of the incoming
# release payload so a verified older build can be upgraded safely.
sts_verify_recorded_install_state() {
  local backup="$1"
  local jar="$2"
  local resources="$3"
  local macos_dir="$4"
  local installed_info="$5"
  local host_arch="$6"
  local manifest="$backup/install-manifest.txt"
  local expected actual path entry line
  local recorded_jre_files=0
  local actual_jre_files=0

  STS_STATE_ERROR=''
  [ -d "$backup" ] && [ ! -L "$backup" ] \
    || sts_state_error 'backup path is missing, invalid, or a symlink' || return 1
  for path in "$manifest" "$backup/installed-jre.sha256" "$backup/installed-overlay.sha256" \
    "$backup/desktop-1.0.jar" "$backup/jre" "$backup/SlayTheSpire" "$backup/Info.plist"; do
    [ -e "$path" ] || sts_state_error "backup is incomplete: $(basename "$path") is missing" || return 1
  done

  expected="$(sts_manifest_value original-jar-sha256 "$manifest")"
  actual="$(shasum -a 256 "$backup/desktop-1.0.jar" | awk '{print $1}')" || return 1
  [ -n "$expected" ] && [ "$actual" = "$expected" ] \
    || sts_state_error 'preserved original jar does not match its recorded hash' || return 1

  [ -f "$macos_dir/SlayTheSpire" ] && [ -x "$macos_dir/SlayTheSpire" ] \
    || sts_state_error 'installed launcher differs' || return 1
  : "$host_arch" # Older verified builds may legitimately use a script/fat launcher.
  expected="$(sts_manifest_value installed-launcher-sha256 "$manifest")"
  actual="$(shasum -a 256 "$macos_dir/SlayTheSpire" | awk '{print $1}')" || return 1
  [ -n "$expected" ] && [ "$actual" = "$expected" ] \
    || sts_state_error 'installed launcher does not match its recorded hash' || return 1

  [ -f "$installed_info" ] || sts_state_error 'installed Info.plist is missing' || return 1
  expected="$(sts_manifest_value installed-info-plist-sha256 "$manifest")"
  actual="$(shasum -a 256 "$installed_info" | awk '{print $1}')" || return 1
  [ -n "$expected" ] && [ "$actual" = "$expected" ] \
    || sts_state_error 'installed Info.plist differs from the completed install' || return 1

  [ -d "$resources/jre" ] && [ -x "$resources/jre/bin/java" ] \
    || sts_state_error 'installed JRE is missing or not executable' || return 1
  "$resources/jre/bin/java" -version >/dev/null 2>&1 \
    || sts_state_error 'installed JRE launch test failed' || return 1
  while IFS= read -r line; do
    expected="${line%% *}"
    path="${line#* }"
    path="${path# }"
    case "$path" in
      ./*) ;;
      *) sts_state_error 'installed JRE state contains an invalid path'; return 1 ;;
    esac
    case "$path" in
      *'/../'*|../*|*/..) sts_state_error 'installed JRE state escapes its directory'; return 1 ;;
    esac
    [ -f "$resources/jre/${path#./}" ] \
      || sts_state_error "installed JRE file is missing: ${path#./}" || return 1
    actual="$(shasum -a 256 "$resources/jre/${path#./}" | awk '{print $1}')" || return 1
    [ "$actual" = "$expected" ] \
      || sts_state_error "installed JRE file differs: ${path#./}" || return 1
    recorded_jre_files=$((recorded_jre_files + 1))
  done < "$backup/installed-jre.sha256"
  actual_jre_files="$(find "$resources/jre" -type f | wc -l | tr -d ' ')"
  [ "$recorded_jre_files" -gt 0 ] && [ "$actual_jre_files" -eq "$recorded_jre_files" ] \
    || sts_state_error 'installed JRE file set differs' || return 1

  [ -f "$jar" ] && unzip -tq "$jar" >/dev/null \
    || sts_state_error 'installed jar is missing or corrupt' || return 1
  expected="$(sts_manifest_value installed-jar-sha256 "$manifest")"
  actual="$(shasum -a 256 "$jar" | awk '{print $1}')" || return 1
  [ -n "$expected" ] && [ "$actual" = "$expected" ] \
    || sts_state_error 'installed jar differs' || return 1

  while IFS= read -r line; do
    expected="${line%% *}"
    entry="${line#* }"
    entry="${entry# }"
    [ "$entry" != "$line" ] \
      || sts_state_error 'installed overlay manifest contains a malformed entry' || return 1
    entry="${entry#./}"
    case "$entry" in
      *'../'*|../*|*/..) sts_state_error 'installed overlay state contains an invalid path'; return 1 ;;
    esac
    actual="$(unzip -p "$jar" "$entry" | shasum -a 256 | awk '{print $1}')" \
      || { sts_state_error "installed overlay entry is missing: $entry"; return 1; }
    [ "$actual" = "$expected" ] \
      || sts_state_error "installed overlay entry differs: $entry" || return 1
  done < "$backup/installed-overlay.sha256"
}

sts_record_install_state() {
  local backup="$1"
  local patch_version="$2"
  local payload_fingerprint="$3"
  local original_jar_sha="$4"
  local installed_jar="$5"
  local installed_jre="$6"
  local installed_launcher="$7"
  local installed_info="$8"
  local overlay_dir="$9"
  local state_dir="${10:-$backup}"
  local installed_jar_sha installed_launcher_sha installed_info_sha

  mkdir -p "$state_dir" || return 1
  installed_jar_sha="$(shasum -a 256 "$installed_jar" | awk '{print $1}')" || return 1
  installed_launcher_sha="$(shasum -a 256 "$installed_launcher" | awk '{print $1}')" || return 1
  installed_info_sha="$(shasum -a 256 "$installed_info" | awk '{print $1}')" || return 1
  printf 'patch-version=%s\npayload-manifest-sha256=%s\noriginal-jar-sha256=%s\ninstalled-jar-sha256=%s\ninstalled-launcher-sha256=%s\ninstalled-info-plist-sha256=%s\n' \
    "$patch_version" "$payload_fingerprint" "$original_jar_sha" "$installed_jar_sha" \
    "$installed_launcher_sha" "$installed_info_sha" \
    > "$state_dir/install-manifest.txt"
  (
    cd "$installed_jre" || exit 1
    find . -type f -print | LC_ALL=C sort | while IFS= read -r entry; do
      shasum -a 256 "$entry"
    done
  ) > "$state_dir/installed-jre.sha256"
  (
    cd "$overlay_dir" || exit 1
    find . -type f -print | LC_ALL=C sort | while IFS= read -r entry; do
      shasum -a 256 "$entry"
    done
  ) > "$state_dir/installed-overlay.sha256"
}

sts_verify_installed_state() {
  local backup="$1"
  local patch_version="$2"
  local payload_fingerprint="$3"
  local payload_manifest="$4"
  local payload="$5"
  local jar="$6"
  local resources="$7"
  local macos_dir="$8"
  local app="$9"
  local installed_info="${10}"
  local host_arch="${11}"
  local jar_delete="${12}"
  local manifest="$backup/install-manifest.txt"
  local expected actual path rel entry line launcher_archs
  local expected_jre_files=0
  local recorded_jre_files=0
  local actual_jre_files=0

  STS_STATE_ERROR=''
  [ -d "$backup" ] && [ ! -L "$backup" ] \
    || sts_state_error 'backup path is missing, invalid, or a symlink' || return 1
  for path in "$manifest" "$backup/installed-jre.sha256" "$backup/installed-overlay.sha256" \
    "$backup/desktop-1.0.jar" "$backup/jre" "$backup/SlayTheSpire" "$backup/Info.plist"; do
    [ -e "$path" ] || sts_state_error "backup is incomplete: $(basename "$path") is missing" || return 1
  done

  [ "$(sts_manifest_value patch-version "$manifest")" = "$patch_version" ] \
    || sts_state_error 'installed patch version differs' || return 1
  [ "$(sts_manifest_value payload-manifest-sha256 "$manifest")" = "$payload_fingerprint" ] \
    || sts_state_error 'installed payload fingerprint differs' || return 1

  expected="$(sts_manifest_value original-jar-sha256 "$manifest")"
  actual="$(shasum -a 256 "$backup/desktop-1.0.jar" | awk '{print $1}')" || return 1
  [ -n "$expected" ] && [ "$actual" = "$expected" ] \
    || sts_state_error 'preserved original jar does not match its recorded hash' || return 1

  [ -f "$macos_dir/SlayTheSpire" ] && [ -x "$macos_dir/SlayTheSpire" ] \
    || sts_state_error 'installed launcher differs' || return 1
  launcher_archs="$(/usr/bin/lipo -archs "$macos_dir/SlayTheSpire" 2>/dev/null || true)"
  [ "$launcher_archs" = "$host_arch" ] \
    || sts_state_error "installed launcher is not native-only $host_arch" || return 1
  expected="$(sts_manifest_value installed-launcher-sha256 "$manifest")"
  actual="$(shasum -a 256 "$macos_dir/SlayTheSpire" | awk '{print $1}')" || return 1
  [ -n "$expected" ] && [ "$actual" = "$expected" ] \
    || sts_state_error 'installed launcher does not match its recorded hash' || return 1
  [ -f "$installed_info" ] || sts_state_error 'installed Info.plist is missing' || return 1
  expected="$(sts_manifest_value installed-info-plist-sha256 "$manifest")"
  actual="$(shasum -a 256 "$installed_info" | awk '{print $1}')" || return 1
  [ -n "$expected" ] && [ "$actual" = "$expected" ] \
    || sts_state_error 'installed Info.plist differs from the completed install' || return 1
  [ -d "$resources/jre" ] || sts_state_error 'installed JRE is missing' || return 1
  [ -x "$resources/jre/bin/java" ] || sts_state_error 'installed JRE launcher is not executable' || return 1

  while IFS= read -r line; do
    expected="${line%% *}"
    path="${line#* }"
    path="${path# }"
    [ "$path" != "$line" ] \
      || sts_state_error 'payload manifest contains a malformed entry' || return 1
    case "$path" in
      "payload/jre/$host_arch/"*)
        rel="${path#payload/jre/$host_arch/}"
        [ -f "$resources/jre/$rel" ] \
          || sts_state_error "installed JRE file is missing: $rel" || return 1
        expected="$(sts_checksum_value "$backup/installed-jre.sha256" "./$rel")" \
          || { sts_state_error "installed JRE state is incomplete: $rel"; return 1; }
        actual="$(shasum -a 256 "$resources/jre/$rel" | awk '{print $1}')" || return 1
        [ "$actual" = "$expected" ] \
          || sts_state_error "installed JRE file differs: $rel" || return 1
        expected_jre_files=$((expected_jre_files + 1))
        ;;
    esac
  done < "$payload_manifest"
  actual_jre_files="$(find "$resources/jre" -type f | wc -l | tr -d ' ')"
  recorded_jre_files="$(wc -l < "$backup/installed-jre.sha256" | tr -d ' ')"
  [ "$expected_jre_files" -gt 0 ] \
    && [ "$actual_jre_files" -eq "$expected_jre_files" ] \
    && [ "$recorded_jre_files" -eq "$expected_jre_files" ] \
    || sts_state_error 'installed JRE file set differs' || return 1

  [ -f "$jar" ] && unzip -tq "$jar" >/dev/null \
    || sts_state_error 'installed jar is missing or corrupt' || return 1
  expected="$(sts_manifest_value installed-jar-sha256 "$manifest")"
  actual="$(shasum -a 256 "$jar" | awk '{print $1}')" || return 1
  [ -n "$expected" ] && [ "$actual" = "$expected" ] \
    || sts_state_error 'installed jar differs' || return 1

  while IFS= read -r line; do
    expected="${line%% *}"
    entry="${line#* }"
    entry="${entry# }"
    [ "$entry" != "$line" ] \
      || sts_state_error 'installed overlay manifest contains a malformed entry' || return 1
    entry="${entry#./}"
    actual="$(unzip -p "$jar" "$entry" | shasum -a 256 | awk '{print $1}')" \
      || { sts_state_error "installed overlay entry is missing: $entry"; return 1; }
    [ "$actual" = "$expected" ] \
      || sts_state_error "installed overlay entry differs: $entry" || return 1
  done < "$backup/installed-overlay.sha256"

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if unzip -Z1 "$jar" | grep -Fqx "$entry"; then
      sts_state_error "entry scheduled for deletion is still installed: $entry"
      return 1
    fi
  done < "$jar_delete"

  # The game legitimately rewrites mutable sealed resources such as
  # info.displayconfig after launch. The installer verifies the complete app
  # signature immediately after signing; repeat-install state checks instead
  # validate every patch-managed artifact above so normal gameplay does not
  # become a false corruption report.
  "$resources/jre/bin/java" -version >/dev/null 2>&1 \
    || sts_state_error "installed $host_arch JRE failed its launch test" || return 1
  return 0
}
