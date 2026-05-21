#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

solution="${DOTNET_FORMAT_SOLUTION:-}"
mode="${DOTNET_FORMAT_MODE:-verify}"
restore="${DOTNET_FORMAT_RESTORE:-false}"
include_value="${DOTNET_FORMAT_INCLUDE:-}"

require_non_empty "DOTNET_FORMAT_SOLUTION" "$solution"
require_bool "DOTNET_FORMAT_RESTORE" "$restore"

case "$mode" in
  format|verify)
    ;;
  *)
    fail "DOTNET_FORMAT_MODE must be format or verify: ${mode}" 2
    ;;
esac

include_paths=()
read_lines_into_array "$include_value" include_paths

if [ "$restore" = true ]; then
  dotnet restore "$solution"
fi

run_dotnet_format() {
  local command="$1"
  shift

  if [ "${#include_paths[@]}" -gt 0 ]; then
    dotnet format "$command" "$solution" --include "${include_paths[@]}" "$@"
  else
    dotnet format "$command" "$solution" "$@"
  fi
}

case "$mode" in
  format)
    run_dotnet_format style --verbosity minimal --no-restore
    run_dotnet_format whitespace --verbosity minimal --no-restore
    ;;
  verify)
    run_dotnet_format whitespace --verify-no-changes --verbosity minimal --no-restore
    run_dotnet_format style --verify-no-changes --verbosity minimal --no-restore
    ;;
esac
