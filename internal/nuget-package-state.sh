#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

mode="${NUGET_PACKAGE_STATE_MODE:-inspect}"
package_version="${NUGET_PACKAGE_STATE_PACKAGE_VERSION:-}"
package_ids_text="${NUGET_PACKAGE_STATE_PACKAGE_IDS:-}"
flat_container_base_url="${NUGET_PACKAGE_STATE_FLAT_CONTAINER_BASE_URL:-https://api.nuget.org/v3-flatcontainer}"
max_attempts="${NUGET_PACKAGE_STATE_MAX_ATTEMPTS:-30}"
interval_seconds="${NUGET_PACKAGE_STATE_INTERVAL_SECONDS:-10}"

require_non_empty "NUGET_PACKAGE_STATE_MODE" "$mode"
require_non_empty "NUGET_PACKAGE_STATE_PACKAGE_VERSION" "$package_version"
require_non_empty "NUGET_PACKAGE_STATE_PACKAGE_IDS" "$package_ids_text"
require_non_empty "NUGET_PACKAGE_STATE_FLAT_CONTAINER_BASE_URL" "$flat_container_base_url"
require_positive_integer "NUGET_PACKAGE_STATE_MAX_ATTEMPTS" "$max_attempts"
require_positive_integer "NUGET_PACKAGE_STATE_INTERVAL_SECONDS" "$interval_seconds"

case "$mode" in
  inspect | wait)
    ;;
  *)
    fail "NUGET_PACKAGE_STATE_MODE must be inspect or wait." 2
    ;;
esac

if [[ ! "$package_version" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]]; then
  fail "NUGET_PACKAGE_STATE_PACKAGE_VERSION contains unsupported characters: ${package_version}" 2
fi

flat_container_base_url="${flat_container_base_url%/}"
package_ids=()

while IFS= read -r package_id || [ -n "$package_id" ]; do
  package_id="$(printf '%s' "$package_id" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ -z "$package_id" ]; then
    continue
  fi

  if [[ ! "$package_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    fail "Package ID contains unsupported characters: ${package_id}" 2
  fi

  package_ids+=("$package_id")
done <<< "$package_ids_text"

if [ "${#package_ids[@]}" -eq 0 ]; then
  fail "NUGET_PACKAGE_STATE_PACKAGE_IDS must contain at least one package ID." 2
fi

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

json_array() {
  local item
  local delimiter=""

  printf '['
  for item in "$@"; do
    printf '%s"%s"' "$delimiter" "$item"
    delimiter=","
  done
  printf ']'
}

package_url() {
  local package_id="$1"
  local package_version="$2"
  local normalized_id
  local normalized_version

  normalized_id="$(lowercase "$package_id")"
  normalized_version="$(lowercase "$package_version")"
  printf '%s/%s/%s/%s.%s.nupkg' \
    "$flat_container_base_url" \
    "$normalized_id" \
    "$normalized_version" \
    "$normalized_id" \
    "$normalized_version"
}

package_exists() {
  local url="$1"
  local http_status
  local curl_status

  set +e
  http_status="$(curl --silent --show-error --location --head --output /dev/null --write-out '%{http_code}' "$url")"
  curl_status=$?
  set -e

  if [ "$curl_status" -ne 0 ]; then
    fail "curl failed while checking package URL: ${url}" 1
  fi

  case "$http_status" in
    200)
      return 0
      ;;
    404)
      return 1
      ;;
    *)
      fail "Unexpected HTTP status ${http_status} while checking package URL: ${url}" 1
      ;;
  esac
}

inspect_packages() {
  existing_package_ids=()
  missing_package_ids=()

  local package_id
  local url
  for package_id in "${package_ids[@]}"; do
    url="$(package_url "$package_id" "$package_version")"
    if package_exists "$url"; then
      existing_package_ids+=("$package_id")
    else
      missing_package_ids+=("$package_id")
    fi
  done
}

append_state_outputs() {
  local all_packages_exist="$1"
  local publish_required="$2"
  local existing_json="[]"
  local missing_json="[]"

  if [ "${#existing_package_ids[@]}" -gt 0 ]; then
    existing_json="$(json_array "${existing_package_ids[@]}")"
  fi

  if [ "${#missing_package_ids[@]}" -gt 0 ]; then
    missing_json="$(json_array "${missing_package_ids[@]}")"
  fi

  append_output "all-packages-exist" "$all_packages_exist"
  append_output "publish-required" "$publish_required"
  append_output "existing-package-ids-json" "$existing_json"
  append_output "missing-package-ids-json" "$missing_json"
}

run_inspect() {
  inspect_packages

  if [ "${#missing_package_ids[@]}" -eq 0 ]; then
    append_state_outputs "true" "false"
    return 0
  fi

  if [ "${#existing_package_ids[@]}" -eq 0 ]; then
    append_state_outputs "false" "true"
    return 0
  fi

  fail "Partial NuGet package publication state detected. Existing: $(json_array "${existing_package_ids[@]}"). Missing: $(json_array "${missing_package_ids[@]}")." 1
}

run_wait() {
  local attempt=1

  while [ "$attempt" -le "$max_attempts" ]; do
    inspect_packages
    if [ "${#missing_package_ids[@]}" -eq 0 ]; then
      append_state_outputs "true" "false"
      return 0
    fi

    if [ "$attempt" -lt "$max_attempts" ]; then
      sleep "$interval_seconds"
    fi

    attempt=$((attempt + 1))
  done

  fail "Timed out waiting for NuGet packages. Missing: $(json_array "${missing_package_ids[@]}")." 1
}

if [ "$mode" = "inspect" ]; then
  run_inspect
else
  run_wait
fi
