---
name: merge-main
description: "Use when the user asks to merge main (or another base branch) into the current branch, integrate upstream changes, or catch a feature branch up with main. Resolves conflicts, verifies the result compiles and passes format/lint checks, and stops before any commit — the user owns all git history operations."
argument-hint: "[base branch, defaults to main]"
---

# /merge-main

Integrate the base branch into the current working branch, resolve every conflict, and leave a working tree that builds and passes the project's checks. **The user owns the git history: never commit, amend, push, tag, reset, rebase, abort, or switch branches.**

## Rules

- **No commits.** Do not run `git commit`, `git merge --continue`, `git push`, `git rebase`, `git reset --hard`, `git checkout <branch>`, `git clean`, or `git stash drop`. The merge is handed over uncommitted for the user to review and commit.
- **Never `--abort`.** If the merge gets hard, resolve it. If it is genuinely unresolvable without a decision only the user can make, stop and ask — leaving the in-progress state intact.
- **No loss of functionality.** Do not delete, stub, mock, comment out, `@Disabled`/`@Ignore`, or `TODO`-away code, tests, or checks to make the build green. Both sides' behaviour must survive the merge.
- **Not done until it builds.** Compilation and formatting/lint checks must actually pass, verified by running them — not assumed.

## Steps

1. **Establish state.** `git status`, `git log --oneline -10`, current branch name. Confirm the working tree is clean enough to merge into; if there are unrelated uncommitted changes, tell the user and ask before proceeding. Default base branch is `main` unless arguments say otherwise.

2. **Refresh the base.** `git fetch origin` (read-only). Merge from `origin/<base>` so no local branch checkout is needed.

3. **Start the merge without committing:**
   ```
   git merge --no-commit --no-ff origin/main
   ```
   A clean merge still stops uncommitted — that is intended. Conflicts are expected; continue to step 4.

4. **Resolve each conflict from primary sources.** For every conflicting file: read both sides, and use `git log`/`git show` on each side's commits to understand *why* each change was made. Preserve both intents. Where they are truly incompatible, keep the one matching the merge's goal (usually: base branch's structural/API changes + this branch's feature behaviour) and say so in the summary. Do not invent new behaviour to paper over a conflict.

5. **Sweep for semantic conflicts.** A textually clean merge can still break: renamed methods/classes on one side used by the other, changed signatures, moved packages, altered config keys, new abstract members. Grep for the symbols each side touched and fix the call sites.

6. **Run the project's real checks**, in this order, fixing what the merge broke after each:
   - **Format:** e.g. `mvn spotless:apply` then `mvn spotless:check` (Maven + Spotless), `./gradlew spotlessApply`, `npm run format`.
   - **Compile + tests:** e.g. `mvn clean install`, `./gradlew build`, `npm run build && npm test`.
   - **Static analysis:** e.g. `mvn pmd:check`, lint tasks.

   Discover the actual commands from the build file and the CI workflow (`.github/workflows/*.yml`) rather than guessing. Run the same gates CI runs. Iterate until every one passes; a failing check means the merge is not finished.

7. **Verify it runs.** Beyond compiling, sanity-check that the merged application/library still works as before — run the test suite in full, and any smoke command the project provides.

8. **Hand over, uncommitted.** Report:
   - files that conflicted and how each was resolved,
   - any trade-off where one side's behaviour was chosen over the other,
   - semantic fixes made beyond the conflict markers,
   - the exact check commands run and their results,
   - the merge state waiting for the user (`git status` summary) and the fact that nothing was committed.
