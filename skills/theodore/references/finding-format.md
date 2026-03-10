# Finding Format

The structured contract between the Reviewer and Builder agents.

## Format

```
{category}/{severity} {file}:{line} -- {description} -> {action}
```

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

## Examples

```
correctness/major src/auth.ts:42 -- Missing null check on user lookup -> Add guard clause before accessing user.email
testing/minor tests/login.test.ts:8 -- Missing edge case for expired session -> Add test for token expiry scenario
architecture/major src/api/routes.ts:15 -- Business logic in route handler -> Extract to service layer
security/major src/db/query.ts:23 -- String interpolation in SQL query -> Use parameterized query
conventions/minor src/utils/helpers.ts:1 -- File name too generic -> Rename to reflect actual contents
performance/minor src/feed.ts:30 -- Fetching all records without pagination -> Add limit/offset
```

## Verdict Format

The reviewer MUST end their review with exactly one of:

```
VERDICT: APPROVED
```

or

```
VERDICT: CHANGES_REQUESTED

FINDINGS:
{finding 1}
{finding 2}
...
```

Major findings block approval. 3 or more minor findings also block approval. 1-2 minor findings do not block.
