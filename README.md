# Theodore

A [Claude Code plugin](https://docs.anthropic.com/en/docs/claude-code/plugins) that runs an autonomous build/review loop. A **Builder** agent writes code (TDD-style, tests first) while a **Reviewer** agent evaluates the PR diff, and they iterate until the reviewer approves or a cycle limit is hit.

All work happens in an isolated git worktree. Your main branch is never touched.

## How it works

```
spec.md --> [Builder] --> tests pass? --> [Mutation Testing] --> [PR] --> [Reviewer]
                ^                                                            |
                |______________ findings __________________________________|
```

1. **Build**: The Builder agent reads your spec and writes tests first, then the minimum implementation to make them pass.
2. **Verify**: The test suite runs. If tests fail, the Builder gets retries to fix them.
3. **Mutate**: Small, deliberate bugs are introduced into the implementation to verify test quality. If tests don't catch a mutation, the Builder must add better tests before the code goes to review.
4. **Publish**: Code is committed to a feature branch and a PR is created (or updated).
5. **Review**: The Reviewer agent examines the PR diff against the spec, checking correctness, architecture, security, and test coverage. It either approves or returns structured findings.
6. **Loop**: If the reviewer requests changes, findings flow back to the Builder and the cycle repeats.

## Installation

Clone this repo into your Claude Code plugins directory:

```bash
git clone https://github.com/trevorwelch/theodore.git ~/.claude/plugins/theodore
```

## Usage

```
/theodore spec.md [--repo /path] [--max-cycles 5] [--max-retries 3] [--builder-model opus] [--reviewer-model sonnet]
```

- `spec.md` (required): A markdown file describing what to build
- `--repo`: Path to the target repository (default: current directory)
- `--max-cycles`: Maximum build/review iterations (default: 5)
- `--max-retries`: Maximum test-fix retries per cycle (default: 3)
- `--builder-model`: Model for the Builder agent (default: opus)
- `--reviewer-model`: Model for the Reviewer agent (default: opus)

### Cancel a session

```
/cancel-theodore
```

### Resume a session

Just run `/theodore` again in the same repo. If an active session exists, you'll be prompted to resume or start fresh.

## Architecture

```
theodore/
├── .claude-plugin/
│   └── plugin.json            # Plugin metadata
├── agents/
│   ├── builder.md             # Builder agent system prompt
│   └── reviewer.md            # Reviewer agent system prompt
├── commands/
│   └── cancel.md              # /cancel-theodore command
├── hooks/
│   └── hooks.json             # Stop hook (warns about active sessions on exit)
├── scripts/
│   ├── setup-worktree.sh      # Creates isolated git worktree and branch
│   └── stop-hook.sh           # Exit warning for active sessions
└── skills/
    └── theodore/
        ├── SKILL.md            # Main orchestrator logic
        └── references/
            ├── builder-playbook.md   # TDD workflow and rules for the Builder
            ├── reviewer-playbook.md  # Code review methodology for the Reviewer
            └── finding-format.md     # Structured format for inter-agent findings
```

### Key design decisions

**Role separation over self-critique.** Rather than having one LLM self-reflect, Theodore splits generation and evaluation into separate agents with distinct system prompts and playbooks.

**Mutation testing as a quality gate.** Between build and review, Theodore introduces deliberate bugs and checks whether tests catch them. Surviving mutants become mandatory findings. This is an automated proxy for "are these tests actually meaningful?"

**Structured inter-agent contract.** Findings follow a rigid format (`category/severity file:line -- description -> action`), reducing ambiguity in agent-to-agent communication. Verdict logic is deterministic: any major finding blocks approval, 3+ minors block, fewer don't.

**Isolation and resumability.** All work happens in git worktrees with persistent state files, so sessions can be interrupted and resumed across Claude Code restarts. Worktrees are automatically cleaned up when sessions end (approved, failed, or max cycles reached).

## Writing a good spec

Theodore works best with specs that have clear, verifiable requirements. Each requirement should be something a test can assert.

```markdown
# User Authentication

## Requirements
- POST /auth/login accepts email and password, returns JWT on success
- JWT expires after 24 hours
- Invalid credentials return 401 with error message
- Rate limit: max 5 failed attempts per email per 15 minutes, then 429
- POST /auth/logout invalidates the token server-side
```

## License

MIT
