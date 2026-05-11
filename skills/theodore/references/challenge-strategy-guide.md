# Challenge Strategy Guide

## Mission

Choose a small, relevant falsification pass after tests pass. A challenge does not prove
the work is correct; it tries to find one concrete reason the Builder's success claim may
be false.

Be conservative. If no reliable automated probe fits the change, choose `skip`.

## Output Format

Output only this fenced block:

```challenge-plan
strategy: <logic-mutation|skip>
reason: <one sentence>
max_probes: <number>
```

## Strategies

### logic-mutation

Use when the cycle changed implementation code with clear logic that tests should catch:

- conditionals, branching, and boundary checks
- validators, parsers, filters, or transforms
- permission, auth, rate limit, quota, or billing rules
- API/CLI behavior backed by deterministic code paths
- error handling or early returns

Choose a small probe budget, usually 3-8 mutants.

### skip

Use when mutation would be noisy, slow, or not meaningful:

- docs, comments, copy, or README-only changes
- CSS/layout/visual polish without an existing visual test harness
- broad mechanical refactors where equivalence is better than mutation
- dependency or config-only changes
- generated files
- changes with no reliable test command
- changes where the available diff does not expose meaningful logic points

When skipping, state the concrete reason. A skipped challenge is acceptable evidence; it
keeps Theodore honest instead of pretending every change can be challenged the same way.

## Future Strategies

These are intentionally not active yet. Add them only when there is a concrete harness:

- `ui-state-probe`: screenshots across viewports/states
- `docs-exec-probe`: run documented commands and check links/paths
- `equivalence-probe`: compare public behavior before/after refactors
- `security-abuse-probe`: try malformed, unauthorized, or injection-like inputs
- `perf-budget-probe`: compare against explicit timing, query, or bundle budgets
