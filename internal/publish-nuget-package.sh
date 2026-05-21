#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

package_glob="${NUGET_PACKAGE_GLOB:-}"
nuget_api_key="${NUGET_API_KEY:-}"
nuget_source="${NUGET_SOURCE:-https://api.nuget.org/v3/index.json}"
skip_duplicate="${NUGET_SKIP_DUPLICATE:-true}"

require_non_empty "NUGET_PACKAGE_GLOB" "$package_glob"
require_non_empty "NUGET_API_KEY" "$nuget_api_key"
require_non_empty "NUGET_SOURCE" "$nuget_source"
require_bool "NUGET_SKIP_DUPLICATE" "$skip_duplicate"

package_paths=()
while IFS= read -r package_path; do
  package_paths+=("$package_path")
done < <(compgen -G "$package_glob" | sort)

if [ "${#package_paths[@]}" -eq 0 ]; then
  fail "No NuGet package artifacts matched: ${package_glob}" 1
fi

for package_path in "${package_paths[@]}"; do
  push_args=(
    dotnet nuget push "$package_path"
    --api-key "$nuget_api_key"
    --source "$nuget_source"
  )

  if [ "$skip_duplicate" = true ]; then
    push_args+=(--skip-duplicate)
  fi

  "${push_args[@]}"
done

