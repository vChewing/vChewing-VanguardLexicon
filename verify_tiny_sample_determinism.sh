#!/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root="$script_dir"
workdir=$(mktemp -d "$repo_root/Build/phase03-verify.XXXXXX")
pass1="$workdir/pass1"
pass2="$workdir/pass2"

mkdir -p "$pass1" "$pass2"

build_target() {
  local pass_dir="$1"
  local target="$2"

  rm -rf "$repo_root/Build/Release" "$repo_root/Build/Intermediate"
  printf 'BUILD %s -> %s\n' "$target" "$(basename -- "$pass_dir")"
  (
    cd "$repo_root"
    VANGUARD_CORPUS_BUILD_MODE=SMALL_TESTABLE_SAMPLE swift run VCDataBuilder "$target"
  ) >"$workdir/$(basename -- "$pass_dir")-$target.log" 2>&1

  case "$target" in
    vanguardTextMap)
      mkdir -p "$pass_dir/$target"
      cp -R "$repo_root/Build/Release/vanguard-textmap" "$pass_dir/$target/Release"
      ;;
  esac
}

hash_text() {
  local command="$1"
  eval "$command" | shasum -a 256 | awk '{print $1}'
}

compare_hashes() {
  local label="$1"
  local command1="$2"
  local command2="$3"
  local hash1 hash2

  hash1=$(hash_text "$command1")
  hash2=$(hash_text "$command2")
  if [[ "$hash1" == "$hash2" ]]; then
    printf 'OK   %s %s\n' "$label" "$hash1"
  else
    printf 'DIFF %s\n' "$label"
    printf '  pass1=%s\n' "$hash1"
    printf '  pass2=%s\n' "$hash2"
  fi
}

for target in vanguardTextMap; do
  build_target "$pass1" "$target"
done

for target in vanguardTextMap; do
  build_target "$pass2" "$target"
done

compare_hashes \
  "textMap.typing" \
  "grep -v '_BUILD_TIMESTAMP' '$pass1/vanguardTextMap/Release/VanguardFactoryDict4Typing.txtMap'" \
  "grep -v '_BUILD_TIMESTAMP' '$pass2/vanguardTextMap/Release/VanguardFactoryDict4Typing.txtMap'"

printf 'LOGDIR %s\n' "$workdir"
