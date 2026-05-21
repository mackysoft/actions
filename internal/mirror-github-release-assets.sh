#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/common.sh
source "${script_dir}/common.sh"

github_token="${MIRROR_GITHUB_TOKEN:-}"
repository="${MIRROR_REPOSITORY:-}"
tag_name="${MIRROR_TAG_NAME:-}"
asset_glob="${MIRROR_ASSET_GLOB:-}"
release_title="${MIRROR_TITLE:-}"
release_notes="${MIRROR_NOTES:-}"
clobber="${MIRROR_CLOBBER:-true}"
verify_tag="${MIRROR_VERIFY_TAG:-true}"
update_existing_release="${MIRROR_UPDATE_EXISTING_RELEASE:-true}"

require_non_empty "MIRROR_GITHUB_TOKEN" "$github_token"
require_non_empty "MIRROR_REPOSITORY" "$repository"
require_non_empty "MIRROR_TAG_NAME" "$tag_name"
require_non_empty "MIRROR_ASSET_GLOB" "$asset_glob"
require_non_empty "MIRROR_TITLE" "$release_title"
require_bool "MIRROR_CLOBBER" "$clobber"
require_bool "MIRROR_VERIFY_TAG" "$verify_tag"
require_bool "MIRROR_UPDATE_EXISTING_RELEASE" "$update_existing_release"

export GH_TOKEN="$github_token"

asset_paths=()
while IFS= read -r asset_path; do
  asset_paths+=("$asset_path")
done < <(compgen -G "$asset_glob" | sort)

if [ "${#asset_paths[@]}" -eq 0 ]; then
  fail "No release assets matched: ${asset_glob}" 1
fi

if gh release view "$tag_name" --repo "$repository" >/dev/null 2>&1; then
  if [ "$update_existing_release" = true ]; then
    gh release edit "$tag_name" \
      --repo "$repository" \
      --title "$release_title" \
      --notes "$release_notes"
  fi

  upload_command=(gh release upload "$tag_name")
  upload_command+=("${asset_paths[@]}")
  upload_command+=(--repo "$repository")
  if [ "$clobber" = true ]; then
    upload_command+=(--clobber)
  fi
  "${upload_command[@]}"
else
  create_command=(gh release create "$tag_name")
  create_command+=("${asset_paths[@]}")
  create_command+=(--repo "$repository" --title "$release_title" --notes "$release_notes")
  if [ "$verify_tag" = true ]; then
    create_command+=(--verify-tag)
  fi
  "${create_command[@]}"
fi

