#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

fail() {
  echo "tests: $*" >&2
  exit 1
}

run_bash_syntax_check() {
  while IFS= read -r script_path; do
    bash -n "$script_path"
  done < <(find "${repo_root}/internal" "${repo_root}/tests" -type f -name '*.sh' | sort)
}

run_yaml_parse_check() {
  ruby --disable-gems <<'RUBY'
require "yaml"

paths = (Dir.glob("*/action.yaml") + Dir.glob(".github/workflows/*.yaml")).sort
abort "No YAML files found." if paths.empty?

paths.each do |path|
  next if File.directory?(path)
  YAML.safe_load(File.read(path), aliases: false)
rescue Psych::Exception => e
  warn "#{path}: #{e.message}"
  exit 1
end
RUBY
}

assert_output_value() {
  local output_file="$1"
  local name="$2"
  local expected="$3"

  if ! grep -Fx "${name}=${expected}" "$output_file" >/dev/null; then
    echo "Expected output ${name}=${expected}, actual:" >&2
    cat "$output_file" >&2
    exit 1
  fi
}

run_resolve_release_version_tests() {
  local output_file

  output_file="$(mktemp "${TMPDIR:-/tmp}/resolve-version.XXXXXX")"
  GITHUB_OUTPUT="$output_file" \
    RELEASE_EVENT_NAME="push" \
    RELEASE_REF_NAME="1.2.3" \
    RELEASE_DISPATCH_TAG="" \
    RELEASE_ALLOW_PRERELEASE="false" \
    bash "${repo_root}/internal/resolve-release-version.sh" >/dev/null
  assert_output_value "$output_file" "package-version" "1.2.3"
  assert_output_value "$output_file" "tag-name" "1.2.3"
  rm -f "$output_file"

  output_file="$(mktemp "${TMPDIR:-/tmp}/resolve-version.XXXXXX")"
  GITHUB_OUTPUT="$output_file" \
    RELEASE_EVENT_NAME="workflow_dispatch" \
    RELEASE_REF_NAME="" \
    RELEASE_DISPATCH_TAG="2.0.0" \
    RELEASE_ALLOW_PRERELEASE="false" \
    bash "${repo_root}/internal/resolve-release-version.sh" >/dev/null
  assert_output_value "$output_file" "package-version" "2.0.0"
  assert_output_value "$output_file" "tag-name" "2.0.0"
  rm -f "$output_file"

  if RELEASE_EVENT_NAME="push" \
    RELEASE_REF_NAME="v1.2.3" \
    RELEASE_DISPATCH_TAG="" \
    RELEASE_ALLOW_PRERELEASE="false" \
    bash "${repo_root}/internal/resolve-release-version.sh" >/dev/null 2>&1; then
    fail "resolve-release-version accepted a leading v tag."
  fi
}

run_validate_release_source_tests() {
  local temp_root
  local remote_dir
  local work_dir
  local release_sha
  local output_file

  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/validate-source.XXXXXX")"
  remote_dir="${temp_root}/remote.git"
  work_dir="${temp_root}/work"
  output_file="${temp_root}/outputs.txt"

  git init --bare "$remote_dir" >/dev/null
  git init -b master "$work_dir" >/dev/null
  (
    cd "$work_dir"
    git config user.name "Tests"
    git config user.email "tests@example.invalid"
    printf 'content\n' > file.txt
    git add file.txt
    git commit -m "test: seed" >/dev/null
    release_sha="$(git rev-parse HEAD)"
    git tag 1.2.3 "$release_sha"
    git remote add origin "$remote_dir"
    git push origin master >/dev/null
    git push origin refs/tags/1.2.3 >/dev/null

    GITHUB_OUTPUT="$output_file" \
      VALIDATE_RELEASE_TAG_NAME="1.2.3" \
      VALIDATE_RELEASE_SHA="$release_sha" \
      VALIDATE_RELEASE_DEFAULT_BRANCH="master" \
      VALIDATE_RELEASE_REMOTE="origin" \
      VALIDATE_RELEASE_REQUIRE_TAG="true" \
      VALIDATE_RELEASE_REQUIRE_HEAD_MATCH="true" \
      VALIDATE_RELEASE_REQUIRE_ANCESTOR="true" \
      bash "${repo_root}/internal/validate-release-source.sh" >/dev/null
    assert_output_value "$output_file" "release-sha" "$release_sha"

    if VALIDATE_RELEASE_TAG_NAME="1.2.3" \
      VALIDATE_RELEASE_SHA="0000000000000000000000000000000000000000" \
      VALIDATE_RELEASE_DEFAULT_BRANCH="master" \
      VALIDATE_RELEASE_REMOTE="origin" \
      VALIDATE_RELEASE_REQUIRE_TAG="true" \
      VALIDATE_RELEASE_REQUIRE_HEAD_MATCH="false" \
      VALIDATE_RELEASE_REQUIRE_ANCESTOR="true" \
      bash "${repo_root}/internal/validate-release-source.sh" >/dev/null 2>&1; then
      fail "validate-release-source accepted a mismatched release SHA."
    fi
  )

  rm -rf "$temp_root"
}

cd "$repo_root"
run_bash_syntax_check
run_yaml_parse_check
run_resolve_release_version_tests
run_validate_release_source_tests

echo "Validation passed."
