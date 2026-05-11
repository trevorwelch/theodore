# Theodore

A [Claude Code plugin](https://docs.anthropic.com/en/docs/claude-code/plugins) that runs an autonomous build/review loop. A **Builder** agent writes code (TDD-style, tests first) while a **Reviewer** agent evaluates the PR diff, and they iterate until the reviewer approves or a cycle limit is hit.

All work happens in an isolated git worktree. Your main branch is never touched.

## How it works

```
spec.md --> [Builder] --> tests pass? --> [Challenge] --> [PR] --> [Reviewer]
                ^                                                     |
                |______________ findings ___________________________|
```

1. **Build**: The Builder agent reads your spec and writes tests first, then the minimum implementation to make them pass.
2. **Verify**: The test suite runs. If tests fail, the Builder gets retries to fix them.
3. **Challenge**: Theodore runs a small falsification pass when one is useful. Logic-heavy changes may get mutation testing; docs, styling, config, or other noisy changes can be skipped with a recorded reason.
4. **Publish**: Code is committed to a feature branch and a PR is created (or updated).
5. **Review**: The Reviewer agent examines the PR diff against the spec, checking correctness, architecture, security, and test coverage. It either approves or returns structured findings.
6. **Loop**: If the reviewer requests changes, findings flow back to the Builder and the cycle repeats.

## Installation

Clone the repo:

```bash
git clone https://github.com/trevorwelch/theodore.git ~/coding/theodore
```

Start Claude Code from any project:

```bash
claude
```

Add Theodore as a local plugin marketplace:

```
/plugin marketplace add ~/coding/theodore
```

Install the plugin:

```
/plugin install theodore@theodore
```

Restart Claude Code after installation. Verify that `/theodore` appears in `/help`.

If you previously added the marketplace before pulling the latest Theodore changes, refresh
it first:

```
/plugin marketplace update theodore
```

If installation fails with `This plugin uses a source type your Claude Code version does
not support`, make sure [.claude-plugin/marketplace.json](.claude-plugin/marketplace.json)
uses `"source": "./"` for Theodore, then run:

```
/plugin marketplace update theodore
/plugin install theodore@theodore
```

### Command-line install after adding the marketplace

After `/plugin marketplace add ~/coding/theodore` has registered the local marketplace,
you can reinstall or install through the Claude Code CLI:

```bash
claude plugin install theodore@theodore
```

Claude Code installs plugins to user scope by default. Use the interactive `/plugin`
interface if you want a project or local install scope instead.

### Updating

Pull the latest Theodore changes, then reinstall the plugin:

```bash
cd ~/coding/theodore
git pull
```

In Claude Code:

```
/plugin uninstall theodore@theodore
/plugin install theodore@theodore
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
- `--reviewer-model`: Model for the Reviewer agent (default: sonnet — different model from builder to reduce self-agreement bias)

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
│   ├── plugin.json            # Plugin metadata
│   └── marketplace.json       # Local marketplace for installation
├── agents/
│   ├── builder.md             # Builder agent system prompt
│   └── reviewer.md            # Reviewer agent system prompt
├── commands/
│   └── cancel.md              # /cancel-theodore command
├── hooks/
│   └── hooks.json             # Stop hook (warns about active sessions on exit)
├── scripts/
│   ├── setup-worktree.sh      # Creates isolated git worktree and branch
│   ├── state-set.sh           # Updates Theodore state frontmatter
│   ├── cycle-diff.sh          # Shows changes since the cycle-start tag
│   ├── extract-challenge-plan.sh # Extracts and validates challenge-plan
│   ├── extract-verdict.sh     # Extracts and validates reviewer json-verdict
│   └── stop-hook.sh           # Exit warning for active sessions
└── skills/
    └── theodore/
        ├── SKILL.md            # Main orchestrator logic
        └── references/
            ├── acceptance-criteria-guide.md   # Converts specs into testable criteria
            ├── challenge-strategy-guide.md    # Chooses the post-test challenge strategy
            ├── builder-playbook.md            # TDD workflow and rules for the Builder
            ├── reviewer-playbook.md           # Code review methodology for the Reviewer
            ├── mutation-testing-playbook.md   # Logic mutation challenge workflow
            └── finding-format.md              # Structured format for inter-agent findings
```

### Key design decisions

**Role separation over self-critique.** Rather than having one LLM self-reflect, Theodore splits generation and evaluation into separate agents with distinct system prompts and playbooks.

**Challenge testing over blanket mutation.** Between build and review, Theodore chooses a small falsification pass. Today, the active strategy is logic mutation for deterministic code paths; when mutation would be noisy or meaningless, the challenge is skipped with an explicit reason. Surviving mutants become mandatory findings.

**Structured inter-agent contract.** Findings follow a rigid format (`category/severity file:line -- description -> action`), reducing ambiguity in agent-to-agent communication. Verdict logic is deterministic: any major finding blocks approval, 3+ minors block, fewer don't.

**Isolation and resumability.** All work happens in git worktrees with persistent state files, so sessions can be interrupted and resumed across Claude Code restarts. Worktrees are automatically cleaned up when sessions end (approved, failed, or max cycles reached).

**Tiny deterministic helpers.** Theodore keeps judgment-heavy work in agents, but uses small shell helpers for path-sensitive bookkeeping: state updates, cycle diffs, challenge plan parsing, and reviewer verdict parsing. These scripts take explicit paths and print machine-readable output so the orchestrator has less fragile prose parsing to do.

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
