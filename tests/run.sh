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

run_nuget_trusted_publish_tests() {
  local temp_root
  local stub_dir
  local package_dir
  local log_file

  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/publish-nuget.XXXXXX")"
  stub_dir="${temp_root}/bin"
  package_dir="${temp_root}/packages"
  log_file="${temp_root}/dotnet.log"
  mkdir -p "$stub_dir" "$package_dir"
  printf 'one\n' > "${package_dir}/B.nupkg"
  printf 'two\n' > "${package_dir}/A.nupkg"

  cat > "${stub_dir}/dotnet" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOTNET_PUSH_FAKE_LOG"
exit 0
SH
  chmod +x "${stub_dir}/dotnet"

  PATH="${stub_dir}:$PATH" \
    DOTNET_PUSH_FAKE_LOG="$log_file" \
    NUGET_API_KEY="fake-key" \
    NUGET_PACKAGE_GLOB="${package_dir}/*.nupkg" \
    NUGET_SOURCE="https://example.test/v3/index.json" \
    bash "${repo_root}/internal/nuget-trusted-publish.sh" >/dev/null

  if grep -F -- "--skip-duplicate" "$log_file" >/dev/null; then
    fail "nuget-trusted-publish passed duplicate policy to dotnet nuget push."
  fi

  if [ "$(wc -l < "$log_file" | tr -d ' ')" != "2" ]; then
    fail "nuget-trusted-publish did not push both package artifacts."
  fi

  first_push="$(sed -n '1p' "$log_file")"
  case "$first_push" in
    *"${package_dir}/A.nupkg"*)
      ;;
    *)
      fail "nuget-trusted-publish did not push package artifacts in sorted order."
      ;;
  esac

  rm -rf "$temp_root"
}

run_nuget_package_state_tests() {
  local temp_root
  local stub_dir
  local output_file
  local curl_log
  local flat_container_base_url
  local package_a_url
  local package_b_url

  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/nuget-state.XXXXXX")"
  stub_dir="${temp_root}/bin"
  output_file="${temp_root}/outputs.txt"
  curl_log="${temp_root}/curl.log"
  flat_container_base_url="https://example.test/v3-flatcontainer"
  package_a_url="${flat_container_base_url}/mackysoft.a/1.2.3/mackysoft.a.1.2.3.nupkg"
  package_b_url="${flat_container_base_url}/mackysoft.b/1.2.3/mackysoft.b.1.2.3.nupkg"

  mkdir -p "$stub_dir"
  cat > "${stub_dir}/curl" <<'SH'
#!/usr/bin/env bash
url=""
for argument in "$@"; do
  url="$argument"
done

printf '%s\n' "$url" >> "$FAKE_CURL_LOG"

case "${FAKE_NUGET_EXISTING:-}" in
  *"|${url}|"*)
    printf '200'
    ;;
  *)
    printf '404'
    ;;
esac
SH
  chmod +x "${stub_dir}/curl"

  : > "$output_file"
  PATH="${stub_dir}:$PATH" \
    FAKE_CURL_LOG="$curl_log" \
    FAKE_NUGET_EXISTING="" \
    GITHUB_OUTPUT="$output_file" \
    NUGET_PACKAGE_STATE_MODE="inspect" \
    NUGET_PACKAGE_STATE_PACKAGE_VERSION="1.2.3" \
    NUGET_PACKAGE_STATE_PACKAGE_IDS=$'MackySoft.A\nMackySoft.B' \
    NUGET_PACKAGE_STATE_FLAT_CONTAINER_BASE_URL="$flat_container_base_url" \
    bash "${repo_root}/internal/nuget-package-state.sh" >/dev/null
  assert_output_value "$output_file" "all-packages-exist" "false"
  assert_output_value "$output_file" "publish-required" "true"
  assert_output_value "$output_file" "existing-package-ids-json" "[]"
  assert_output_value "$output_file" "missing-package-ids-json" '["MackySoft.A","MackySoft.B"]'

  : > "$output_file"
  : > "$curl_log"
  PATH="${stub_dir}:$PATH" \
    FAKE_CURL_LOG="$curl_log" \
    FAKE_NUGET_EXISTING="|${package_a_url}|${package_b_url}|" \
    GITHUB_OUTPUT="$output_file" \
    NUGET_PACKAGE_STATE_MODE="inspect" \
    NUGET_PACKAGE_STATE_PACKAGE_VERSION="1.2.3" \
    NUGET_PACKAGE_STATE_PACKAGE_IDS=$'MackySoft.A\nMackySoft.B' \
    NUGET_PACKAGE_STATE_FLAT_CONTAINER_BASE_URL="$flat_container_base_url" \
    bash "${repo_root}/internal/nuget-package-state.sh" >/dev/null
  assert_output_value "$output_file" "all-packages-exist" "true"
  assert_output_value "$output_file" "publish-required" "false"
  assert_output_value "$output_file" "existing-package-ids-json" '["MackySoft.A","MackySoft.B"]'
  assert_output_value "$output_file" "missing-package-ids-json" "[]"

  if ! grep -Fx "$package_a_url" "$curl_log" >/dev/null; then
    fail "nuget-package-state did not normalize package IDs and versions for flat container URLs."
  fi

  : > "$output_file"
  if PATH="${stub_dir}:$PATH" \
    FAKE_CURL_LOG="$curl_log" \
    FAKE_NUGET_EXISTING="|${package_a_url}|" \
    GITHUB_OUTPUT="$output_file" \
    NUGET_PACKAGE_STATE_MODE="inspect" \
    NUGET_PACKAGE_STATE_PACKAGE_VERSION="1.2.3" \
    NUGET_PACKAGE_STATE_PACKAGE_IDS=$'MackySoft.A\nMackySoft.B' \
    NUGET_PACKAGE_STATE_FLAT_CONTAINER_BASE_URL="$flat_container_base_url" \
    bash "${repo_root}/internal/nuget-package-state.sh" >/dev/null 2>&1; then
    fail "nuget-package-state accepted partial publication state."
  fi

  : > "$output_file"
  PATH="${stub_dir}:$PATH" \
    FAKE_CURL_LOG="$curl_log" \
    FAKE_NUGET_EXISTING="|${package_a_url}|${package_b_url}|" \
    GITHUB_OUTPUT="$output_file" \
    NUGET_PACKAGE_STATE_MODE="wait" \
    NUGET_PACKAGE_STATE_PACKAGE_VERSION="1.2.3" \
    NUGET_PACKAGE_STATE_PACKAGE_IDS=$'MackySoft.A\nMackySoft.B' \
    NUGET_PACKAGE_STATE_FLAT_CONTAINER_BASE_URL="$flat_container_base_url" \
    NUGET_PACKAGE_STATE_MAX_ATTEMPTS="1" \
    NUGET_PACKAGE_STATE_INTERVAL_SECONDS="1" \
    bash "${repo_root}/internal/nuget-package-state.sh" >/dev/null
  assert_output_value "$output_file" "all-packages-exist" "true"
  assert_output_value "$output_file" "publish-required" "false"

  if PATH="${stub_dir}:$PATH" \
    FAKE_CURL_LOG="$curl_log" \
    FAKE_NUGET_EXISTING="" \
    NUGET_PACKAGE_STATE_MODE="wait" \
    NUGET_PACKAGE_STATE_PACKAGE_VERSION="1.2.3" \
    NUGET_PACKAGE_STATE_PACKAGE_IDS=$'MackySoft.A\nMackySoft.B' \
    NUGET_PACKAGE_STATE_FLAT_CONTAINER_BASE_URL="$flat_container_base_url" \
    NUGET_PACKAGE_STATE_MAX_ATTEMPTS="1" \
    NUGET_PACKAGE_STATE_INTERVAL_SECONDS="1" \
    bash "${repo_root}/internal/nuget-package-state.sh" >/dev/null 2>&1; then
    fail "nuget-package-state wait mode accepted missing packages after timeout."
  fi

  rm -rf "$temp_root"
}

cd "$repo_root"
run_bash_syntax_check
run_yaml_parse_check
run_nuget_trusted_publish_tests
run_nuget_package_state_tests

echo "Validation passed."
