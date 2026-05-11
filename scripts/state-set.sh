#!/bin/bash

# Theodore: update simple YAML frontmatter keys in .theodore/state.md.
#
# Usage:
#   state-set.sh --state /abs/worktree/.theodore/state.md --phase verify --cycle 2
#   state-set.sh --state /abs/worktree/.theodore/state.md --key pr_url --value https://...

set -euo pipefail

STATE_PATH=""
declare -a UPDATES=()

usage() {
  cat >&2 <<'EOF'
Usage:
  state-set.sh --state <state.md> [--phase <phase>] [--cycle <n>] [--active <true|false>]
  state-set.sh --state <state.md> --key <frontmatter_key> --value <value>

Updates simple top-level YAML frontmatter keys. Prints the updated key list on stdout.
EOF
}

add_update() {
  local key="$1"
  local value="$2"
  if [[ -z "$key" ]]; then
    echo "Error: empty key" >&2
    exit 1
  fi
  UPDATES+=("${key}=${value}")
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state)
      STATE_PATH="${2:-}"
      shift 2
      ;;
    --phase|--cycle|--active|--pr-number|--pr-url|--test-command|--branch-name|--worktree-path|--repo-path)
      key="${1#--}"
      key="${key//-/_}"
      add_update "$key" "${2:-}"
      shift 2
      ;;
    --key)
      key="${2:-}"
      shift 2
      if [[ "${1:-}" != "--value" ]]; then
        echo "Error: --key must be followed by --value" >&2
        usage
        exit 1
      fi
      add_update "$key" "${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$STATE_PATH" ]]; then
  echo "Error: --state is required" >&2
  usage
  exit 1
fi

if [[ ! -f "$STATE_PATH" ]]; then
  echo "Error: state file not found: $STATE_PATH" >&2
  exit 1
fi

if [[ ${#UPDATES[@]} -eq 0 ]]; then
  echo "Error: at least one update is required" >&2
  usage
  exit 1
fi

if ! sed -n '1p' "$STATE_PATH" | grep -qx -- '---'; then
  echo "Error: state file must start with YAML frontmatter" >&2
  exit 1
fi

tmp_file="$(mktemp "${TMPDIR:-/tmp}/theodore-state.XXXXXX")"
updates_file="$(mktemp "${TMPDIR:-/tmp}/theodore-updates.XXXXXX")"
trap 'rm -f "$tmp_file" "$updates_file"' EXIT

for update in "${UPDATES[@]}"; do
  printf '%s\t%s\n' "${update%%=*}" "${update#*=}" >> "$updates_file"
done

awk -v updates_file="$updates_file" '
BEGIN {
  while ((getline row < updates_file) > 0) {
    tab = index(row, "\t")
    key = substr(row, 1, tab - 1)
    value = substr(row, tab + 1)
    wanted[key] = value
    seen[key] = 0
  }
  close(updates_file)
  in_frontmatter = 0
  delimiter_count = 0
}
NR == 1 && $0 == "---" {
  in_frontmatter = 1
  delimiter_count = 1
  print
  next
}
in_frontmatter && $0 == "---" {
  for (key in wanted) {
    if (!seen[key]) {
      print key ": " wanted[key]
    }
  }
  in_frontmatter = 0
  delimiter_count = 2
  print
  next
}
in_frontmatter {
  line = $0
  for (key in wanted) {
    prefix = key ":"
    if (index(line, prefix) == 1) {
      print key ": " wanted[key]
      seen[key] = 1
      next
    }
  }
  print
  next
}
{ print }
END {
  if (delimiter_count < 2) {
    exit 2
  }
}
' "$STATE_PATH" > "$tmp_file" || {
  echo "Error: failed to update state frontmatter" >&2
  exit 1
}

mv "$tmp_file" "$STATE_PATH"
trap - EXIT

for update in "${UPDATES[@]}"; do
  printf '%s\n' "${update%%=*}"
done
