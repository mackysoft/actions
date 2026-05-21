#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

tag_name="${VALIDATE_RELEASE_TAG_NAME:-}"
release_sha="${VALIDATE_RELEASE_SHA:-}"
default_branch="${VALIDATE_RELEASE_DEFAULT_BRANCH:-}"
remote="${VALIDATE_RELEASE_REMOTE:-origin}"
require_tag="${VALIDATE_RELEASE_REQUIRE_TAG:-true}"
require_head_match="${VALIDATE_RELEASE_REQUIRE_HEAD_MATCH:-false}"
require_ancestor="${VALIDATE_RELEASE_REQUIRE_ANCESTOR:-true}"

require_non_empty "VALIDATE_RELEASE_TAG_NAME" "$tag_name"
require_non_empty "VALIDATE_RELEASE_DEFAULT_BRANCH" "$default_branch"
require_non_empty "VALIDATE_RELEASE_REMOTE" "$remote"
require_bool "VALIDATE_RELEASE_REQUIRE_TAG" "$require_tag"
require_bool "VALIDATE_RELEASE_REQUIRE_HEAD_MATCH" "$require_head_match"
require_bool "VALIDATE_RELEASE_REQUIRE_ANCESTOR" "$require_ancestor"

if [ -n "$release_sha" ] && [[ ! "$release_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
  fail "VALIDATE_RELEASE_SHA must be a 40-character Git SHA: ${release_sha}" 2
fi

git fetch "$remote" "${default_branch}:refs/remotes/${remote}/${default_branch}"

resolved_sha=""
if [ "$require_tag" = true ]; then
  git fetch --force "$remote" "refs/tags/${tag_name}:refs/tags/${tag_name}"
  resolved_sha="$(git rev-list -n 1 "refs/tags/${tag_name}")"
else
  if [ -n "$release_sha" ]; then
    resolved_sha="$release_sha"
  else
    resolved_sha="$(git rev-parse HEAD)"
  fi
fi

if [[ ! "$resolved_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
  fail "Resolved release SHA is not a 40-character Git SHA: ${resolved_sha}" 1
fi

if [ -n "$release_sha" ] && [ "$resolved_sha" != "$release_sha" ]; then
  fail "Release source does not match expected SHA. Expected: ${release_sha}. Actual: ${resolved_sha}" 1
fi

if [ "$require_head_match" = true ]; then
  head_sha="$(git rev-parse HEAD)"
  if [ "$head_sha" != "$resolved_sha" ]; then
    fail "Checked out source does not match release source. Expected: ${resolved_sha}. Actual: ${head_sha}" 1
  fi
fi

if [ "$require_ancestor" = true ]; then
  if ! git merge-base --is-ancestor "$resolved_sha" "refs/remotes/${remote}/${default_branch}"; then
    fail "Release source must be reachable from ${remote}/${default_branch}. Actual sha: ${resolved_sha}" 1
  fi
fi

append_output "release-sha" "$resolved_sha"
echo "Validated release source: ${resolved_sha}"

