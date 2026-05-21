#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

solution="${DOTNET_FORMAT_SOLUTION:-}"
mode="${DOTNET_FORMAT_MODE:-verify}"
restore="${DOTNET_FORMAT_RESTORE:-false}"
diagnostics_value="${DOTNET_FORMAT_DIAGNOSTICS:-}"
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

diagnostics=()
include_paths=()
read_lines_into_array "$diagnostics_value" diagnostics
read_lines_into_array "$include_value" include_paths

if [ "${#diagnostics[@]}" -eq 0 ]; then
  fail "DOTNET_FORMAT_DIAGNOSTICS must contain at least one diagnostic ID." 2
fi

if [ "$restore" = true ]; then
  dotnet restore "$solution"
fi

format_base_args=()
if [ "${#include_paths[@]}" -gt 0 ]; then
  format_base_args+=(--include "${include_paths[@]}")
fi

case "$mode" in
  format)
    dotnet format style "$solution" "${format_base_args[@]}" --diagnostics "${diagnostics[@]}" --verbosity minimal --no-restore
    dotnet format whitespace "$solution" "${format_base_args[@]}" --verbosity minimal --no-restore
    ;;
  verify)
    dotnet format whitespace "$solution" "${format_base_args[@]}" --verify-no-changes --verbosity minimal --no-restore
    dotnet format style "$solution" "${format_base_args[@]}" --diagnostics "${diagnostics[@]}" --verify-no-changes --verbosity minimal --no-restore
    ;;
esac

