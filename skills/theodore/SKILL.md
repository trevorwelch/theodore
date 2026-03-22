---
description: "Autonomous dual-agent build/review loop"
argument-hint: "spec.md [--repo /path] [--max-cycles 5] [--max-retries 3] [--builder-model opus] [--reviewer-model opus]"
allowed-tools: ["Read", "Edit", "Write", "Glob", "Grep", "Bash(*)", "Agent(*)"]
---

# Theodore: Dual-Agent Build/Review Loop

You are the orchestrator. Follow these steps exactly.

## CRITICAL: Autonomous Execution

This is a fully autonomous build/review loop. You MUST execute ALL phases from start to finish in a single, uninterrupted run. **DO NOT** pause, stop, or wait for user input between phases or steps. **DO NOT** treat the completion of a sub-step (agent returning, tool completing, study finishing) as a stopping point. The ONLY reasons to stop are:
- A terminal state is reached (approved, failed, or max_cycles_reached)
- An unrecoverable error occurs that you cannot handle

After every agent dispatch, tool call, or phase completion, **immediately proceed to the next step in the same response**. Do not output a status update and then stop. Every response you generate MUST end with either a tool call (the next action) or a terminal state report. If your response would end with just text and no tool call, you are stalling -- add the next action.

Common stall points to avoid:
- After codebase study agents return: immediately write the state file
- After builder agent returns: immediately run tests (VERIFY)
- After tests pass: immediately run mutation testing
- After mutation testing: immediately publish (PUBLISH)
- After publishing PR: immediately dispatch reviewer
- After reviewer returns: immediately parse verdict and act on it

## Phase 0: Parse Arguments

Parse `$ARGUMENTS` to extract:
- `spec_file` (required): first positional argument, path to a .md spec file
- `--repo <path>` (optional, default: current working directory)
- `--max-cycles <N>` (optional, default: 5)
- `--max-retries <N>` (optional, default: 3)
- `--builder-model <model>` (optional, default: opus)
- `--reviewer-model <model>` (optional, default: opus)

If no arguments or no spec file provided, output this usage message and stop:
```
Usage: /theodore spec.md [--repo /path] [--max-cycles 5] [--max-retries 3] [--builder-model opus] [--reviewer-model opus]

Theodore is a dual-agent autonomous build/review loop.
A Builder agent writes code (TDD-style) and a Reviewer agent reviews the PR,
iterating until the reviewer approves or max cycles are exhausted.
All work happens in an isolated git worktree. Your main branch is never touched.
```

Read the spec file. If it doesn't exist, report the error and stop.

Resolve the plugin root by running: `echo "${CLAUDE_PLUGIN_ROOT}"`
Store this as `PLUGIN_ROOT` for all subsequent file references.

Derive `SPEC_NAME` from the spec filename (strip path and .md extension).

## Phase 1: Resume Check & Cleanup

Search for existing Theodore worktrees:
```bash
find <repo>/.claude/worktrees/theodore-*/.theodore/ -name "state.md" 2>/dev/null
```

Also check for orphaned worktrees (directories with no state file):
```bash
ls -d <repo>/.claude/worktrees/theodore-*/ 2>/dev/null
```

**Cleanup orphaned worktrees**: For any worktree directory that has NO `.theodore/state.md` file (or the state file is empty/unreadable), silently clean it up:
```bash
git -C <repo> worktree remove <orphaned_worktree_path> --force 2>/dev/null
git -C <repo> branch -D <branch_from_path> 2>/dev/null
```

For each state file found, check if it contains `active: true`.

**If an active session exists:**
- Read the state file to get the current `phase`, `cycle`, and `spec_name`
- Tell the user: "Found active Theodore session '<spec_name>' at cycle <N>, phase: <phase>."
- Ask: "Resume this session, or start fresh (which cancels the existing one)?"
- If resume: read the full state file, set variables from its frontmatter, and resume based on `phase`:
  - `build`: restart Step 1 (BUILD) for the current cycle
  - `verify`: restart Step 2 (VERIFY) for the current cycle
  - `mutate`: restart Step 2b (MUTATE) for the current cycle
  - `publish`: restart Step 3 (PUBLISH) for the current cycle
  - `review`: restart Step 4 (REVIEW) for the current cycle
  - `complete` or `failed` or `max_cycles_reached`: these are terminal states, report status and stop
- If start fresh: clean up the old session (remove worktree and branch), then continue to Phase 2

**If state files exist but none have `active: true`**: These are completed/failed sessions. Clean up their worktrees silently and continue to Phase 2.

**If no state files or worktrees found**: Continue to Phase 2.

## Phase 2: Setup

### 2a: Create Worktree

Run the setup script:
```bash
"${PLUGIN_ROOT}/scripts/setup-worktree.sh" --repo <repo_path> --spec-name <SPEC_NAME>
```

Parse the output to extract `branch_name` and `worktree_path` values.

### 2b: Codebase Study

Dispatch **two Explore agents in parallel** into the worktree. Both should explore the worktree path.

**Builder study agent** (model: sonnet):
```
Explore the codebase at <worktree_path> and report:
1. Project language(s) and framework(s)
2. Directory structure and module organization
3. Key architectural patterns (layering, dependency injection, etc.)
4. Test framework and conventions (file naming, assertion style, test runner)
5. The exact command to run tests (e.g., "npm test", "pytest", "cargo test")
6. Build commands if applicable
7. Any configuration files that affect development (tsconfig, eslint, pyproject, etc.)

Be thorough but concise. Format your report with clear headings.
```

**Reviewer study agent** (model: sonnet):
```
Explore the codebase at <worktree_path> and report:
1. Code style and formatting conventions (indentation, naming patterns, import style)
2. Module boundaries and layering (what goes where)
3. Error handling patterns
4. Security-relevant patterns (auth, input validation, data sanitization)
5. API design patterns (REST conventions, response formats, error codes)
6. Dependency management approach
7. Any linting/formatting config that enforces standards

Be thorough but concise. Format your report with clear headings.
```

Collect both study reports. **Immediately proceed to 2c -- do not stop here.**

### 2c: Write State File

If `<worktree>/.theodore/state.md` already exists (from a crashed prior attempt), delete it first:
```bash
rm -f <worktree>/.theodore/state.md
```

Then write the initial state file at `<worktree>/.theodore/state.md`:

```markdown
---
active: true
phase: build
cycle: 1
max_cycles: <max_cycles>
max_retries: <max_retries>
builder_model: <builder_model>
reviewer_model: <reviewer_model>
spec_name: <SPEC_NAME>
repo_path: <repo_path>
worktree_path: <worktree_path>
branch_name: <branch>
pr_number: null
pr_url: null
test_command: <extracted from builder study>
started_at: "<current UTC timestamp>"
---

## Spec

<full contents of the spec file>

## Builder Study

<builder study report>

## Reviewer Study

<reviewer study report>

## Findings

None yet.
```

Report to the user: "Theodore session initialized. Starting build/review loop." **Immediately proceed to Phase 3 -- do not stop here.**

## Phase 3: The Loop

Loop from `cycle` to `max_cycles`:

### Step 1: BUILD

Update state file: set `phase: build`, `cycle: <current>`

Dispatch a **general-purpose Agent** (model: `builder_model` from state).

On **cycle 1**, use this prompt:
```
You are the Builder agent in a Theodore build/review loop.

Working directory: <worktree_path>
Cycle: 1 of <max_cycles> (fresh build, no prior findings)
Plugin root: <PLUGIN_ROOT>

Read these files to get your instructions and context:
1. Builder playbook: <PLUGIN_ROOT>/skills/theodore/references/builder-playbook.md
2. Finding format: <PLUGIN_ROOT>/skills/theodore/references/finding-format.md
3. State file: <worktree_path>/.theodore/state.md

Follow the "Cycle 1: Fresh Build" section of the builder playbook.
All file paths must be absolute, within the worktree.

When done, output your BUILD COMPLETE summary.
```

On **cycle 2+**, use this prompt:
```
You are the Builder agent in a Theodore build/review loop.

Working directory: <worktree_path>
Cycle: <N> of <max_cycles> (FINDINGS FROM PREVIOUS REVIEW MUST BE ADDRESSED FIRST)
Plugin root: <PLUGIN_ROOT>

Read these files to get your instructions and context:
1. Builder playbook: <PLUGIN_ROOT>/skills/theodore/references/builder-playbook.md
2. Finding format: <PLUGIN_ROOT>/skills/theodore/references/finding-format.md
3. State file: <worktree_path>/.theodore/state.md

IMPORTANT: The state file contains "Findings" and/or "Mutation Findings" sections with
feedback from the previous cycle. You MUST address ALL major findings before any new work.
Mutation findings mean the tests failed to catch a deliberate bug at that location -- you
must add tests that would catch it. Follow the "Cycle 2+: Address Findings First" section
of the builder playbook.
All file paths must be absolute, within the worktree.

When done, output your BUILD COMPLETE summary.
```

Report builder progress to user (1-2 sentences max). **Immediately proceed to Step 2 -- do not stop here.**

### Step 2: VERIFY

Update state file: set `phase: verify`

Extract the `test_command` from the state file frontmatter.
Run the tests from the worktree:
```bash
bash -c 'cd <worktree_path> && <test_command>'
```

**If tests pass**: report "Tests passed." and **immediately proceed to Step 2b**.

**If tests fail**: enter the inner fix loop (up to `max_retries`):

For each retry:
1. Capture the test failure output
2. Dispatch a **general-purpose Agent** (model: `builder_model`):
   ```
   You are the Builder agent in a Theodore build/review loop (fix mode).

   Working directory: <worktree_path>
   Plugin root: <PLUGIN_ROOT>

   Tests failed. Here is the failure output:
   <test failure output>

   Read the state file at <worktree_path>/.theodore/state.md for context.
   Fix the failing tests. All file paths must be absolute, within the worktree.
   Do NOT change test expectations unless they are clearly wrong. Fix the implementation.
   ```
3. Re-run tests: `bash -c 'cd <worktree_path> && <test_command>'`
4. If tests pass: break out of inner loop
5. If tests still fail: continue to next retry

**If tests still fail after all retries**: report failure to user with the last error output, update state `phase: failed`, set `active: false`. Clean up the worktree and branch:
```bash
git -C <repo_path> worktree remove <worktree_path> --force
git -C <repo_path> branch -D <branch_name>
```
Stop.

### Step 2b: MUTATE

Update state file: set `phase: mutate`

This step verifies test quality by introducing small, deliberate bugs (mutants) into the implementation and checking that the tests catch them. A surviving mutant means the tests are too weak.

Dispatch a **general-purpose Agent** (model: `builder_model` from state):
```
You are a Mutation Testing agent in a Theodore build/review loop.

Working directory: <worktree_path>
Plugin root: <PLUGIN_ROOT>

Read the state file at <worktree_path>/.theodore/state.md for spec context, the test command,
and the builder study (to understand project patterns).

Your job is to verify test quality through mutation testing. Follow these steps:

1. IDENTIFY TARGETS: Read the implementation files created/modified for this spec (NOT test files).
   For each file, identify 3-5 critical logic points: conditionals, boundary checks, error handling,
   return values, arithmetic operations.

2. GENERATE MUTANTS: For each target, create a small, realistic mutation. Good mutations:
   - Flip a conditional (< to <=, == to !=)
   - Change a boundary value (+1, -1)
   - Remove an error check or early return
   - Swap a variable for a related one
   - Change an operator (+ to -, && to ||)
   - Return a wrong value (null, empty, hardcoded)

   Bad mutations (DO NOT generate these):
   - Syntax errors (the code must still parse)
   - Deleting entire functions (too obvious)
   - Changes unrelated to spec requirements

3. TEST EACH MUTANT: For each mutation:
   a. Apply the mutation using the Edit tool
   b. Run the test command: bash -c 'cd <worktree_path> && <test_command>'
   c. Record the result: KILLED (test failed = good) or SURVIVED (test passed = bad)
   d. IMMEDIATELY revert the mutation using the Edit tool (restore the original code)
   e. Verify the revert is correct before moving to the next mutant

   CRITICAL: You MUST revert each mutation before applying the next one. Never leave a mutation
   in place. After all mutants are tested, run the full test suite once more to confirm the
   code is back to its original, passing state.

4. REPORT: Output your results in this exact format:

MUTATION REPORT
Mutants tested: <N>
Killed: <N>
Survived: <N>

SURVIVED MUTANTS:
<file>:<line> -- <description of mutation> -- <what this means the tests are missing>
...

If all mutants were killed, output:
MUTATION REPORT
Mutants tested: <N>
Killed: <N>
Survived: 0

Generate at least 5 mutants total across the implementation files.
```

**After the mutation agent returns**, verify the worktree is clean (no leftover mutations):
```bash
git -C <worktree_path> diff --quiet || git -C <worktree_path> checkout -- .
```
Then run the test suite once more to confirm the code is in a passing state:
```bash
bash -c 'cd <worktree_path> && <test_command>'
```
If tests fail after this safety check, a mutation was not properly reverted. Dispatch the builder agent in fix mode (same as the VERIFY retry loop) before proceeding.

**Parse the mutation report.**

- If **all mutants killed**: report "Mutation testing passed: <N>/<N> mutants killed." and **immediately proceed to Step 3 -- do not stop here.**
- If **any mutants survived**: these become automatic findings. For each survived mutant, create a finding:
  ```
  testing/major <file>:<line> -- Mutation survived: <description> -> Add test that catches this case
  ```
  Append these findings to the state file under a new section:
  ```
  ## Mutation Findings (Cycle <N>)

  <survived mutant findings>
  ```
  Do NOT proceed to publish or review. Instead, loop back to **Step 1 (BUILD)** for the next cycle,
  incrementing the cycle counter. The builder will see these mutation findings and must add tests
  to cover the gaps before the code goes to review.

  If this was the last cycle (`cycle == max_cycles`), update state: `phase: max_cycles_reached`,
  `active: false`, report the surviving mutants to the user, and stop.

### Step 3: PUBLISH

Update state file: set `phase: publish`

Run these git commands from the worktree:
```bash
git -C <worktree_path> add -A && git -C <worktree_path> commit -m "theodore: cycle <N> - <SPEC_NAME>"
```

**Cycle 1** (no PR exists yet):
```bash
git -C <worktree_path> push -u origin <branch_name>
```
Then create the PR:
```bash
gh pr create --repo <repo_path> --head <branch_name> --title "theodore: <SPEC_NAME>" --body "$(cat <<'EOF'
## Spec

<full spec contents, or a concise summary if the spec exceeds 40 lines>

## What was built

<brief summary of the implementation based on the builder's BUILD COMPLETE output>

---

*Automated PR by [Theodore](https://github.com/trevorwelch/theodore) build/review loop.*
EOF
)"
```
Parse the PR URL and number from gh output. Update the state file: set `pr_number` and `pr_url`.

**Cycle 2+** (PR already exists):
```bash
git -C <worktree_path> push
```
Add a comment noting the cycle:
```bash
gh pr comment <pr_number> --repo <repo_path> --body "Cycle <N>: Addressed reviewer findings and pushed updates."
```

Report PR status to user (1-2 sentences max). **Immediately proceed to Step 4 -- do not stop here.**

### Step 4: REVIEW

Update state file: set `phase: review`

Dispatch a **general-purpose Agent** (model: `reviewer_model` from state):
```
You are the Reviewer agent in a Theodore build/review loop.

PR number: <pr_number>
Repo: <repo_path>
Worktree: <worktree_path>
Cycle: <N> of <max_cycles>
Plugin root: <PLUGIN_ROOT>

Read these files to get your instructions and context:
1. Reviewer playbook: <PLUGIN_ROOT>/skills/theodore/references/reviewer-playbook.md
2. Finding format: <PLUGIN_ROOT>/skills/theodore/references/finding-format.md
3. State file: <worktree_path>/.theodore/state.md (for spec and codebase context only)

Then get the PR diff:
  gh pr diff <pr_number> --repo <repo_path>

Review the diff following the reviewer playbook exactly. You MUST include an explicit
spec requirement checklist in your review output. If you need surrounding context to
verify correctness for any file in the diff, you may read the full file at its worktree
path (<worktree_path>/...). Output your verdict.
```

### Step 5: Check Verdict

Parse the reviewer agent's output for the verdict line.

**VERDICT: APPROVED**
- Update state: `phase: complete`, `active: false`
- Comment on the PR: `gh pr comment <pr_number> --repo <repo_path> --body "Theodore: Reviewer approved at cycle <N>. PR ready for human review."`
- Clean up the worktree (the branch and PR persist on the remote):
  ```bash
  git -C <repo_path> worktree remove <worktree_path> --force
  ```
- Report to user: "Reviewer approved! PR is ready for human review: <pr_url>"
- Stop the loop.

**VERDICT: CHANGES_REQUESTED**
- Extract the FINDINGS block from the reviewer output (everything after `FINDINGS:`)
- Append findings to the state file under a new section:
  ```
  ## Findings (Cycle <N>)

  <extracted findings>
  ```
- If this was the last cycle (`cycle == max_cycles`):
  - Update state: `phase: max_cycles_reached`, `active: false`
  - Clean up the worktree (the branch and PR persist on the remote):
    ```bash
    git -C <repo_path> worktree remove <worktree_path> --force
    ```
  - Report to user: "Max cycles (<max_cycles>) reached. Outstanding findings:\n<findings>\nPR: <pr_url>"
  - Stop the loop.
- Otherwise: increment cycle and **immediately loop back to Step 1 -- do not stop here.**

**No clear verdict found**:
- Treat as CHANGES_REQUESTED with a single finding: `conventions/major orchestrator:0 -- Reviewer output missing structured verdict -> Re-review with proper VERDICT format`
- **Immediately continue the loop -- do not stop here.**
