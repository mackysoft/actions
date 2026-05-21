#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

cache_key_prefix="${CACHE_KEY_PREFIX:-nuget}"
cache_key_files="${CACHE_KEY_FILES:-}"
runner_os="${RUNNER_OS:-$(uname -s)}"

require_non_empty "CACHE_KEY_PREFIX" "$cache_key_prefix"

patterns=()
read_lines_into_array "$cache_key_files" patterns

matched_files_file="$(mktemp "${TMPDIR:-/tmp}/cache-files.XXXXXX")"
trap 'rm -f "$matched_files_file"' EXIT

if [ "${#patterns[@]}" -eq 0 ]; then
  echo "No cache key file patterns were provided."
else
  for pattern in "${patterns[@]}"; do
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git ls-files -- "$pattern" >> "$matched_files_file"
    elif [ -f "$pattern" ]; then
      printf '%s\n' "$pattern" >> "$matched_files_file"
    fi
  done
fi

if [ -s "$matched_files_file" ]; then
  sort -u "$matched_files_file" -o "$matched_files_file"
  hash_value="$(
    while IFS= read -r file; do
      if [ -f "$file" ]; then
        shasum -a 256 "$file"
      fi
    done < "$matched_files_file" | shasum -a 256 | awk '{ print $1 }'
  )"
else
  hash_value="no-files"
fi

cache_key="${runner_os}-${cache_key_prefix}-${hash_value}"
append_output "cache-key" "$cache_key"
echo "NuGet cache key: ${cache_key}"

