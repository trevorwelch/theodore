---
description: "Autonomous dual-agent build/review loop"
argument-hint: "spec.md [--repo /path] [--max-cycles 5] [--max-retries 3] [--builder-model opus] [--reviewer-model sonnet]"
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
- `--reviewer-model <model>` (optional, default: sonnet — deliberately different from builder to reduce self-agreement bias)

If no arguments or no spec file provided, output this usage message and stop:
```
Usage: /theodore spec.md [--repo /path] [--max-cycles 5] [--max-retries 3] [--builder-model opus] [--reviewer-model sonnet]

Theodore is a dual-agent autonomous build/review loop.
A Builder agent writes code (TDD-style) and a Reviewer agent reviews the PR,
iterating until the reviewer approves or max cycles are exhausted.
All work happens in an isolated git worktree. Your main branch is never touched.
```

Read the spec file. If it doesn't exist, report the error and stop.

**PLUGIN_ROOT resolution (mandatory, do this FIRST before any file references):**
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
# Fallback: resolve from the skill symlink's parent structure
if [ -z "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." 2>/dev/null && pwd)"
fi
```
Run: `echo "${CLAUDE_PLUGIN_ROOT}"` to get `PLUGIN_ROOT`. If empty, resolve it by reading the skill symlink target (`readlink ~/.claude/skills/theodore`) and stripping the trailing `/skills/theodore` to get the plugin root directory. **All script/agent/reference paths MUST use `PLUGIN_ROOT`, never the skill directory path.** The skill directory only contains `SKILL.md` and `references/` — scripts, agents, and hooks are at the plugin root.

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

### 2c: Define Acceptance Criteria

Dispatch a **general-purpose Agent** (model: sonnet):
```
You are an Acceptance Criteria agent in a Theodore build/review loop.

Plugin root: <PLUGIN_ROOT>
Worktree: <worktree_path>

Read these files:
1. Acceptance criteria guide: <PLUGIN_ROOT>/skills/theodore/references/acceptance-criteria-guide.md
2. The feature spec (provided below)

Feature Spec:
<full contents of the spec file>

Codebase Context:
<builder study report — so the agent knows what test frameworks/tools are available>

Generate acceptance criteria following the guide. Prefer criteria that verify behavior
the way a human would experience it (e2e tests for web apps, realistic API calls for
services, actual CLI invocations for tools). Unit-level criteria are supporting evidence,
not the primary eval.

If the spec already contains an "Acceptance Criteria" section, refine and formalize it
into the structured format rather than generating from scratch. Preserve the user's intent.

Output ONLY the acceptance criteria in the specified format.
```

Collect the acceptance criteria output. **Immediately proceed to 2d -- do not stop here.**

### 2d: Write State File

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

## Acceptance Criteria

<acceptance criteria output from Phase 2c>

## Findings

None yet.
```

Report to the user: "Theodore session initialized. Starting build/review loop." **Immediately proceed to Phase 3 -- do not stop here.**

## Phase 3: The Loop

Loop from `cycle` to `max_cycles`:

### Step 1: BUILD

Update state file: set `phase: build`, `cycle: <current>`

Tag the current state for rollback and logging:
```bash
git -C <worktree_path> tag -f "theodore/cycle-<N>-start"
```

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

IMPORTANT: The state file contains an "Acceptance Criteria" section. These criteria are
your primary targets. Every criterion must have a corresponding test. Write tests that
verify behavior the way a human would experience it (e2e for web apps, realistic API calls
for services). Unit tests are supporting evidence, not the primary eval.

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
must add tests that would catch it. The "Acceptance Criteria" section defines your primary
targets. Every criterion must still have a passing test. Follow the "Cycle 2+: Address
Findings First" section of the builder playbook.
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
Test command: <test_command>

Read these files:
1. Mutation testing playbook: <PLUGIN_ROOT>/skills/theodore/references/mutation-testing-playbook.md
2. State file: <worktree_path>/.theodore/state.md (for spec context and builder study)

Follow the playbook exactly. Only mutate files and lines touched in this cycle.
```

**After the mutation agent returns**, verify the worktree is clean (no leftover mutations):
```bash
git -C <worktree_path> diff
```
If the diff is non-empty, a mutation was not properly reverted. Reset the worktree:
```bash
git -C <worktree_path> checkout -- .
```
Then run the test suite once more to confirm the code is in a passing state:
```bash
bash -c 'cd <worktree_path> && <test_command>'
```
If tests fail after this safety check, a mutation leaked into the code. Dispatch the builder agent in fix mode (same as the VERIFY retry loop) before proceeding.

**Parse the mutation report.**

- If **all mutants killed**: report "Mutation testing passed: <N>/<N> mutants killed." and **immediately proceed to Step 3 -- do not stop here.**
- If **any mutants survived**: these become automatic findings. For each survived mutant, create a finding with a sequential ID (starting from `[M1]` to distinguish from reviewer findings):
  ```
  [M1] testing/major <file>:<line> -- Mutation survived: <description> -> Add test that catches this case
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
Add a structured comment detailing the cycle. Build the comment body from the builder's BUILD COMPLETE summary:
```bash
gh pr comment <pr_number> --repo <repo_path> --body "$(cat <<'EOF'
## Cycle <N>

### Findings Addressed
- [F1]: <what was done>
- [F2]: <what was done>
- [M1]: <what was done> (if mutation findings existed)

### Tests Added
- <test descriptions from builder summary>

### Mutations
- <N>/<N> killed (or "No mutation cycle" if mutations passed on previous cycle)
EOF
)"
```

Report PR status to user (1-2 sentences max). **Immediately proceed to Step 4 -- do not stop here.**

### Step 4: REVIEW

Update state file: set `phase: review`

Dispatch a **general-purpose Agent** (model: `reviewer_model` from state).

**Important — context isolation**: The reviewer must NOT see the Builder Study section of the state file (it contains builder-specific context that creates self-agreement bias). Before dispatching, extract only the sections the reviewer needs: **Spec**, **Reviewer Study**, **Acceptance Criteria**, and any prior **Findings** sections. Pass these directly in the prompt rather than pointing the reviewer at the full state file.

```
You are the Reviewer agent in a Theodore build/review loop.

PR number: <pr_number>
Repo: <repo_path>
Worktree: <worktree_path>
Cycle: <N> of <max_cycles>
Plugin root: <PLUGIN_ROOT>

Read these files to get your instructions:
1. Reviewer playbook: <PLUGIN_ROOT>/skills/theodore/references/reviewer-playbook.md
2. Finding format: <PLUGIN_ROOT>/skills/theodore/references/finding-format.md

Here is your context (extracted from the session state):

## Spec
<spec contents from state file>

## Reviewer Study
<reviewer study section from state file>

## Acceptance Criteria
<acceptance criteria section from state file>

## Prior Findings
<findings sections from state file, or "None" if cycle 1>

Now get the PR diff:
  gh pr diff <pr_number> --repo <repo_path>

Review the diff following the reviewer playbook exactly. Your primary checklist is the
Acceptance Criteria. For each criterion, verify implementation exists and a test proves
it works at the right level (e2e/integration for user-facing behavior, not just unit tests).
Mark each criterion PASS or FAIL. If you need surrounding context to verify correctness
for any file in the diff, you may read the full file at its worktree path (<worktree_path>/...).

Output your verdict as a json-verdict code block.
```

### Step 5: Check Verdict

Parse the reviewer agent's output for the `json-verdict` code block. Extract the JSON object and read the `verdict` and `findings` fields.

**If no `json-verdict` block is found**: Treat as CHANGES_REQUESTED with a single finding: `[F1] conventions/major orchestrator:0 -- Reviewer output missing json-verdict block -> Re-review with proper verdict format`. **Immediately continue the loop — do not stop here.**

**`"verdict": "APPROVED"`**
- Update state: `phase: complete`, `active: false`
- If the `findings` array is non-empty (1-2 minor notes), append them to the state file for reference
- Comment on the PR: `gh pr comment <pr_number> --repo <repo_path> --body "Theodore: Reviewer approved at cycle <N>. PR ready for human review."`
- Clean up the worktree (the branch and PR persist on the remote):
  ```bash
  git -C <repo_path> worktree remove <worktree_path> --force
  ```
- Report to user: "Reviewer approved! PR is ready for human review: <pr_url>"
- Stop the loop.

**`"verdict": "CHANGES_REQUESTED"`**
- Extract the `findings` array from the JSON
- Append findings to the state file under a new section:
  ```
  ## Findings (Cycle <N>)

  <each finding from the array, one per line>
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
