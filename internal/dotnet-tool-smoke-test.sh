#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

package_id="${DOTNET_TOOL_PACKAGE_ID:-}"
package_version="${DOTNET_TOOL_PACKAGE_VERSION:-}"
command_name="${DOTNET_TOOL_COMMAND_NAME:-}"
package_source="${DOTNET_TOOL_SOURCE:-https://api.nuget.org/v3/index.json}"
retry_timeout_seconds="${DOTNET_TOOL_RETRY_TIMEOUT_SECONDS:-600}"
retry_interval_seconds="${DOTNET_TOOL_RETRY_INTERVAL_SECONDS:-30}"
assert_version="${DOTNET_TOOL_ASSERT_VERSION:-true}"
version_argument="${DOTNET_TOOL_VERSION_ARGUMENT:---version}"
assert_help="${DOTNET_TOOL_ASSERT_HELP:-true}"
help_argument="${DOTNET_TOOL_HELP_ARGUMENT:---help}"
help_contains="${DOTNET_TOOL_HELP_CONTAINS:-}"

require_non_empty "DOTNET_TOOL_PACKAGE_ID" "$package_id"
require_non_empty "DOTNET_TOOL_PACKAGE_VERSION" "$package_version"
require_non_empty "DOTNET_TOOL_COMMAND_NAME" "$command_name"
require_non_empty "DOTNET_TOOL_SOURCE" "$package_source"
require_positive_integer "DOTNET_TOOL_RETRY_TIMEOUT_SECONDS" "$retry_timeout_seconds"
require_non_negative_integer "DOTNET_TOOL_RETRY_INTERVAL_SECONDS" "$retry_interval_seconds"
require_bool "DOTNET_TOOL_ASSERT_VERSION" "$assert_version"
require_bool "DOTNET_TOOL_ASSERT_HELP" "$assert_help"

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/dotnet-tool-smoke.XXXXXX")"
cleanup() {
  rm -rf "$temp_root"
}
trap cleanup EXIT

tool_dir="$temp_root/tools"
dotnet_cli_home="$temp_root/dotnet-home"
nuget_packages="$temp_root/nuget-packages"
nuget_http_cache="$temp_root/nuget-http-cache"
install_output="$temp_root/dotnet-tool-install.txt"
version_output="$temp_root/version.txt"
help_output="$temp_root/help.txt"

mkdir -p "$tool_dir" "$dotnet_cli_home" "$nuget_packages" "$nuget_http_cache"

tool_dir_for_dotnet="$(to_dotnet_path "$tool_dir")"
dotnet_cli_home_for_dotnet="$(to_dotnet_path "$dotnet_cli_home")"
nuget_packages_for_dotnet="$(to_dotnet_path "$nuget_packages")"
nuget_http_cache_for_dotnet="$(to_dotnet_path "$nuget_http_cache")"

install_tool() {
  DOTNET_ADD_GLOBAL_TOOLS_TO_PATH=false \
  DOTNET_CLI_HOME="$dotnet_cli_home_for_dotnet" \
  DOTNET_CLI_TELEMETRY_OPTOUT=1 \
  DOTNET_GENERATE_ASPNET_CERTIFICATE=false \
  DOTNET_NOLOGO=1 \
  DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
  NUGET_HTTP_CACHE_PATH="$nuget_http_cache_for_dotnet" \
  NUGET_PACKAGES="$nuget_packages_for_dotnet" \
  dotnet tool install "$package_id" \
    --version "$package_version" \
    --tool-path "$tool_dir_for_dotnet" \
    --add-source "$package_source" \
    --disable-parallel
}

reset_retry_state() {
  rm -rf "$tool_dir" "$nuget_http_cache"
  mkdir -p "$tool_dir" "$nuget_http_cache"
}

deadline=$((SECONDS + retry_timeout_seconds))
attempt=1
while true; do
  echo "Installing ${package_id} ${package_version} from ${package_source} (attempt ${attempt})."
  reset_retry_state

  if install_tool > "$install_output" 2>&1; then
    break
  fi

  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "----- dotnet tool install output begin -----" >&2
    cat "$install_output" >&2
    echo "----- dotnet tool install output end -----" >&2
    fail "Package could not be installed before retry timeout." 1
  fi

  remaining_seconds=$((deadline - SECONDS))
  if [ "$remaining_seconds" -le 0 ]; then
    echo "----- dotnet tool install output begin -----" >&2
    cat "$install_output" >&2
    echo "----- dotnet tool install output end -----" >&2
    fail "Package could not be installed before retry timeout." 1
  fi

  sleep_seconds="$retry_interval_seconds"
  if [ "$remaining_seconds" -lt "$sleep_seconds" ]; then
    sleep_seconds="$remaining_seconds"
  fi

  echo "Package is not installable yet; waiting ${sleep_seconds}s before retrying."
  sleep "$sleep_seconds"
  attempt=$((attempt + 1))
done

tool_command="$tool_dir/$command_name"
if [ -f "$tool_dir/${command_name}.exe" ]; then
  tool_command="$tool_dir/${command_name}.exe"
fi

if [ ! -f "$tool_command" ]; then
  fail "Installed tool command was not found: ${tool_command}" 1
fi

if [ "$assert_version" = true ]; then
  "$tool_command" "$version_argument" > "$version_output" 2>&1
  actual_version="$(tr -d '\r' < "$version_output")"
  if [ "$actual_version" != "$package_version" ]; then
    echo "Unexpected tool version. Expected: ${package_version}. Actual output:" >&2
    cat "$version_output" >&2
    exit 1
  fi
fi

if [ "$assert_help" = true ]; then
  "$tool_command" "$help_argument" > "$help_output" 2>&1
  if [ -n "$help_contains" ]; then
    if ! grep -Fq -- "$help_contains" "$help_output"; then
      echo "Help output did not contain expected text: ${help_contains}" >&2
      cat "$help_output" >&2
      exit 1
    fi
  elif [ ! -s "$help_output" ]; then
    fail "Help output was empty." 1
  fi
fi

echo "dotnet tool smoke test passed: ${package_id} ${package_version}"

