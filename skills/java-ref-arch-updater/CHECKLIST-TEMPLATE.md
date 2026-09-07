# Checklist template

Write this to `docs/ref-arch-adherence-checklist.md` in the **target** project at the end of
Step 2, filled in. It is the rubric for Steps 3-5 and the evidence behind the final report.

Every invariant gets a row. `absent` is a legitimate status and the reason the row exists; a row
left blank means the analysis has a blind spot, so go back and close it.

---

```markdown
# Reference-architecture adherence checklist

Reference: <path>, commit <sha>
Target: <artifactId>, branch <branch>
Baseline captured at: <path to the Step 1 baseline>

## Concerns

Which reference concerns this project actually has. Drives which modules are in scope.

| Concern              | Present | Evidence / reason                       |
|:---------------------|:--------|:----------------------------------------|
| relational store     |         |                                         |
| cache / read model   |         |                                         |
| event publishing     |         |                                         |
| stream processing    |         |                                         |
| HTTP surface         |         |                                         |
| admin CLI            |         |                                         |
| protobuf             |         |                                         |

## Invariants

Status is `present`, `partial` or `absent`. Evidence is a target file path, or `absent`.

| #   | Invariant                                | Status | Evidence | Action |
|:----|:-----------------------------------------|:-------|:---------|:-------|
| I1  | module topology                          |        |          |        |
| I2  | dependency direction                     |        |          |        |
| I3  | `For*` ports vs `I*` abstractions        |        |          |        |
| I4  | CQRS consumed from commons, not forked   |        |          |        |
| I5  | domain package topology                  |        |          |        |
| I6  | command / query shape                    |        |          |        |
| I7  | environment wiring classes               |        |          |        |
| I8  | domain primitives are records            |        |          |        |
| I9  | validation binding                       |        |          |        |
| I10 | domain error codes                       |        |          |        |
| I11 | CodeArtifact wiring                      |        |          |        |
| I12 | build and quality plugins                |        |          |        |
| I13 | unit / integration test layout           |        |          |        |
| I14 | two-sided coverage gate                  |        |          |        |
| I15 | commons contract tests                   |        |          |        |

## Legacy patterns to retire

Patterns in the target that the reference architecture replaces. Each needs a destination, not a
deletion.

| Legacy pattern | Location | Replaced by | Ported |
|:---------------|:---------|:------------|:-------|

## Modules

| Module | In scope | Reason |
|:-------|:---------|:-------|

## Blockers

Paths that could not be ported, and why. Empty is the goal; populated is honest.
```
