---
name: python-ref-arch-updater
description: Refactor a Python project to adhere to the Caema Python reference architecture (ref-arch-python), introducing the architectural concepts it is missing while preserving existing behavior. Use when the user asks to align, migrate, or catch a Python service up to the reference architecture, to adopt its hexagonal CQRS core, or to audit a project's adherence to ref-arch-python.
argument-hint: "[path to the reference architecture, defaults to ~/repos/caema/ref-arch-python]"
---

# Python reference-architecture updater

Bring a target Python project into adherence with the reference architecture, introducing the
architectural concepts it lacks while every existing behavior survives.

Two things decide the outcome, and both are settled before you edit anything:

- **Invariant vs. instance.** The reference is a working service (`asset-library`), not a template.
  Its hexagonal layering, CQRS core, naming rules, namespace-package layout and test contract are
  **invariants** every project adopts. Its `MediaAsset`, its Redis cache, its FastAPI surface and
  its `asset.` telemetry prefix are **instances**, applicable only where the target has that
  concern. Read [`INVARIANTS.md`](INVARIANTS.md). It is the rubric.
- **Baseline.** "Behavior unchanged" is a claim about a comparison, so capture the comparison
  before the first edit.

The reference lives at `$1`, defaulting to `~/repos/caema/ref-arch-python`. Read it; never write to it.

**Python has no compiler**, so a broken module stays silent until something imports it — and this
architecture's near-total absence of `__init__.py` means plenty is never imported during a partial
run. Ruff passing is not evidence the code loads. Step 5 imports every module explicitly.

## Step 0 — Preconditions

Each of these blocks the work, and each is cheap now against expensive later.

1. **Reference present.** The path resolves and holds `README.md`, `AGENTS.md`, `Makefile` and
   `pyproject.toml`. `AGENTS.md` is the authoritative guide here, and it is long; read all of it.
2. **Target is a `uv` Python project.** `pyproject.toml` exists. Report and stop if the target is
   Poetry, pip-tools or setuptools-only rather than silently converting its packaging.
3. **Python floor.** The reference requires `>=3.13` and uses PEP 695 generic syntax
   (`class ICommand[U, T]`), which is a hard parse error below it. Report a mismatch; do not
   rewrite the generics downward.
4. **`uv` installed**, and `uv sync --all-groups` succeeds in the target.
5. **Docker running.** `docker info` succeeds. The integration suite and the coverage gate both
   drive testcontainers.
6. **Clean tree.** `git status` is clean, and you are on a working branch, not the default branch.

## Step 1 — Baseline

Record the starting state to a file outside the repo tree, and keep it for Step 5.

- Run the target's existing checks and full suite exactly as they stand. Save the output.
- Record per-test results, and the current coverage percentages per layer if the target measures them.
- When the target is **already red**, record precisely which tests fail. Those stay failing and
  named as pre-existing in your final report — not silently fixed, and not blamed on this work.

Completion criterion: a saved baseline naming every test and its result.

## Step 2 — Exhaustive granular analysis, and the checklist

1. Read `AGENTS.md` in full, then `README.md`, then `Makefile`, `pyproject.toml`,
   `.pre-commit-config.yaml` and `.github/workflows/ci.yml`.
2. Read every `.py` file in the reference, layer by layer: `domain/` → `adapters/` →
   `deployments/` → `tests/`. Include `tests/build/coverage_validator.py` and
   `tests/build/expected_coverage.json`.
   *(Optional fast path, where parallel subagents are available: fan the per-layer reads out and
   merge. The reads are independent; serial reading reaches the same place.)*
3. **Where `AGENTS.md` and the code disagree, the code is the truth.** Two known drifts: the doc
   places `DomainError` under `cqrs/execution_result/` when it lives at `domain/src/domain_error.py`,
   and it places `ForUpdatingAssets` under `cqrs/ports/` when the asset ports live at
   `domain/src/assets/ports/`. Expect more, and record each one you find.
4. Map, against [`INVARIANTS.md`](INVARIANTS.md): package topology and layer boundaries; the CQRS
   and domain-primitive rules; naming conventions; permitted dependency direction; and the
   structures present in the reference and **absent** in the target.
5. Decide, per reference concern, whether the target **has** that concern. A target with no cache
   needs no cache adapter, and its absence is not a finding.

Write the result to `docs/ref-arch-adherence-checklist.md` in the target, from
[`CHECKLIST-TEMPLATE.md`](CHECKLIST-TEMPLATE.md). The file, not your context, is the rubric for
Steps 3-5: a long refactor outlives what you can hold.

Completion criterion: every invariant carries a status of `present`, `partial` or `absent` plus
evidence (a target file path, or `absent`); every reference component is applicable or not, with
its reason.

## Step 3 — Foundational definitions

Unlike the Java sibling, **the CQRS core lives in this repository**. There is no shared package and
no private registry: `domain/src/cqrs/` is source you replicate into the target. So this step is
genuine copying, and it is the one place the instruction "introduce, replicate and wire up" is
literally right.

1. Replicate `domain/src/cqrs/` — `base_handler.py`, `commands/`, `queries/`, `execution_result/`,
   `ports/` and `ports/tracing/` — plus `domain/src/domain_error.py`.
2. **Rename the service prefix as you copy.** `BaseHandler._handle_execution` builds its workflow
   name as `f"asset.{self.handler_type}"`. That `asset.` is this service's namespace, not an
   invariant; carried over verbatim it mislabels every span the target emits.
3. Replicate the validation trio: `abstract_validator.py`, `domain_validation_utils.py`, and a
   target-specific `<aggregate>_validator.py`.
4. Align `pyproject.toml`: the ruff `lint.select` set, `lint.isort.known-first-party`, the format
   block, the pytest `asyncio_*_loop_scope` and markers, and both coverage blocks.
   **Copy the coverage config exactly**, including `include_namespace_packages = true` — without
   it, untested files vanish from the report instead of landing at 0%, inflating every bucket.
5. Replicate the `Makefile` targets and `.pre-commit-config.yaml`.

`make lint` passes at the end of this step, with business logic untouched.

## Step 4 — Refactor and adopt, layer by layer

Port the target's code onto the new definitions in dependency order — `domain`, then `adapters`,
then `deployments`, then `tests` — returning to green at each boundary. One green layer at a time
beats one 60-file diff that never runs.

For each layer: introduce the invariant structures, move the existing logic onto them, and keep
every existing code path reachable and exercised.

**Hard guardrail, because the whole value of the refactor rests on it:** every original code path
arrives fully wired on the other side. Reaching green by commenting out a failing call, mocking a
collaborator, or leaving a `pass`/`NotImplementedError` body is a failed run, not a partial one.
Where a path genuinely cannot be ported, stop and report it as a blocker with its reason.

Migrate the tests **last**, into the path-decides-the-contract layout: `tests/unit/` mirroring the
source tree, `tests/integration/` grouped by provisioned infrastructure, `tests/build/` for the
gate. Moving them relocates the safety net that has been proving the refactor, so domain, adapters
and deployments are green first.

## Step 5 — Verification

The repo's own aggregate target is the bar, and it is `make verify` — `lint`, then `fix`, then
`format`, then `coverage`:

```bash
make verify
```

Order matters and is easy to get backwards: `make fix` runs `ruff check --fix --unsafe-fixes`,
which **rewrites code**, so formatting comes after it. Running `format` before `fix` leaves the
tree unformatted. `make test` is not the gate either — it skips coverage, while CI runs
`make coverage`.

Then three checks the gate alone will not give you:

1. **Import every module.** Ruff parses; it does not execute. Import each module under `domain/`,
   `adapters/` and `deployments/` and confirm each loads. This is the Python stand-in for
   "it compiles", and the namespace-package layout is exactly what hides an unimported broken file.
2. **Clean tree.** `make verify` mutates via `fix` and `format`. Re-run it and confirm it produces
   no further diff, so CI's non-mutating `ruff format --check` will agree.
3. **Baseline diff.** Every test that passed in Step 1 passes now, none was deleted or disabled,
   and any failure now also failed then and is named as pre-existing.

The **coverage gate is a two-sided ratchet at ±3%**, enforced by `tests/build/coverage_validator.py`
over four fixed buckets — `domain`, `adapters`, `deployments`, `Overall`. Rising more than 3% above
baseline fails exactly as a drop does, so a refactor that adds tests trips it: the reference's
`deployments` baseline sits at 45.5%, meaning 48.6% is a build failure. Re-baseline by running
`make coverage`, reading the actual percentages off the validator table, and writing those into
`tests/build/expected_coverage.json` in the same change. Widening the band is a failed run.

## Report

Close with: invariants moved `absent` → `present`; concerns marked not-applicable and why; the
coverage numbers written and what they were measured at; every `AGENTS.md`-to-code drift found;
and every blocker you stopped on rather than routed around.
