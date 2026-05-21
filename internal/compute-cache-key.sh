#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

cache_key_prefix="${CACHE_KEY_PREFIX:-nuget}"
cache_key_files="${CACHE_KEY_FILES:-}"
runner_os="${RUNNER_OS:-$(uname -s)}"

require_non_empty "CACHE_KEY_PREFIX" "$cache_key_prefix"

hash_file() {
  local file="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{ print $1 }'
    return
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{ print $1 }'
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{ print $NF }'
    return
  fi

  fail "No SHA-256 hashing command is available. Expected shasum, sha256sum, or openssl." 1
}

hash_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{ print $1 }'
    return
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{ print $1 }'
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | awk '{ print $NF }'
    return
  fi

  fail "No SHA-256 hashing command is available. Expected shasum, sha256sum, or openssl." 1
}

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
        printf '%s  %s\n' "$(hash_file "$file")" "$file"
      fi
    done < "$matched_files_file" | hash_stream
  )"
else
  hash_value="no-files"
fi

cache_key="${runner_os}-${cache_key_prefix}-${hash_value}"
append_output "cache-key" "$cache_key"
echo "NuGet cache key: ${cache_key}"
