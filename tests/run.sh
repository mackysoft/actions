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

extract_multiline_output() {
  local output_file="$1"
  local name="$2"

  awk -v name="$name" '
    found && $0 == delimiter { exit }
    found { print }
    index($0, name "<<") == 1 {
      delimiter = substr($0, length(name) + 3)
      found = 1
    }
  ' "$output_file"
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

run_nuget_common_tests() {
  local temp_root
  local stub_dir
  local counter_file
  # shellcheck source=internal/nuget-common.sh
  source "${repo_root}/internal/nuget-common.sh"

  expected_url="https://example.test/v3-flatcontainer/mackysoft.ucli/1.2.3-beta.1/mackysoft.ucli.1.2.3-beta.1.nupkg"
  actual_url="$(nuget_flat_container_url "https://example.test/v3-flatcontainer/" "MackySoft.Ucli" "1.2.3-beta.1")"
  if [ "$actual_url" != "$expected_url" ]; then
    fail "Unexpected NuGet flat container URL. Expected: ${expected_url}. Actual: ${actual_url}"
  fi

  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/nuget-common.XXXXXX")"
  stub_dir="${temp_root}/bin"
  counter_file="${temp_root}/curl-count.txt"
  mkdir -p "$stub_dir"
  cat > "${stub_dir}/curl" <<'SH'
#!/usr/bin/env bash
count=0
if [ -f "$FAKE_CURL_COUNTER_FILE" ]; then
  count="$(cat "$FAKE_CURL_COUNTER_FILE")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$FAKE_CURL_COUNTER_FILE"
if [ "$count" -lt 2 ]; then
  exit 22
fi
exit 0
SH
  chmod +x "${stub_dir}/curl"
  PATH="${stub_dir}:$PATH" \
    FAKE_CURL_COUNTER_FILE="$counter_file" \
    NUGET_CURL_RETRY_ATTEMPTS="2" \
    NUGET_CURL_RETRY_DELAY_SECONDS="0" \
    nuget_curl_head "https://example.test/package.nupkg"
  if [ "$(cat "$counter_file")" != "2" ]; then
    fail "nuget_curl_head did not retry after a curl failure."
  fi

  rm -rf "$temp_root"
}

create_fake_curl() {
  local stub_dir="$1"

  cat > "${stub_dir}/curl" <<'SH'
#!/usr/bin/env bash
url=""
for arg in "$@"; do
  case "$arg" in
    http://*|https://*)
      url="$arg"
      ;;
  esac
done

if [ -z "$url" ]; then
  exit 2
fi

if [ -n "${FAKE_CURL_STATE:-}" ] && grep -Fx "$url" "$FAKE_CURL_STATE" >/dev/null 2>&1; then
  exit 0
fi

exit 22
SH
  chmod +x "${stub_dir}/curl"
}

run_inspect_nuget_package_state_tests() {
  local temp_root
  local stub_dir
  local state_file
  local output_file
  local source_base_url
  local one_url
  local two_url
  local missing_output

  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/inspect-nuget.XXXXXX")"
  stub_dir="${temp_root}/bin"
  state_file="${temp_root}/available.txt"
  output_file="${temp_root}/outputs.txt"
  source_base_url="https://example.test/v3-flatcontainer"
  mkdir -p "$stub_dir"
  : > "$state_file"
  create_fake_curl "$stub_dir"

  # shellcheck source=internal/nuget-common.sh
  source "${repo_root}/internal/nuget-common.sh"
  one_url="$(nuget_flat_container_url "$source_base_url" "MackySoft.One" "1.2.3")"
  two_url="$(nuget_flat_container_url "$source_base_url" "MackySoft.Two" "1.2.3")"

  PATH="${stub_dir}:$PATH" \
    FAKE_CURL_STATE="$state_file" \
    GITHUB_OUTPUT="$output_file" \
    NUGET_CURL_RETRY_ATTEMPTS="1" \
    NUGET_CURL_RETRY_DELAY_SECONDS="0" \
    NUGET_PACKAGE_VERSION="1.2.3" \
    NUGET_PACKAGE_IDS=$'MackySoft.One\nMackySoft.Two' \
    NUGET_SOURCE_BASE_URL="$source_base_url" \
    NUGET_FAIL_ON_PARTIAL="true" \
    bash "${repo_root}/internal/inspect-nuget-package-state.sh" >/dev/null
  assert_output_value "$output_file" "all-packages-exist" "false"
  assert_output_value "$output_file" "publish-required" "true"
  missing_output="$(extract_multiline_output "$output_file" "missing-package-ids")"
  if [ "$missing_output" != $'MackySoft.One\nMackySoft.Two' ]; then
    fail "Unexpected missing package output for all-missing state."
  fi

  : > "$output_file"
  {
    printf '%s\n' "$one_url"
    printf '%s\n' "$two_url"
  } > "$state_file"
  PATH="${stub_dir}:$PATH" \
    FAKE_CURL_STATE="$state_file" \
    GITHUB_OUTPUT="$output_file" \
    NUGET_CURL_RETRY_ATTEMPTS="1" \
    NUGET_CURL_RETRY_DELAY_SECONDS="0" \
    NUGET_PACKAGE_VERSION="1.2.3" \
    NUGET_PACKAGE_IDS=$'MackySoft.One\nMackySoft.Two' \
    NUGET_SOURCE_BASE_URL="$source_base_url" \
    NUGET_FAIL_ON_PARTIAL="true" \
    bash "${repo_root}/internal/inspect-nuget-package-state.sh" >/dev/null
  assert_output_value "$output_file" "all-packages-exist" "true"
  assert_output_value "$output_file" "publish-required" "false"

  printf '%s\n' "$one_url" > "$state_file"
  if PATH="${stub_dir}:$PATH" \
    FAKE_CURL_STATE="$state_file" \
    NUGET_CURL_RETRY_ATTEMPTS="1" \
    NUGET_CURL_RETRY_DELAY_SECONDS="0" \
    NUGET_PACKAGE_VERSION="1.2.3" \
    NUGET_PACKAGE_IDS=$'MackySoft.One\nMackySoft.Two' \
    NUGET_SOURCE_BASE_URL="$source_base_url" \
    NUGET_FAIL_ON_PARTIAL="true" \
    bash "${repo_root}/internal/inspect-nuget-package-state.sh" >/dev/null 2>&1; then
    fail "inspect-nuget-package-state accepted a partial release state."
  fi

  rm -rf "$temp_root"
}

run_wait_nuget_packages_tests() {
  local temp_root
  local stub_dir
  local state_file
  local source_base_url
  local package_url

  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/wait-nuget.XXXXXX")"
  stub_dir="${temp_root}/bin"
  state_file="${temp_root}/available.txt"
  source_base_url="https://example.test/v3-flatcontainer"
  mkdir -p "$stub_dir"
  create_fake_curl "$stub_dir"

  # shellcheck source=internal/nuget-common.sh
  source "${repo_root}/internal/nuget-common.sh"
  package_url="$(nuget_flat_container_url "$source_base_url" "MackySoft.Tool" "1.2.3")"
  printf '%s\n' "$package_url" > "$state_file"

  PATH="${stub_dir}:$PATH" \
    FAKE_CURL_STATE="$state_file" \
    NUGET_CURL_RETRY_ATTEMPTS="1" \
    NUGET_CURL_RETRY_DELAY_SECONDS="0" \
    NUGET_PACKAGE_VERSION="1.2.3" \
    NUGET_PACKAGE_IDS="MackySoft.Tool" \
    NUGET_SOURCE_BASE_URL="$source_base_url" \
    NUGET_WAIT_ATTEMPTS="1" \
    NUGET_WAIT_INTERVAL_SECONDS="0" \
    bash "${repo_root}/internal/wait-nuget-packages.sh" >/dev/null

  : > "$state_file"
  if PATH="${stub_dir}:$PATH" \
    FAKE_CURL_STATE="$state_file" \
    NUGET_CURL_RETRY_ATTEMPTS="1" \
    NUGET_CURL_RETRY_DELAY_SECONDS="0" \
    NUGET_PACKAGE_VERSION="1.2.3" \
    NUGET_PACKAGE_IDS="MackySoft.Tool" \
    NUGET_SOURCE_BASE_URL="$source_base_url" \
    NUGET_WAIT_ATTEMPTS="2" \
    NUGET_WAIT_INTERVAL_SECONDS="0" \
    bash "${repo_root}/internal/wait-nuget-packages.sh" >/dev/null 2>&1; then
    fail "wait-nuget-packages succeeded for a missing package."
  fi

  rm -rf "$temp_root"
}

create_fake_gh() {
  local stub_dir="$1"

  cat > "${stub_dir}/gh" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "release" ] && [ "$2" = "view" ]; then
  exit "${FAKE_GH_RELEASE_VIEW_EXIT:-1}"
fi

printf '%s\n' "$*" >> "${FAKE_GH_LOG}"
exit 0
SH
  chmod +x "${stub_dir}/gh"
}

run_mirror_github_release_assets_tests() {
  local temp_root
  local stub_dir
  local asset_dir
  local log_file

  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/mirror-assets.XXXXXX")"
  stub_dir="${temp_root}/bin"
  asset_dir="${temp_root}/assets"
  log_file="${temp_root}/gh.log"
  mkdir -p "$stub_dir" "$asset_dir"
  create_fake_gh "$stub_dir"
  printf 'a\n' > "${asset_dir}/a.nupkg"
  printf 'b\n' > "${asset_dir}/b.nupkg"

  PATH="${stub_dir}:$PATH" \
    FAKE_GH_LOG="$log_file" \
    FAKE_GH_RELEASE_VIEW_EXIT="1" \
    MIRROR_GITHUB_TOKEN="token" \
    MIRROR_REPOSITORY="mackysoft/actions" \
    MIRROR_TAG_NAME="1.2.3" \
    MIRROR_ASSET_GLOB="${asset_dir}/*.nupkg" \
    MIRROR_TITLE="1.2.3" \
    MIRROR_NOTES="" \
    MIRROR_CLOBBER="true" \
    MIRROR_VERIFY_TAG="true" \
    MIRROR_UPDATE_EXISTING_RELEASE="true" \
    bash "${repo_root}/internal/mirror-github-release-assets.sh" >/dev/null
  if ! grep -F "release create 1.2.3" "$log_file" >/dev/null || ! grep -F -- "--verify-tag" "$log_file" >/dev/null; then
    fail "mirror-github-release-assets did not create a verified release."
  fi

  : > "$log_file"
  PATH="${stub_dir}:$PATH" \
    FAKE_GH_LOG="$log_file" \
    FAKE_GH_RELEASE_VIEW_EXIT="0" \
    MIRROR_GITHUB_TOKEN="token" \
    MIRROR_REPOSITORY="mackysoft/actions" \
    MIRROR_TAG_NAME="1.2.3" \
    MIRROR_ASSET_GLOB="${asset_dir}/*.nupkg" \
    MIRROR_TITLE="1.2.3" \
    MIRROR_NOTES="notes" \
    MIRROR_CLOBBER="true" \
    MIRROR_VERIFY_TAG="true" \
    MIRROR_UPDATE_EXISTING_RELEASE="true" \
    bash "${repo_root}/internal/mirror-github-release-assets.sh" >/dev/null
  if ! grep -F "release edit 1.2.3" "$log_file" >/dev/null || ! grep -F "release upload 1.2.3" "$log_file" >/dev/null || ! grep -F -- "--clobber" "$log_file" >/dev/null; then
    fail "mirror-github-release-assets did not update and upload to an existing release."
  fi

  rm -rf "$temp_root"
}

create_fake_dotnet() {
  local stub_dir="$1"

  cat > "${stub_dir}/dotnet" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "tool" ] && [ "$2" = "install" ]; then
  counter_file="${DOTNET_TOOL_COUNTER_FILE}"
  count=0
  if [ -f "$counter_file" ]; then
    count="$(cat "$counter_file")"
  fi
  count=$((count + 1))
  printf '%s\n' "$count" > "$counter_file"

  if [ "$count" -le "${DOTNET_TOOL_FAIL_COUNT:-0}" ]; then
    echo "simulated install failure" >&2
    exit 1
  fi

  tool_path=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tool-path)
        tool_path="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  if [ -z "$tool_path" ]; then
    echo "--tool-path was missing" >&2
    exit 1
  fi

  mkdir -p "$tool_path"
  cat > "${tool_path}/${DOTNET_TOOL_FAKE_COMMAND_NAME}" <<'TOOL'
#!/usr/bin/env bash
case "$1" in
  --version)
    printf '%s\n' "${DOTNET_TOOL_FAKE_VERSION}"
    ;;
  --help)
    printf '%s\n' "${DOTNET_TOOL_FAKE_HELP}"
    ;;
  *)
    exit 2
    ;;
esac
TOOL
  chmod +x "${tool_path}/${DOTNET_TOOL_FAKE_COMMAND_NAME}"
  exit 0
fi

echo "unexpected dotnet invocation: $*" >&2
exit 1
SH
  chmod +x "${stub_dir}/dotnet"
}

run_dotnet_tool_smoke_test_tests() {
  local temp_root
  local stub_dir
  local counter_file

  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/dotnet-tool-smoke.XXXXXX")"
  stub_dir="${temp_root}/bin"
  counter_file="${temp_root}/counter.txt"
  mkdir -p "$stub_dir"
  create_fake_dotnet "$stub_dir"

  PATH="${stub_dir}:$PATH" \
    DOTNET_TOOL_COUNTER_FILE="$counter_file" \
    DOTNET_TOOL_FAIL_COUNT="1" \
    DOTNET_TOOL_FAKE_COMMAND_NAME="sample-tool" \
    DOTNET_TOOL_FAKE_VERSION="1.2.3" \
    DOTNET_TOOL_FAKE_HELP="Commands:" \
    DOTNET_TOOL_PACKAGE_ID="MackySoft.SampleTool" \
    DOTNET_TOOL_PACKAGE_VERSION="1.2.3" \
    DOTNET_TOOL_COMMAND_NAME="sample-tool" \
    DOTNET_TOOL_SOURCE="${temp_root}/packages" \
    DOTNET_TOOL_RETRY_TIMEOUT_SECONDS="5" \
    DOTNET_TOOL_RETRY_INTERVAL_SECONDS="0" \
    DOTNET_TOOL_ASSERT_VERSION="true" \
    DOTNET_TOOL_VERSION_ARGUMENT="--version" \
    DOTNET_TOOL_ASSERT_HELP="true" \
    DOTNET_TOOL_HELP_ARGUMENT="--help" \
    DOTNET_TOOL_HELP_CONTAINS="Commands:" \
    bash "${repo_root}/internal/dotnet-tool-smoke-test.sh" >/dev/null

  if [ "$(cat "$counter_file")" != "2" ]; then
    fail "dotnet-tool-smoke-test did not retry the failed install."
  fi

  rm -rf "$temp_root"
}

cd "$repo_root"
run_bash_syntax_check
run_yaml_parse_check
run_resolve_release_version_tests
run_validate_release_source_tests
run_nuget_common_tests
run_inspect_nuget_package_state_tests
run_wait_nuget_packages_tests
run_mirror_github_release_assets_tests
run_dotnet_tool_smoke_test_tests

echo "Validation passed."
