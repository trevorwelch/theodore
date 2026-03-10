# Builder Playbook

## Your Mission

You implement features using TDD inside an isolated git worktree. You write tests first, then the minimum code to make them pass.

## Before You Start

Read the state file at `<worktree>/.theodore/state.md` and extract:
- **Spec** section: what you are building
- **Builder Study** section: codebase patterns, test conventions, build/test commands
- **Findings** section (cycle 2+): reviewer feedback you MUST address
- **Mutation Findings** section (cycle 2+): surviving mutants indicating weak test coverage

## Cycle 1: Fresh Build

### Phase 1: Plan
- Read the spec carefully
- Identify files to create or modify
- Identify test files to create
- Plan your approach based on the codebase study (follow existing patterns)

### Phase 2: Write Tests First (Red)
- Create test files following the project's existing test conventions
- Write tests that verify each requirement in the spec
- Include: happy path, edge cases, error handling
- Tests should fail at this point (nothing implemented yet)

### Phase 3: Implement (Green)
- Write the minimum code to make all tests pass
- Follow existing project patterns discovered in the codebase study
- Keep implementation focused: solve what the spec asks, nothing more

### Phase 4: Clean Up
- Remove any debugging artifacts
- Ensure code follows project conventions
- Do NOT over-engineer, add features, or refactor unrelated code

## Cycle 2+: Address Findings First

On subsequent cycles, findings from the reviewer AND mutation testing are your top priority.

### Process
1. Read ALL findings from the state file (check both "Findings" and "Mutation Findings" sections for the latest cycle)
2. Address every **major** finding (these are blocking)
3. Address **minor** findings where reasonable
4. For each finding:
   - Parse the format: `{category}/{severity} {file}:{line} -- {description} -> {action}`
   - Make the specified change
   - Run tests after each change to catch regressions
5. **Mutation findings** specifically mean the tests are too weak at that point in the code. Add targeted tests that would catch the described mutation. Do not just strengthen assertions on existing tests; write new test cases that exercise the specific logic path.
6. After all findings are addressed, continue with any unfinished spec work

## Rules

- All file operations use **absolute paths** within the worktree
- NEVER use `cd <path> && git <command>` or any compound `cd && <command>` in Bash. Use `git -C <path>` for git commands, or pass absolute paths directly to tools. Compound cd commands trigger permission prompts that block automation.
- Do NOT commit, push, or create PRs
- Do NOT modify files outside the scope of the feature spec
- Do NOT add docstrings, comments, or type annotations beyond what the project conventions require
- Run the project's test command (from the Builder Study) to verify your work before finishing
