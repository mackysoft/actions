#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

tag_name="${RELEASE_SOURCE_GUARD_TAG_NAME:-}"
expected_release_sha="${RELEASE_SOURCE_GUARD_EXPECTED_RELEASE_SHA:-}"
default_branch="${RELEASE_SOURCE_GUARD_DEFAULT_BRANCH:-}"
remote="${RELEASE_SOURCE_GUARD_REMOTE:-origin}"
tag_prefix="${RELEASE_SOURCE_GUARD_TAG_PREFIX:-}"

require_non_empty "RELEASE_SOURCE_GUARD_TAG_NAME" "$tag_name"
require_non_empty "RELEASE_SOURCE_GUARD_DEFAULT_BRANCH" "$default_branch"
require_non_empty "RELEASE_SOURCE_GUARD_REMOTE" "$remote"

if [ -n "$expected_release_sha" ] && [[ ! "$expected_release_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
  fail "RELEASE_SOURCE_GUARD_EXPECTED_RELEASE_SHA must be a 40-character Git SHA: ${expected_release_sha}" 2
fi

if [ -n "$tag_prefix" ]; then
  tag_prefix_length="${#tag_prefix}"
  if [ "${tag_name:0:$tag_prefix_length}" != "$tag_prefix" ]; then
    fail "Release tag must start with tag prefix '${tag_prefix}': ${tag_name}" 2
  fi

  package_version="${tag_name:$tag_prefix_length}"
else
  package_version="$tag_name"
fi

semver_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
if [[ ! "$package_version" =~ $semver_pattern ]]; then
  fail "Release tag does not resolve to a SemVer package version: ${tag_name}" 2
fi

git fetch "$remote" "${default_branch}:refs/remotes/${remote}/${default_branch}"
git fetch --force "$remote" "refs/tags/${tag_name}:refs/tags/${tag_name}"

release_sha="$(git rev-list -n 1 "refs/tags/${tag_name}")"
if [[ ! "$release_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
  fail "Resolved release SHA is not a 40-character Git SHA: ${release_sha}" 1
fi

if [ -n "$expected_release_sha" ] && [ "$release_sha" != "$expected_release_sha" ]; then
  fail "Release source does not match expected SHA. Expected: ${expected_release_sha}. Actual: ${release_sha}" 1
fi

head_sha="$(git rev-parse HEAD)"
if [ "$head_sha" != "$release_sha" ]; then
  fail "Checked out source does not match release source. Expected: ${release_sha}. Actual: ${head_sha}" 1
fi

if ! git merge-base --is-ancestor "$release_sha" "refs/remotes/${remote}/${default_branch}"; then
  fail "Release source must be reachable from ${remote}/${default_branch}. Actual SHA: ${release_sha}" 1
fi

append_output "tag-name" "$tag_name"
append_output "package-version" "$package_version"
append_output "release-sha" "$release_sha"
echo "Validated release source: ${tag_name} (${release_sha})"
