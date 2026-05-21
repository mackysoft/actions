#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

event_name="${RELEASE_EVENT_NAME:-}"
ref_name="${RELEASE_REF_NAME:-}"
dispatch_tag="${RELEASE_DISPATCH_TAG:-}"
allow_prerelease="${RELEASE_ALLOW_PRERELEASE:-false}"

require_non_empty "RELEASE_EVENT_NAME" "$event_name"
require_bool "RELEASE_ALLOW_PRERELEASE" "$allow_prerelease"

if [ "$event_name" = "workflow_dispatch" ]; then
  release_tag="$dispatch_tag"
else
  release_tag="$ref_name"
fi

require_non_empty "release tag" "$release_tag"

case "$release_tag" in
  */*)
    fail "Release tag must not contain path separators: ${release_tag}" 2
    ;;
esac

stable_semver='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
prerelease_semver='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*))?$'

if [ "$allow_prerelease" = true ]; then
  if [[ ! "$release_tag" =~ $prerelease_semver ]]; then
    fail "Release tag must be SemVer without a leading v: ${release_tag}" 2
  fi
elif [[ ! "$release_tag" =~ $stable_semver ]]; then
  fail "Release tag must use <major>.<minor>.<patch> without a leading v: ${release_tag}" 2
fi

append_output "package-version" "$release_tag"
append_output "tag-name" "$release_tag"
echo "Resolved release version: ${release_tag}"

