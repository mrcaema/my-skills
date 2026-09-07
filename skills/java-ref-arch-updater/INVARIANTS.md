# Invariants and instances

The reference is a working service, so every observation in it is one of two things. Classify
before you copy.

- An **invariant** is a structural rule the reference *demonstrates*. Every project adopts it.
  Its absence in the target is a finding.
- An **instance** is that rule applied to the asset domain. A target adopts it only where it has
  the same concern. Its absence is a finding only when the concern exists.

Copying an instance the target has no concern for produces an empty module and a contrived
abstraction. Skipping an invariant produces a project that only looks aligned.

## Invariants

### I1. Module topology

Four kinds of module, and the kind decides what may live there:

| Kind          | Holds                                                              |
|:--------------|:-------------------------------------------------------------------|
| `domain`      | business logic, domain models, port definitions. One module.        |
| `adapters/*`  | one module per external technology, implementing domain ports.      |
| `deployments/*` | one module per runnable entry point.                              |
| `tests`       | the whole suite, and the coverage gate. One module.                 |

### I2. Dependency direction

`domain` depends only on the shared commons artifacts and generic libraries. `adapters/*` depend
on `domain`. `deployments/*` depend on `domain` and the adapters they wire. `tests` depends on
everything. A `domain` class importing an adapter or deployment package inverts the hexagon and is
the single most important violation to catch.

### I3. Naming: ports vs. internal abstractions

The prefix carries meaning, and the two are not interchangeable:

- **`For*`** is reserved for **ports** — boundary interfaces, driving or driven
  (`ForUpdatingAssets`, `ForQueryingAssets`, `ForRecordingTelemetry`, `ForHandlingCommands`).
- **`I*`, or no prefix**, marks **internal abstractions and design patterns** — structural or
  behavioral, used for orchestration rather than external I/O (`ICommand`, `IQuery`, `ISpan`,
  `ITracer`).

A `For*` name on a non-boundary interface, or an `I*` name on a port, is a finding.

### I4. CQRS consumed from commons, never forked

The execution engine, telemetry ports, validation bridge and coverage validator are **not** in the
reference repo. They are consumed as `com.caema.commons:*` artifacts, so one fix is a fix
everywhere. A local reimplementation of any of them is the defining violation of this
architecture. The import tells a reader which is which: `com.caema.commons.*` is shared,
`com.caema.<service>.*` is the service.

The surface the reference relies on:

| Package                                    | Provides                                                        |
|:-------------------------------------------|:----------------------------------------------------------------|
| `com.caema.commons.cqrs`                   | `BaseHandler`, `DomainError`                                     |
| `com.caema.commons.cqrs.command`           | `ICommand`, `CommandHandler`, `ForHandlingCommands`, `NoCommandData` |
| `com.caema.commons.cqrs.query`             | `IQuery`, `QueryHandler`, `ForHandlingQueries`, `NoQueryData`    |
| `com.caema.commons.cqrs.executionresult`   | `ExecutionResult`, `SuccessfulExecution`, `FailedExecution`, `FatalExecution` |
| `com.caema.commons.telemetry.ports`        | `ForRecordingTelemetry`, and the tracing ports                   |
| `com.caema.commons.opentelemetry`          | `OpenTelemetryAdapter`, `OpenTelemetryConfig`                    |
| `com.caema.commons.validation`             | `DomainValidationUtils`                                          |
| `com.caema.commons.coverage`               | `CoverageValidator` (test scope)                                 |

### I5. Package topology inside the domain

One package per bounded context. The aggregate sits at its root; the rest is fixed:

```
domain/<context>/
    <Aggregate>.java
    commands/      one class per write operation
    queries/       one class per read operation
    events/        domain events
    ports/         For* boundary interfaces
    validation/    <Aggregate>Validation + <Aggregate>Validator
    environment/   the wiring classes of I7
```

### I6. Command and query shape

A command is a class implementing `ICommand<TInput, TOutput>`, taking its ports as `final`
constructor parameters, and exposing exactly `executeAsync` returning
`CompletableFuture<ExecutionResult<TOutput>>`. It validates first and short-circuits on failure
with `ExecutionResult.failed(...)` before any port call. Queries mirror this with `IQuery`.
Parameters are `final`. Async composition is `CompletableFuture` chaining, not blocking.

### I7. Environment wiring classes

Per bounded context, in `environment/`: `<Context>Commands`, `<Context>Queries` and
`<Context>Telemetry`. The first two take the ports as constructor parameters, instantiate each
command or query **once** into a `final` field, and expose each through a no-arg accessor.
`<Context>Telemetry` supplies the `NAMESPACE` constant the shared telemetry handlers require.
This is where the service binds a generic shared component to its own knowledge — bound locally
rather than pushed upstream.

### I8. Domain primitives are records

Aggregates, entities, value objects and events are `record`s. An aggregate maps to its event
through a `to<Event>()` method on the record itself.

### I9. Validation

A local `<Aggregate>Validation` binds the shared `DomainValidationUtils` bridge to a local
`<Aggregate>Validator`, returning `List<DomainError>`. The validator holds the rules; the
validation class holds the binding.

### I10. Domain error codes

`new DomainError("<AGGREGATE>-NNN", "message with {} placeholder", arg)` — a stable
per-aggregate prefix and a zero-padded sequence, with `{}` placeholders rather than concatenation.

### I11. CodeArtifact wiring

Root `pom.xml` carries the registry coordinates as **discrete properties** (`codeartifact.domain`,
`codeartifact.domain.owner`, `codeartifact.region`, `codeartifact.repository`) with the URL
derived from them, so a fork retargets a single value. The commons version is pinned once in a
property, and the commons artifacts are declared in `<dependencyManagement>` so every module
resolves the same one.

The registry is a **`<repositories>` entry, never a `<mirrors>` entry**: only `com.caema.commons:*`
comes from CodeArtifact, and everything else still resolves from Maven Central. The
`<repository><id>` must equal the `<server><id>` in `~/.m2/settings.xml`, or Maven sends the
request unauthenticated and receives a `401`.

### I12. Build and quality plugins

- `maven-enforcer-plugin` — `requireJavaVersion` at the reference's floor.
- `spotless-maven-plugin` — `palantirJavaFormat`, import order `com,org,java,javax,`,
  `removeUnusedImports`, `formatAnnotations`; `check` bound to `verify`.
- `maven-pmd-plugin` — pinned `pmd-core`/`pmd-java`, ruleset at
  `${maven.multiModuleProjectDirectory}/pmd-ruleset.xml`, `failOnViolation`, `printFailingErrors`;
  `check` bound to `verify`.
- `jacoco-maven-plugin` — `prepare-agent` at the root.
- `exec-maven-plugin` — `git config core.hooksPath .githooks` at `initialize`, `inherited=false`,
  so a clone wires the shared hooks on first build.

### I13. Test module layout

Tests do **not** live in `src/test/java`. `build-helper-maven-plugin` adds two source roots at
`generate-test-sources`:

- `src/unit/java` — fast, isolated, no external infrastructure, milliseconds.
- `src/integration/java` — Testcontainers against real infrastructure.

Each has its own `log4j2.xml` under the matching `src/<kind>/resources`, suppressing external
libraries and Testcontainers to `WARN` so application `INFO` stays readable.

### I14. Coverage gate

`jacoco` `report-aggregate` at `test` produces a unified report; `exec-maven-plugin` runs
`com.caema.commons.coverage.CoverageValidator` at `verify` against `tests/expected_coverage.json`.

That file holds a shared `tolerance` and a `modules` map with an `Overall` plus one entry per
module. The gate is **two-sided**: falling more than the tolerance below expectation fails, and
rising more than the tolerance above it also fails, which forces the threshold to be ratcheted up
rather than left stale. Keys match the JaCoCo `GROUP` column — an exact match first, then a
case-insensitive substring — so they name real Maven modules, not source-tree layers.

### I15. Commons contract tests

`tests/src/unit/java/.../tests/commons/` holds tests against the `com.caema.commons` boundary,
asserting **only what this service actually relies on**. Their purpose is regression detection: a
behavioral change in a future commons release fails here, in CI, rather than in staging. They
leave commons internals to commons.

## Instances

Adopt each only where the target has the concern. Absent concern, absent module — and that is
adherence, not drift.

| Instance in the reference                                          | Adopt when the target...                    |
|:-------------------------------------------------------------------|:--------------------------------------------|
| `MediaAsset`, `AssetCreated`, `ASSET-###` codes                     | never — the target has its own aggregates    |
| `adapters/postgres` (+ HikariCP)                                    | has relational persistence                   |
| `adapters/redis`                                                    | has a cache or materialized read model       |
| `adapters/kafka-producer`                                           | publishes events                             |
| `adapters/protobuf`                                                 | serializes with protobuf                     |
| `deployments/web-api` (Javalin)                                     | exposes HTTP                                 |
| `deployments/kafka-stream` (+ `TelemetryExceptionHandler`, `TELEMETRY_ADAPTER_CONFIG` reflective injection) | processes a stream |
| `deployments/cli`                                                   | has an administrative CLI                    |
| the Kafka → Redis materialized-view read path                       | reads are event-sourced from a write model   |
| `jacoco` `<exclude>` of the generated protobuf package              | generates protobuf sources                   |
| groupId `com.caema.assetlibrary`, artifact `asset-library-parent`   | never — the target keeps its own identity    |
| the specific numbers in `expected_coverage.json`                    | never — measure the target's own, then ratchet |
