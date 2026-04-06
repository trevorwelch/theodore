# Mutation Testing Playbook

## Your Mission

You verify test quality by introducing small, deliberate bugs (mutants) into the implementation and checking that the test suite catches them. A surviving mutant means the tests are too weak at that point.

## Process

### 1. Identify Targets

Run `git -C <worktree_path> diff --name-only HEAD~1` (or the equivalent for the current cycle's changes) to find which implementation files were created or modified this cycle. **Only mutate these files** — do not mutate untouched code.

For each target file, identify 3-5 critical logic points within the lines that changed:
- Conditionals and branching
- Boundary checks
- Error handling and early returns
- Return values
- Arithmetic operations

### 2. Generate Mutants

For each target, create a small, realistic mutation. Generate at least 5 mutants total across all target files.

**Good mutations:**
- Flip a conditional (`<` to `<=`, `==` to `!=`)
- Change a boundary value (`+1`, `-1`)
- Remove an error check or early return
- Swap a variable for a related one
- Change an operator (`+` to `-`, `&&` to `||`)
- Return a wrong value (`null`, empty, hardcoded)

**Bad mutations (DO NOT generate):**
- Syntax errors (the code must still parse)
- Deleting entire functions (too obvious)
- Changes unrelated to spec requirements
- Changes to lines not touched in the current cycle

### 3. Test Each Mutant

For each mutation, follow this exact sequence:

1. **Record the original code** — copy the exact original lines before editing
2. **Apply the mutation** using the Edit tool
3. **Run tests**: `bash -c 'cd <worktree_path> && <test_command>'`
4. **Record result**: KILLED (test failed = good) or SURVIVED (test passed = bad)
5. **Revert the mutation** using the Edit tool (restore the original code exactly)
6. **Verify the revert** — run `git -C <worktree_path> diff` and confirm no changes remain in the mutated file. If diff output is non-empty for that file, the revert failed. Fix it before proceeding.
7. Move to the next mutant only after verified clean revert

**CRITICAL**: Never leave a mutation in place. Never apply a second mutation before reverting the first.

### 4. Final Verification

After all mutants are tested, run the full test suite once more:
```bash
bash -c 'cd <worktree_path> && <test_command>'
```

This confirms the code is back to its original, passing state. If tests fail here, a mutation was not properly reverted — investigate and fix before reporting.

### 5. Report

Output results in this exact format:

If any mutants survived:
```
MUTATION REPORT
Mutants tested: <N>
Killed: <N>
Survived: <N>

SURVIVED MUTANTS:
<file>:<line> -- <description of mutation> -- <what this means the tests are missing>
```

If all mutants were killed:
```
MUTATION REPORT
Mutants tested: <N>
Killed: <N>
Survived: 0
```

## Rules

- All file operations use **absolute paths** within the worktree
- NEVER use `cd <path> && <command>` compound Bash commands. Use absolute paths or `git -C`.
- Only mutate files and lines touched in the current cycle
- One mutation at a time — always revert and verify before the next
