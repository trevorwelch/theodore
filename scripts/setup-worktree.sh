#!/bin/bash

# Theodore: Create isolated git worktree for build/review loop
#
# Creates a new git branch and worktree under <repo>/.claude/worktrees/
# so the build/review loop never touches the main working tree.
# Outputs YAML (branch_name, worktree_path) for the orchestrator to parse.

set -euo pipefail

REPO_PATH=""
SPEC_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --repo requires a path argument" >&2
        exit 1
      fi
      REPO_PATH="$2"
      shift 2
      ;;
    --spec-name)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --spec-name requires a name argument" >&2
        exit 1
      fi
      SPEC_NAME="$2"
      shift 2
      ;;
    -h|--help)
      cat << 'EOF'
Theodore Worktree Setup

USAGE:
  setup-worktree.sh --repo <path> --spec-name <name>

Creates a git worktree and branch for an isolated Theodore session.
Branch: theodore/<spec-name>-<timestamp>
Worktree: <repo>/.claude/worktrees/theodore-<spec-name>-<timestamp>/

Outputs YAML with branch and worktree path on success.
EOF
      exit 0
      ;;
    *)
      echo "Error: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$REPO_PATH" ]]; then
  echo "Error: --repo is required" >&2
  exit 1
fi

if [[ -z "$SPEC_NAME" ]]; then
  echo "Error: --spec-name is required" >&2
  exit 1
fi

# Resolve to absolute path
REPO_PATH=$(cd "$REPO_PATH" && pwd)

# Verify it's a git repo
if ! git -C "$REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: $REPO_PATH is not a git repository" >&2
  exit 1
fi

# Sanitize spec name: lowercase, alphanumeric + hyphens only, no leading/trailing hyphens
SAFE_NAME=$(echo "$SPEC_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BRANCH_NAME="theodore/${SAFE_NAME}-${TIMESTAMP}"
WORKTREE_DIR="${REPO_PATH}/.claude/worktrees/theodore-${SAFE_NAME}-${TIMESTAMP}"

cd "$REPO_PATH"

# Ensure worktree parent directory exists and is gitignored
mkdir -p .claude/worktrees
if [[ -f .gitignore ]]; then
  if ! grep -qx '.claude/worktrees/' .gitignore 2>/dev/null; then
    echo '.claude/worktrees/' >> .gitignore
  fi
else
  echo '.claude/worktrees/' > .gitignore
fi

# Create branch from current HEAD
git branch "$BRANCH_NAME" HEAD

# Create worktree
git worktree add "$WORKTREE_DIR" "$BRANCH_NAME"

# Ensure .theodore dir exists in worktree for state file
mkdir -p "${WORKTREE_DIR}/.theodore"

cat <<EOF
branch_name: ${BRANCH_NAME}
worktree_path: ${WORKTREE_DIR}
EOF
