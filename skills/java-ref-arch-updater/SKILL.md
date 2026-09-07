---
name: java-ref-arch-updater
description: Refactor a Java project to adhere to the Caema Java reference architecture (ref-arch-java), introducing the architectural concepts it is missing while preserving existing behavior. Use when the user asks to align, migrate, or catch a Java service up to the reference architecture, to adopt the shared com.caema.commons CQRS/telemetry/validation building blocks, or to audit a project's adherence to ref-arch-java.
argument-hint: "[path to the reference architecture, defaults to ~/repos/caema/ref-arch-java]"
---

# Java reference-architecture updater

Bring a target Java project into adherence with the reference architecture, introducing the
architectural concepts it lacks while every existing behavior survives.

Two things make this succeed or fail, and both are decided before you edit anything:

- **Invariant vs. instance.** The reference is a working service (`AssetLibrary`), not a template.
  Its hexagonal structure, CQRS engine, naming rules and test layout are **invariants** every
  project adopts. Its `MediaAsset` aggregate, its Redis cache, its Kafka stream and its module
  list are **instances** of those invariants, applicable only where the target has that concern.
  Read [`INVARIANTS.md`](INVARIANTS.md) for the classification. It is the rubric.
- **Baseline.** "Behavior unchanged" is a claim about a comparison, so capture the comparison
  first. A refactor with no recorded starting state cannot prove anything at the end.

The reference lives at `$1`, defaulting to `~/repos/caema/ref-arch-java`. Read it; never write to it.

## Step 0 — Preconditions

Every one of these blocks the work. Check them before touching a file, because each failure is
cheap now and expensive after 60 files have moved.

1. **Reference present.** The path resolves and holds `README.md`, `pom.xml` and `tests/README.md`.
   There is no `AGENTS.md`; the two READMEs are the whole prose corpus.
2. **Target is Maven.** A root `pom.xml` exists. If the target builds with Gradle or is not Java,
   stop and report that this skill does not apply.
3. **CodeArtifact reachable.** The shared building blocks resolve from a private registry, so
   run the reference's own helper: `<reference>/.github/scripts/codeartifact-settings.sh`. It
   writes `~/.m2/settings.xml`. Confirm the `<server><id>` it wrote equals the `<repository><id>`
   in the reference root `pom.xml`; a mismatch resolves unauthenticated and CodeArtifact answers
   `401`. Tokens last 12 hours, so re-run when resolution starts failing mid-session.
4. **Docker running.** `docker info` succeeds. The integration suite drives Testcontainers, and
   Step 5's gate includes it.
5. **JDK.** The reference's `.java-version` and `<maven.compiler.release>` set the floor, enforced
   by `maven-enforcer-plugin`. Report a mismatch rather than lowering the floor.
6. **Clean tree.** `git status` is clean, and you are on a working branch, not the default branch.

## Step 1 — Baseline

Record the starting state to a file outside the repo tree, and keep it for Step 5.

- Run the target's existing verification exactly as it stands today. Save full output.
- Record the per-module test count and the pass/fail of each test.
- When the target is **already red**, record precisely which tests fail. Those stay failing and
  named in your final report; a pre-existing failure is not yours to silently fix, and not yours
  to be blamed for.

Completion criterion: a saved baseline naming every test and its result. Not "the build works".

## Step 2 — Exhaustive granular analysis, and the checklist

Understanding must be micro-detailed; a blind spot here becomes a wrong invariant later.

1. Read the reference `README.md` in full, then `tests/README.md` in full.
2. Read every `.java` file in the reference, module by module, in dependency order:
   `domain` → `adapters/*` → `deployments/*` → `tests`. Also read the root `pom.xml`, each module
   `pom.xml`, `pmd-ruleset.xml`, `tests/expected_coverage.json`, and `.githooks/`.
   *(Optional fast path, where parallel subagents are available: fan the per-module reads out and
   merge the findings. The reads are independent. Serial reading reaches the same place.)*
3. Map, against [`INVARIANTS.md`](INVARIANTS.md): package topology and module boundaries; the
   CQRS and domain-primitive rules; naming conventions; permitted dependency direction; and the
   structures present in the reference that are **absent** in the target.
4. Decide, for each reference concern, whether the target **has** that concern. A target with no
   cache needs no cache adapter, and its absence is not a finding.

Write the result to `docs/ref-arch-adherence-checklist.md` in the target, from
[`CHECKLIST-TEMPLATE.md`](CHECKLIST-TEMPLATE.md). This file, not your context, is the rubric for
Steps 3-5: a long refactor outlives what you can hold.

Completion criterion: every invariant in `INVARIANTS.md` carries a status of `present`, `partial`
or `absent` plus evidence (a target file path, or `absent`); every reference module is marked
applicable or not-applicable with its reason.

## Step 3 — Foundational definitions

Establish the foundation before porting logic onto it. The shared building blocks are **consumed,
never forked**: `com.caema.commons.*` is shared code, and a local copy of it is the specific
failure this step exists to prevent.

Copy real values out of the reference `pom.xml` rather than typing coordinates from memory:

1. Root `<properties>`: the `codeartifact.*` block and the pinned commons version.
2. Root `<repositories>`: the CodeArtifact repository. A `<repositories>` entry, so it is additive
   and everything else still resolves from Maven Central.
3. Root `<dependencyManagement>`: the `com.caema.commons:*` artifacts the target needs, pinned to
   the single version property.
4. **Prove resolution now.** `mvn -q dependency:resolve` must succeed. This is where a `401`
   surfaces; find it here, not after the refactor.
5. Root `<pluginManagement>` and `<plugins>`: enforcer, spotless, compiler, surefire, jacoco, pmd,
   and the git-hooks `exec` execution. Copy `pmd-ruleset.xml` and `.githooks/` across.
6. Create module skeletons for the **applicable** modules only, per the checklist.

The build is green at the end of this step, with business logic untouched.

## Step 4 — Refactor and adopt, module by module

Port the target's code onto the new definitions in dependency order — `domain`, then `adapters`,
then `deployments`, then `tests` — and return the build to green at each boundary. One green
module at a time beats one 60-file diff that compiles never.

For each module: introduce the invariant structures, move the existing logic onto them, and keep
every existing code path reachable and exercised.

**Hard guardrail, because the whole value of the refactor rests on it:** every original code path
arrives fully wired on the other side. Reaching green by commenting out a failing call, mocking a
collaborator, or stubbing a method body is a failed run, not a partial one. When a path genuinely
cannot be ported, stop and report it as a blocker with its reason; do not route around it.

Migrate the tests **last**. The reference splits `src/unit/java` from `src/integration/java`
instead of `src/test/java`, so moving them relocates the safety net that has been proving the
refactor. Domain, adapters and deployments are green first; the test layout moves after.

## Step 5 — Verification

The bar is the reference's own command, passing end to end from a clean tree:

```bash
mvn spotless:apply && mvn pmd:check && mvn clean install
```

`mvn clean install` runs spotless `check`, PMD `check`, the unit and Testcontainers integration
suites, and the coverage gate. All of it counts.

The **coverage gate is two-sided**: `tests/expected_coverage.json` declares a threshold per module,
an `Overall`, and a shared `tolerance`, and coverage that lands more than the tolerance *above* its
expectation fails the build just as a shortfall does. Module keys match the JaCoCo `GROUP` column,
so they name real Maven modules. Re-baseline only after the suite is green, from measured values,
ratcheting up. A threshold lowered to make a build pass is a failed run.

Then compare against the Step 1 baseline: every test that passed then passes now, no test was
deleted or disabled, and any test that fails now failed then and is named as pre-existing.

## Report

Close with: invariants moved `absent` → `present`; concerns marked not-applicable and why; the
coverage thresholds set and what they were measured at; and every blocker you stopped on rather
than routed around.
