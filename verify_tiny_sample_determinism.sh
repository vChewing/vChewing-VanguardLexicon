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
    vanguardSQLLegacy)
      mkdir -p "$pass_dir/$target"
      cp -R "$repo_root/Build/Intermediate/vanguardSQL-Legacy" "$pass_dir/$target/Intermediate"
      cp -R "$repo_root/Build/Release/vanguardSQL-Legacy" "$pass_dir/$target/Release"
      ;;
    vanguardTriePlist)
      mkdir -p "$pass_dir/$target"
      cp -R "$repo_root/Build/Release/vanguard-trie-plist" "$pass_dir/$target/Release"
      ;;
    vanguardTrieSQL)
      mkdir -p "$pass_dir/$target"
      cp -R "$repo_root/Build/Intermediate/vanguard-trie-sql" "$pass_dir/$target/Intermediate"
      cp -R "$repo_root/Build/Release/vanguard-trie-sql" "$pass_dir/$target/Release"
      ;;
    vanguardTextMap)
      mkdir -p "$pass_dir/$target"
      cp -R "$repo_root/Build/Release/vanguard-textmap" "$pass_dir/$target/Release"
      ;;
  esac
}

normalize_plist() {
  swift - "$1" <<'SWIFT'
import Foundation

let path = CommandLine.arguments[1]
let data = try Data(contentsOf: URL(fileURLWithPath: path))
var format = PropertyListSerialization.PropertyListFormat.binary
let raw = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)

guard var root = raw as? [String: Any] else {
  fatalError("Unexpected plist root")
}

if let nodes = root["nodes"] as? [[String: Any]] {
  let normalizedNodes: [[String: Any]] = nodes.compactMap { node in
    let readingKey = (node["readingKey"] as? String) ?? ""
    if readingKey == "_BUILD_TIMESTAMP" {
      return nil
    }

    var mutable = node
    if let children = mutable["children"] as? [String: Int] {
      mutable["children"] = Dictionary(
        uniqueKeysWithValues: children
          .filter { $0.key != "_BUILD_TIMESTAMP" }
          .sorted { $0.key < $1.key }
      )
    } else if let children = mutable["children"] as? [String: Any] {
      mutable["children"] = Dictionary(
        uniqueKeysWithValues: children
          .filter { $0.key != "_BUILD_TIMESTAMP" }
          .sorted { $0.key < $1.key }
      )
    }
    if let entries = mutable["entries"] as? [String] {
      mutable["entries"] = entries.filter { !$0.hasPrefix("_BUILD_TIMESTAMP\t") }
    }
    return mutable
  }.sorted { lhs, rhs in
    (lhs["id"] as? Int ?? -1) < (rhs["id"] as? Int ?? -1)
  }
  root["nodes"] = normalizedNodes
}

let output = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
FileHandle.standardOutput.write(output)
SWIFT
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

for target in vanguardSQLLegacy vanguardTriePlist vanguardTrieSQL vanguardTextMap; do
  build_target "$pass1" "$target"
done

for target in vanguardSQLLegacy vanguardTriePlist vanguardTrieSQL vanguardTextMap; do
  build_target "$pass2" "$target"
done

compare_hashes \
  "legacySQL.sql" \
  "grep -v '_BUILD_TIMESTAMP' '$pass1/vanguardSQLLegacy/Intermediate/vanguardLegacy.sql'" \
  "grep -v '_BUILD_TIMESTAMP' '$pass2/vanguardSQLLegacy/Intermediate/vanguardLegacy.sql'"

compare_hashes \
  "legacySQL.sqlite.dump" \
  "sqlite3 '$pass1/vanguardSQLLegacy/Release/vChewingFactoryDatabase.sqlite' '.dump' | grep -v '_BUILD_TIMESTAMP'" \
  "sqlite3 '$pass2/vanguardSQLLegacy/Release/vChewingFactoryDatabase.sqlite' '.dump' | grep -v '_BUILD_TIMESTAMP'"

compare_hashes \
  "triePlist.typing" \
  "normalize_plist '$pass1/vanguardTriePlist/Release/VanguardFactoryDict4Typing.plist'" \
  "normalize_plist '$pass2/vanguardTriePlist/Release/VanguardFactoryDict4Typing.plist'"

compare_hashes \
  "triePlist.rev" \
  "normalize_plist '$pass1/vanguardTriePlist/Release/VanguardFactoryDict4RevLookup.plist'" \
  "normalize_plist '$pass2/vanguardTriePlist/Release/VanguardFactoryDict4RevLookup.plist'"

compare_hashes \
  "trieSQL.typing.sql" \
  "grep -v '_BUILD_TIMESTAMP' '$pass1/vanguardTrieSQL/Intermediate/VanguardFactoryDict4Typing.sql'" \
  "grep -v '_BUILD_TIMESTAMP' '$pass2/vanguardTrieSQL/Intermediate/VanguardFactoryDict4Typing.sql'"

compare_hashes \
  "trieSQL.rev.sql" \
  "grep -v '_BUILD_TIMESTAMP' '$pass1/vanguardTrieSQL/Intermediate/VanguardFactoryDict4RevLookup.sql'" \
  "grep -v '_BUILD_TIMESTAMP' '$pass2/vanguardTrieSQL/Intermediate/VanguardFactoryDict4RevLookup.sql'"

compare_hashes \
  "trieSQL.typing.sqlite.dump" \
  "sqlite3 '$pass1/vanguardTrieSQL/Release/VanguardFactoryDict4Typing.sqlite' '.dump' | grep -v '_BUILD_TIMESTAMP'" \
  "sqlite3 '$pass2/vanguardTrieSQL/Release/VanguardFactoryDict4Typing.sqlite' '.dump' | grep -v '_BUILD_TIMESTAMP'"

compare_hashes \
  "trieSQL.rev.sqlite.dump" \
  "sqlite3 '$pass1/vanguardTrieSQL/Release/VanguardFactoryDict4RevLookup.sqlite' '.dump' | grep -v '_BUILD_TIMESTAMP'" \
  "sqlite3 '$pass2/vanguardTrieSQL/Release/VanguardFactoryDict4RevLookup.sqlite' '.dump' | grep -v '_BUILD_TIMESTAMP'"

compare_hashes \
  "textMap.typing" \
  "grep -v '_BUILD_TIMESTAMP' '$pass1/vanguardTextMap/Release/VanguardFactoryDict4Typing.txtMap'" \
  "grep -v '_BUILD_TIMESTAMP' '$pass2/vanguardTextMap/Release/VanguardFactoryDict4Typing.txtMap'"

printf 'LOGDIR %s\n' "$workdir"