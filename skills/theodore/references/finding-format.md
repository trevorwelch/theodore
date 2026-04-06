# Finding Format

The structured contract between the Reviewer and Builder agents.

## Format

```
[F{n}] {category}/{severity} {file}:{line} -- {description} -> {action}
```

Each finding gets a sequential ID (`[F1]`, `[F2]`, ...) within a review. IDs let the builder reference specific findings when addressing them and let the orchestrator verify each was resolved.

## Categories

- **architecture**: Wrong layer, bad abstraction, coupling issues
- **correctness**: Bugs, missing null checks, logic errors, race conditions
- **testing**: Missing tests, weak assertions, untested edge cases
- **conventions**: Naming, file organization, pattern violations
- **security**: Injection, auth gaps, data exposure, unsafe operations
- **performance**: N+1 queries, unnecessary allocations, missing caching

## Severities

- **major**: Blocking. Must be fixed before approval. Correctness bugs, security issues, architectural violations.
- **minor**: Non-blocking. Should be fixed but won't block approval alone. Style nits, missing edge case tests, minor performance.

## Multi-file issues

When a finding spans multiple files, use the primary file (where the fix should be applied) as the location and reference the related file(s) in the description:

```
[F1] architecture/major src/api/routes.ts:15 -- Business logic in route handler (also affects src/services/auth.ts) -> Extract to service layer
```

## Examples

```
[F1] correctness/major src/auth.ts:42 -- Missing null check on user lookup -> Add guard clause before accessing user.email
[F2] testing/minor tests/login.test.ts:8 -- Missing edge case for expired session -> Add test for token expiry scenario
[F3] architecture/major src/api/routes.ts:15 -- Business logic in route handler -> Extract to service layer
[F4] security/major src/db/query.ts:23 -- String interpolation in SQL query -> Use parameterized query
[F5] conventions/minor src/utils/helpers.ts:1 -- File name too generic -> Rename to reflect actual contents
[F6] performance/minor src/feed.ts:30 -- Fetching all records without pagination -> Add limit/offset
```

## Verdict Format

The reviewer MUST end their review with a JSON verdict block inside a fenced code block tagged `json-verdict`:

Approved (no findings, or 1-2 minor):
````
```json-verdict
{"verdict": "APPROVED", "findings": []}
```
````

Approved with minor notes (1-2 minor findings — non-blocking):
````
```json-verdict
{"verdict": "APPROVED", "findings": ["[F1] conventions/minor src/utils/helpers.ts:1 -- File name too generic -> Rename to reflect actual contents"]}
```
````

Changes requested:
````
```json-verdict
{"verdict": "CHANGES_REQUESTED", "findings": ["[F1] correctness/major src/auth.ts:42 -- Missing null check -> Add guard clause", "[F2] testing/minor tests/login.test.ts:8 -- Missing edge case -> Add expired session test"]}
```
````

Major findings block approval. 3 or more minor findings also block approval. 1-2 minor findings do not block.
