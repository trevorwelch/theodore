#!/bin/bash

# Theodore Stop Hook
#
# Fires when Claude Code exits. Checks for active Theodore sessions in
# worktrees and warns the user, but never blocks exit. Sessions survive
# across restarts and can be resumed with /theodore or cancelled with
# /cancel-theodore.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Search for active Theodore state files in worktrees
ACTIVE_STATES=()
for state_file in "$PROJECT_DIR"/.claude/worktrees/theodore-*/.theodore/state.md; do
  [[ -f "$state_file" ]] || continue
  if grep -q 'active: true' "$state_file" 2>/dev/null; then
    ACTIVE_STATES+=("$state_file")
  fi
done

if [[ ${#ACTIVE_STATES[@]} -eq 0 ]]; then
  # No active sessions, allow exit silently
  exit 0
fi

# Warn about active sessions but don't block exit
for state_file in "${ACTIVE_STATES[@]}"; do
  # Extract YAML frontmatter between --- delimiters
  FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$state_file")
  SPEC_NAME=$(echo "$FRONTMATTER" | grep '^spec_name:' | sed 's/spec_name: *//')
  CYCLE=$(echo "$FRONTMATTER" | grep '^cycle:' | sed 's/cycle: *//')
  PHASE=$(echo "$FRONTMATTER" | grep '^phase:' | sed 's/phase: *//')
  echo "Warning: Active Theodore session '${SPEC_NAME}' (cycle ${CYCLE}, phase: ${PHASE}). Run /theodore to resume or /cancel-theodore to cancel." >&2
done

# Allow exit (don't block)
exit 0
