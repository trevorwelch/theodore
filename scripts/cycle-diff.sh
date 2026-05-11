#!/bin/bash

# Theodore: show files or diff changed since a cycle-start tag.

set -euo pipefail

WORKTREE_PATH=""
CYCLE=""
MODE="diff"
PATHSPEC=()

usage() {
  cat >&2 <<'EOF'
Usage:
  cycle-diff.sh --worktree <path> --cycle <n> [--name-only] [-- <path>...]

Prints git diff output against tag theodore/cycle-<n>-start.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree)
      WORKTREE_PATH="${2:-}"
      shift 2
      ;;
    --cycle)
      CYCLE="${2:-}"
      shift 2
      ;;
    --name-only)
      MODE="name-only"
      shift
      ;;
    --)
      shift
      PATHSPEC=("$@")
      break
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

if [[ -z "$WORKTREE_PATH" || -z "$CYCLE" ]]; then
  echo "Error: --worktree and --cycle are required" >&2
  usage
  exit 1
fi

if ! [[ "$CYCLE" =~ ^[0-9]+$ ]]; then
  echo "Error: --cycle must be numeric" >&2
  exit 1
fi

TAG="theodore/cycle-${CYCLE}-start"

if ! git -C "$WORKTREE_PATH" rev-parse --verify --quiet "$TAG" >/dev/null; then
  echo "Error: missing cycle tag: $TAG" >&2
  exit 1
fi

if [[ ${#PATHSPEC[@]} -eq 0 ]]; then
  if [[ "$MODE" == "name-only" ]]; then
    git -C "$WORKTREE_PATH" diff --name-only "$TAG"
  else
    git -C "$WORKTREE_PATH" diff "$TAG"
  fi
else
  if [[ "$MODE" == "name-only" ]]; then
    git -C "$WORKTREE_PATH" diff --name-only "$TAG" -- "${PATHSPEC[@]}"
  else
    git -C "$WORKTREE_PATH" diff "$TAG" -- "${PATHSPEC[@]}"
  fi
fi
