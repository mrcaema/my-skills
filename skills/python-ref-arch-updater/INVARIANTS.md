# Invariants and instances

The reference is a working service, so every observation in it is one of two things. Classify
before you copy.

- An **invariant** is a structural rule the reference *demonstrates*. Every project adopts it.
  Its absence in the target is a finding.
- An **instance** is that rule applied to the asset domain. A target adopts it only where it has
  the same concern. Its absence is a finding only when the concern exists.

Copying an instance the target has no concern for produces a dead module and a contrived
abstraction. Skipping an invariant produces a project that only looks aligned.

## Invariants

### I1. Three-zone layering

`domain/`, `adapters/`, `deployments/` — and the zone decides what may live there:

| Zone           | Holds                                                                    |
|:---------------|:--------------------------------------------------------------------------|
| `domain/`      | pure business logic, the CQRS core, port definitions. **No** IO libraries. |
| `adapters/`    | one component per technology, implementing domain ports.                   |
| `deployments/` | one component per runnable entry point; wires adapters into the domain.    |
| `tests/`       | the suite, plus the coverage gate under `tests/build/`.                    |

`domain/` contains no HTTP framework, no database driver, and no telemetry vendor. That rule is
the architecture; everything else is detail.

### I2. The `src/` segment

Every component nests its code under `src/`: `domain/src/`, `adapters/postgres/src/`,
`deployments/web_api/src/`. Imports are absolute from the repo root and **include the segment** —
`from domain.src.cqrs.commands.i_command import ICommand`. Tests run with `PYTHONPATH=.`, set by
the `Makefile` and by `pythonpath = "."` in `pyproject.toml`.

### I3. Implicit namespace packages

The source layers carry almost no `__init__.py` — one in the entire tree. This is deliberate and
load-bearing, not an oversight: `[tool.coverage.run] source` plus
`[tool.coverage.report] include_namespace_packages = true` are what make coverage.py scan those
directories for never-imported files. Remove either and untested files vanish from the report
instead of landing at 0%, inflating every bucket. Adding `__init__.py` files "for tidiness"
silently changes what coverage measures.

### I4. Dependency direction

Outer depends on inner, never the reverse. `domain` imports nothing from `adapters` or
`deployments`. `adapters` import `domain`. `deployments` import `domain` and the adapters they
wire. A `domain` module importing an adapter inverts the hexagon and is the single most important
violation to catch.

### I5. Naming: ports vs. internal abstractions

The prefix carries meaning, and the two are not interchangeable:

- **`For*`** is reserved for **ports** — boundary interfaces, driving or driven
  (`ForUpdatingAssets`, `ForQueryingAssets`, `ForManagingAssetCache`, `ForRecordingTelemetry`,
  `ForHandlingCommands`).
- **`I*`, or no prefix**, marks **internal abstractions and design patterns** — behavioral
  orchestration with no physical IO boundary (`ICommand`, `IQuery`, `ISpan`, `ITracer`, `IScope`,
  `ISpanContext`).

Files are `snake_case` of the class they hold, one class per file: `i_command.py` → `ICommand`,
`for_updating_assets.py` → `ForUpdatingAssets`.

### I6. The CQRS core lives in the repository

Unlike the Java reference, there is no shared distribution and no private registry. `domain/src/cqrs/`
is source, replicated per project:

```
domain/src/cqrs/
    base_handler.py                 BaseHandler — the shared execution + telemetry orchestrator
    commands/                       ICommand, ForHandlingCommands, CommandHandler
    queries/                        IQuery, ForHandlingQueries, QueryHandler
    execution_result/               ExecutionResult, Successful/Failed/FatalExecution
    ports/for_recording_telemetry.py
    ports/tracing/                  ITracer, ISpan, IScope, ISpanContext, SpanCreationSettings
domain/src/domain_error.py          DomainError
```

`ports/tracing/` are pure ABCs modeled on Datadog.Trace but vendor-agnostic, and they **never**
import a vendor library. That purity is what lets the domain stay ignorant of the tracer.

### I7. Command and query shape

A command subclasses `ICommand[TInput, TOutput]` (PEP 695 generics), takes its ports as
constructor parameters, and exposes exactly `async def execute_async(self, input_data)` returning
`ExecutionResult[TOutput]`. It validates first and short-circuits with `ExecutionResult.failed(...)`
before any port call. Queries mirror this with `IQuery`.

### I8. Handlers and telemetry

`CommandHandler(ForHandlingCommands, BaseHandler)` and `QueryHandler` take an **optional**
`for_recording_telemetry: ForRecordingTelemetry | None` by constructor injection and delegate to
`BaseHandler._handle_execution`. When telemetry is present the run is wrapped in
`encapsulate_business_workflow`, and `increment_business_event`,
`record_business_measurement`, `record_anomaly` and `enrich_current_workflow` fire around it. When
absent, execution proceeds unwrapped and warns once. Every exception becomes
`ExecutionResult.fatal(e)` rather than propagating.

The workflow-name prefix in `BaseHandler` (`f"asset.{self.handler_type}"`) is **service-specific**;
see the instance table.

### I9. Results, never exceptions, across the boundary

Commands and queries return `ExecutionResult` — `SuccessfulExecution`, `FailedExecution` (domain
rule violations) or `FatalExecution` (a crash). The domain raises no HTTP exception because it
knows nothing of HTTP. Every deployment endpoint routes its result through one uniform
`handle_result()` wrapper, which maps success to a DTO, failures to the error list, and fatals to
an error body.

`ExecutionResult` exposes `success` / `failed` / `fatal` constructors, `handle_func` / `handle_proc`
visitors, and `is_success` / `get_value` / `get_domain_errors` accessors. Its constructors import
their concrete subclasses **inside the method body** to break the circular import; keep that shape.

### I10. Domain primitives and errors

Aggregates, entities, value objects and events are `@dataclass`. `DomainError` is a dataclass of
`code`, `message` and an optional `parameters` tuple, with `get_formatted_message()` substituting
`{}` placeholders. Codes are a stable per-aggregate prefix plus a zero-padded sequence
(`ASSET-001`).

### I11. Environment wiring classes

Per bounded context, in `environment/`: `<Context>Commands` and `<Context>Queries`. Each takes the
ports as constructor parameters, instantiates every command or query **once** into an attribute,
and exposes each through a no-arg accessor method. Deployments hold the instance and call the
accessor; they never construct a command directly.

### I12. Test layout is a contract

The directory a test lives in *is* its contract — tests are split by what they need to run, not by
what they assert:

```
tests/
    conftest.py        tags every test by path. Imports no infrastructure.
    unit/              mirrors the source tree. No Docker, milliseconds.
        tooling/       tests for build tooling
        test_*.py      genuinely cross-layer tests sit at this root
    integration/       grouped by the infrastructure it provisions
        conftest.py    fixtures shared across infrastructure groups
    build/             coverage validator and baseline, out of the test tree proper
```

Four rules follow, and each has bitten someone:

- **Markers are derived, never written.** The root `conftest.py` sets `unit` / `integration` from
  the file path in `pytest_collection_modifyitems`, so a marker cannot drift from a location. Both
  are registered in `pyproject.toml`. Hand-writing `@pytest.mark.unit` defeats it.
- **Root conftest purity.** It loads for the fast suite too, so importing adapters or
  testcontainers there makes `make test-unit` pay for Docker it never uses.
- **No global `TracerProvider` in a shared fixture.** It can be set only once per process, so the
  first test to claim it decides `service.name` for every later test and trace assertions start
  depending on collection order. Fixtures hand out an `OpenTelemetryConfig`; each consumer owns its
  provider via `create_provider()`.
- **Order independence.** Directory names decide collection order, so any coupling through
  process-global state breaks the moment a directory is added or renamed.

### I13. Real infrastructure, not mocks, at the boundaries

Integration and end-to-end tests use physical containers via `testcontainers`, never mocks, so the
boundaries (database, cache, collector) are exercised as they actually behave. Prefer structured
wait strategies over the deprecated `@wait_container_is_ready`. `asyncio_default_test_loop_scope`
and `asyncio_default_fixture_loop_scope` are both `"session"`, or container lifespans detach from
async fixture boundaries. `TESTCONTAINERS_RYUK_DISABLED=true` is set for suites that boot
containers, because the reaper's own port mapping fails setup often enough to be a worse risk than
the leak it prevents; fixtures stop their containers explicitly instead.

### I14. Coverage is a two-sided ratchet

`tests/build/coverage_validator.py` compares four fixed buckets — `domain`, `adapters`,
`deployments`, `Overall` — against `tests/build/expected_coverage.json` and fails on a drift of
more than **±3%**. Below is a regression; **above also fails**, forcing a real gain to be declared
by updating the baseline so the number in the repo reflects reality. The band is hardcoded in the
validator, not the JSON. Re-baseline from measured values in the same change that moved them, and
never widen the band to pass. The validator itself is under test in
`tests/unit/tooling/test_coverage_validator.py`; a policy change updates that test in the same commit.

### I15. Toolchain

`uv` exclusively for dependency and run management. `ruff` for both lint and format — no black, no
isort, no flake8 — with the reference's `lint.select` set and `known-first-party` naming the three
layers. `pre-commit` runs `ruff --fix` and `ruff-format`. The `Makefile` is the interface:
`lint`, `fix`, `format`, `test`, `test-unit`, `test-integration`, `coverage`, and `verify` as the
aggregate. CI runs `ruff check`, `ruff format --check` and `make coverage`.

### I16. No ORM

Raw async driver bindings mapped into explicit repositories, to keep abstraction leaks out. Use
dataclasses, or pydantic inside DTOs, for schema enforcement.

## Instances

Adopt each only where the target has the concern. Absent concern, absent component — and that is
adherence, not drift.

| Instance in the reference                                      | Adopt when the target...                       |
|:---------------------------------------------------------------|:-----------------------------------------------|
| `MediaAsset`, `AssetAnalyzed`, `ASSET-###` codes                 | never — the target has its own aggregates       |
| the `asset.` workflow-name prefix in `BaseHandler`               | never — rename to the target's own namespace    |
| `AssetLibraryCommands` / `AssetLibraryQueries` naming            | rename to the target's context                  |
| `adapters/postgres/` (asyncpg)                                   | has relational persistence                      |
| `adapters/redis/`                                                | has a cache or materialized read model          |
| `adapters/open_telemetry/`                                       | emits traces — the ports stay either way        |
| `deployments/web_api/` (FastAPI, uvicorn, `app_state` lifespan)  | exposes HTTP                                    |
| `deployments/cli/` (Typer)                                       | has an administrative CLI                       |
| `AssetDto` shapes in `web_api` and `redis`                       | never — DTOs follow the target's own aggregates |
| `API_SERVICE_NAME` / `CLI_SERVICE_NAME` env names                | rename per the target's deployments             |
| the Jaeger integration group                                     | asserts on exported traces                      |
| the numbers in `expected_coverage.json`                          | never — measure the target's own, then ratchet  |
| project name `asset-library` in `pyproject.toml`                 | never — the target keeps its identity           |
