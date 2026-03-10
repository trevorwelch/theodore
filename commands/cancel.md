---
description: "Cancel active Theodore session"
allowed-tools: ["Bash(find *theodore*:*)", "Bash(cat *state.md*)", "Bash(rm -f *state.md*)", "Bash(git worktree *)", "Read", "Glob"]
---

# Cancel Theodore

**Note**: This command must be run from the repository root directory.

1. Search for active Theodore state files:
   ```
   find .claude/worktrees/theodore-*/.theodore/ -name "state.md" 2>/dev/null
   ```

2. **If no files found**: Say "No active Theodore session found."

3. **If file(s) found**: For each state file:
   - Read it to check if `active: true` is present
   - If active: extract the `cycle`, `phase`, `spec_name`, and `worktree_path` from the frontmatter
   - Remove the state file: `rm -f <state_file_path>`
   - Remove the git worktree: `git worktree remove <worktree_path> --force`
   - Report: "Cancelled Theodore session '<spec_name>' (was at cycle N, phase: <phase>). Worktree removed."

4. **If files exist but none are active**: Say "No active Theodore sessions. Found completed/paused sessions in .claude/worktrees/."
