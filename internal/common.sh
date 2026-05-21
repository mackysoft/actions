#!/usr/bin/env bash

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

require_non_empty() {
  local name="$1"
  local value="$2"

  if [ -z "$value" ]; then
    fail "${name} is required." 2
  fi
}

require_positive_integer() {
  local name="$1"
  local value="$2"

  require_non_empty "$name" "$value"

  if [[ ! "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ]; then
    fail "${name} must be a positive integer." 2
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
