# Checklist template

Write this to `docs/ref-arch-adherence-checklist.md` in the **target** project at the end of
Step 2, filled in. It is the rubric for Steps 3-5 and the evidence behind the final report.

Every invariant gets a row. `absent` is a legitimate status and the reason the row exists; a blank
row means the analysis has a blind spot, so go back and close it.

---

```markdown
# Reference-architecture adherence checklist

Reference: <path>, commit <sha>
Target: <project name>, branch <branch>
Baseline captured at: <path to the Step 1 baseline>

## Concerns

Which reference concerns this project actually has. Drives which components are in scope.

| Concern              | Present | Evidence / reason                       |
|:---------------------|:--------|:----------------------------------------|
| relational store     |         |                                         |
| cache / read model   |         |                                         |
| trace emission       |         |                                         |
| HTTP surface         |         |                                         |
| admin CLI            |         |                                         |

## Invariants

Status is `present`, `partial` or `absent`. Evidence is a target file path, or `absent`.

| #   | Invariant                                      | Status | Evidence | Action |
|:----|:-----------------------------------------------|:-------|:---------|:-------|
| I1  | three-zone layering                             |        |          |        |
| I2  | `src/` segment and absolute imports             |        |          |        |
| I3  | implicit namespace packages + coverage config   |        |          |        |
| I4  | dependency direction                            |        |          |        |
| I5  | `For*` ports vs `I*` abstractions               |        |          |        |
| I6  | CQRS core replicated in-repo                    |        |          |        |
| I7  | command / query shape                           |        |          |        |
| I8  | handlers and optional telemetry injection       |        |          |        |
| I9  | ExecutionResult across the boundary             |        |          |        |
| I10 | dataclass primitives and DomainError codes      |        |          |        |
| I11 | environment wiring classes                      |        |          |        |
| I12 | test layout as contract (4 sub-rules)           |        |          |        |
| I13 | testcontainers over mocks at boundaries         |        |          |        |
| I14 | two-sided ±3% coverage ratchet                  |        |          |        |
| I15 | uv + ruff + pre-commit + Makefile               |        |          |        |
| I16 | no ORM                                          |        |          |        |

## Service-prefix renames

Instances that must be renamed rather than copied. Each needs its target-side value decided
before Step 3 copies the file.

| Reference value                        | Target value | Done |
|:---------------------------------------|:-------------|:-----|
| `asset.` workflow prefix (BaseHandler)  |              |      |
| `AssetLibraryCommands` / `...Queries`   |              |      |
| `API_SERVICE_NAME` / `CLI_SERVICE_NAME` |              |      |

## AGENTS.md drift

Where the reference doc and the reference code disagree. Code wins; record it so the next run
does not re-derive it.

| AGENTS.md claims | Code actually does |
|:-----------------|:-------------------|

## Legacy patterns to retire

Patterns in the target the reference architecture replaces. Each needs a destination, not a
deletion.

| Legacy pattern | Location | Replaced by | Ported |
|:---------------|:---------|:------------|:-------|

## Components

| Component | In scope | Reason |
|:----------|:---------|:-------|

## Blockers

Paths that could not be ported, and why. Empty is the goal; populated is honest.
```
