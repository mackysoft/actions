#!/usr/bin/env bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

nuget_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

nuget_validate_version() {
  local version="$1"
  local semver_pattern

  semver_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*))?$'
  if [[ ! "$version" =~ $semver_pattern ]]; then
    fail "Package version must be SemVer without a leading v: ${version}" 2
  fi
}

nuget_flat_container_url() {
  local source_base_url="$1"
  local package_id="$2"
  local version="$3"
  local base_url
  local lower_package_id
  local lower_version

  base_url="${source_base_url%/}"
  lower_package_id="$(nuget_lower "$package_id")"
  lower_version="$(nuget_lower "$version")"
  printf '%s/%s/%s/%s.%s.nupkg' \
    "$base_url" \
    "$lower_package_id" \
    "$lower_version" \
    "$lower_package_id" \
    "$lower_version"
}

nuget_package_exists() {
  local source_base_url="$1"
  local package_id="$2"
  local version="$3"
  local url

  url="$(nuget_flat_container_url "$source_base_url" "$package_id" "$version")"
  nuget_curl_head "$url"
}

nuget_curl_head() {
  local url="$1"
  local attempt_count="${NUGET_CURL_RETRY_ATTEMPTS:-3}"
  local retry_delay_seconds="${NUGET_CURL_RETRY_DELAY_SECONDS:-2}"
  local attempt=1

  require_positive_integer "NUGET_CURL_RETRY_ATTEMPTS" "$attempt_count"
  require_non_negative_integer "NUGET_CURL_RETRY_DELAY_SECONDS" "$retry_delay_seconds"

  while true; do
    if curl --fail --silent --show-error --head "$url" >/dev/null; then
      return 0
    fi

    if [ "$attempt" -ge "$attempt_count" ]; then
      return 1
    fi

    sleep "$retry_delay_seconds"
    attempt=$((attempt + 1))
  done
}

nuget_read_package_ids() {
  local value="$1"
  local target_name="$2"

  read_lines_into_array "$value" "$target_name"
  eval 'local count="${#'"$target_name"'[@]}"'
  if [ "$count" -eq 0 ]; then
    fail "NUGET_PACKAGE_IDS must contain at least one package ID." 2
  fi
}

join_lines() {
  local value
  local output=""

  for value in "$@"; do
    if [ -z "$output" ]; then
      output="$value"
    else
      output="${output}
${value}"
    fi
  done

  printf '%s' "$output"
}
