#!/usr/bin/env bash

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

require_bool() {
  local name="$1"
  local value="$2"

  case "$value" in
    true|false)
      return 0
      ;;
    *)
      fail "${name} must be either true or false: ${value}" 2
      ;;
  esac
}

require_non_empty() {
  local name="$1"
  local value="$2"

  if [ -z "$value" ]; then
    fail "${name} is required." 2
  fi
}

append_output() {
  local name="$1"
  local value="$2"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$name" "$value" >> "$GITHUB_OUTPUT"
  else
    printf '%s=%s\n' "$name" "$value"
  fi
}

read_lines_into_array() {
  local value="$1"
  local target_name="$2"
  local line

  eval "$target_name=()"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*)
        continue
        ;;
      *)
        eval "$target_name+=(\"\$line\")"
        ;;
    esac
  done <<EOF
$value
EOF
}

