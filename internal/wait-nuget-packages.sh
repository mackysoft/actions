#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/nuget-common.sh
source "${script_dir}/nuget-common.sh"

package_version="${NUGET_PACKAGE_VERSION:-}"
package_ids_value="${NUGET_PACKAGE_IDS:-}"
source_base_url="${NUGET_SOURCE_BASE_URL:-https://api.nuget.org/v3-flatcontainer}"
attempt_count="${NUGET_WAIT_ATTEMPTS:-30}"
interval_seconds="${NUGET_WAIT_INTERVAL_SECONDS:-10}"

require_non_empty "NUGET_PACKAGE_VERSION" "$package_version"
require_non_empty "NUGET_PACKAGE_IDS" "$package_ids_value"
require_non_empty "NUGET_SOURCE_BASE_URL" "$source_base_url"
require_positive_integer "NUGET_WAIT_ATTEMPTS" "$attempt_count"
require_non_negative_integer "NUGET_WAIT_INTERVAL_SECONDS" "$interval_seconds"
nuget_validate_version "$package_version"

package_ids=()
nuget_read_package_ids "$package_ids_value" package_ids

missing_package_ids=("${package_ids[@]}")
attempt=1
while [ "$attempt" -le "$attempt_count" ]; do
  next_missing_package_ids=()
  for package_id in "${missing_package_ids[@]}"; do
    if nuget_package_exists "$source_base_url" "$package_id" "$package_version"; then
      echo "NuGet package is available: ${package_id} ${package_version}"
    else
      next_missing_package_ids+=("$package_id")
    fi
  done

  if [ "${#next_missing_package_ids[@]}" -eq 0 ]; then
    exit 0
  fi

  missing_package_ids=("${next_missing_package_ids[@]}")
  if [ "$attempt" -lt "$attempt_count" ]; then
    echo "Waiting for NuGet packages to become available (${attempt}/${attempt_count}): ${missing_package_ids[*]}"
    sleep "$interval_seconds"
  fi

  attempt=$((attempt + 1))
done

echo "NuGet packages did not become available for ${package_version}:" >&2
printf '%s\n' "${missing_package_ids[@]}" >&2
exit 1
