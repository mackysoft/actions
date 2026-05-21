#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

target="${DOTNET_TEST_TARGET:-}"
configuration="${DOTNET_TEST_CONFIGURATION:-Release}"
restore="${DOTNET_TEST_RESTORE:-false}"
no_build="${DOTNET_TEST_NO_BUILD:-false}"
test_arguments_value="${DOTNET_TEST_ARGUMENTS:-}"

require_non_empty "DOTNET_TEST_CONFIGURATION" "$configuration"
require_bool "DOTNET_TEST_RESTORE" "$restore"
require_bool "DOTNET_TEST_NO_BUILD" "$no_build"

test_arguments=()
read_lines_into_array "$test_arguments_value" test_arguments

command_args=(dotnet test)
if [ -n "$target" ]; then
  command_args+=("$target")
fi

command_args+=(--configuration "$configuration")
if [ "$restore" = false ]; then
  command_args+=(--no-restore)
fi

if [ "$no_build" = true ]; then
  command_args+=(--no-build)
fi

if [ "${#test_arguments[@]}" -gt 0 ]; then
  command_args+=("${test_arguments[@]}")
fi

"${command_args[@]}"

