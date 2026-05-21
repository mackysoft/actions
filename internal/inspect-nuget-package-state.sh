#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/nuget-common.sh
source "${script_dir}/nuget-common.sh"

package_version="${NUGET_PACKAGE_VERSION:-}"
package_ids_value="${NUGET_PACKAGE_IDS:-}"
source_base_url="${NUGET_SOURCE_BASE_URL:-https://api.nuget.org/v3-flatcontainer}"
fail_on_partial="${NUGET_FAIL_ON_PARTIAL:-true}"

require_non_empty "NUGET_PACKAGE_VERSION" "$package_version"
require_non_empty "NUGET_PACKAGE_IDS" "$package_ids_value"
require_non_empty "NUGET_SOURCE_BASE_URL" "$source_base_url"
require_bool "NUGET_FAIL_ON_PARTIAL" "$fail_on_partial"
nuget_validate_version "$package_version"

package_ids=()
nuget_read_package_ids "$package_ids_value" package_ids

existing_package_ids=()
missing_package_ids=()
for package_id in "${package_ids[@]}"; do
  if nuget_package_exists "$source_base_url" "$package_id" "$package_version"; then
    existing_package_ids+=("$package_id")
  else
    missing_package_ids+=("$package_id")
  fi
done

all_packages_exist=false
publish_required=true
if [ "${#existing_package_ids[@]}" -eq "${#package_ids[@]}" ]; then
  all_packages_exist=true
  publish_required=false
elif [ "${#existing_package_ids[@]}" -ne 0 ]; then
  if [ "$fail_on_partial" = true ]; then
    echo "NuGet release state is inconsistent for ${package_version}." >&2
    echo "Existing packages:" >&2
    printf '%s\n' "${existing_package_ids[@]}" >&2
    echo "Missing packages:" >&2
    printf '%s\n' "${missing_package_ids[@]}" >&2
    exit 1
  fi
fi

append_output "all-packages-exist" "$all_packages_exist"
append_output "publish-required" "$publish_required"
if [ "${#existing_package_ids[@]}" -eq 0 ]; then
  append_multiline_output "existing-package-ids" ""
else
  append_multiline_output "existing-package-ids" "$(join_lines "${existing_package_ids[@]}")"
fi
if [ "${#missing_package_ids[@]}" -eq 0 ]; then
  append_multiline_output "missing-package-ids" ""
else
  append_multiline_output "missing-package-ids" "$(join_lines "${missing_package_ids[@]}")"
fi

if [ "$publish_required" = true ]; then
  echo "NuGet packages are not fully published for ${package_version}."
else
  echo "NuGet packages already exist for ${package_version}."
fi
