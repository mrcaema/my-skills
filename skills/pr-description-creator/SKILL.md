---
name: pr-description-creator
description: Use this skill when asked to write, draft, or generate the description (body) of a pull request. It first builds an interactive HTML explanation of the change by running the explain-diff-html skill, then uses the understanding from that investigation to fill out the repository's own pull request template (falling back to a built-in default template), producing a ready-to-paste PR description. It never performs git operations — the user owns branching, committing, pushing, and PR creation.
---

# Pull Request Description Creator

This skill studies a change deeply, then writes a Pull Request description that
adheres to the repository's standards. **It produces two deliverables, in this
order**:

1.  **An HTML explanation** — produced by running the `explain-diff-html` skill
    over `main...HEAD`, without the user having to ask for it.
2.  **Text** — a PR title and a PR body the user can paste into GitHub (or into
    `gh pr create` themselves).

**The order is the point.** The HTML step is not a bonus artifact bolted on at
the end — it is the analysis pass. Building the explanation forces you to trace
the old and new code paths, find the callers and tests, and work out *why* the
change is shaped the way it is. A description written after that work is
grounded in real understanding; one written straight off the diff is a
restatement of the diff. Do the investigation, then write.

## Scope — read this first

**This skill never runs a git write operation.** It does not branch, stage,
commit, push, create, or update a pull request. It does not call
`gh pr create` / `gh pr edit`. If a branch is missing, changes are uncommitted,
or the branch is unpushed, **say so in the output and let the user decide** —
that is their call, not yours.

Read-only git is expected and encouraged: `git status`, `git diff`, `git log`,
`git show`, `git branch --show-current`, `git remote -v`.

Generating the HTML explanation (step 2) is likewise read-only: it reads the
diff and writes one HTML file **outside the repository**. It is not a git
operation and does not need the user's permission to run — it is part of this
skill's normal output.

## Workflow

1.  **Gather context**: Understand what actually changed before writing a word.
    - `git branch --show-current` — the branch the work sits on.
    - Determine the base branch **locally, without a network round-trip**:
      `git symbolic-ref --short refs/remotes/origin/HEAD` (→ `origin/main`).
      Fall back to `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
      or the repo's docs. Do **not** use `git remote show origin` — it contacts
      the remote, so it is slow and fails outright offline or without auth.
    - `git fetch origin <base>` — refresh the base ref before diffing. A stale
      local base silently drags other people's already-merged commits into your
      diff and your description.
    - `git log --oneline origin/<base>..HEAD` — the commits in this change.
    - `git diff origin/<base>...HEAD --stat` **first**, then read the diff of the
      files that matter. Read the code; do not infer the change from commit
      messages alone. On a large change, do not pull the entire diff into
      context in one shot — sample the significant files and say what you
      sampled.
    - `git status` — note anything uncommitted, so you can flag it. Do **not**
      commit it.
    - **Degenerate cases**: if the current branch *is* the base, or `git log`
      shows no commits ahead of it, there is no PR range. Describe the
      uncommitted work instead and say plainly that is what you did. If there is
      nothing to describe at all, stop and tell the user rather than inventing a
      change.

2.  **Generate the HTML explanation — first, not last**: Before drafting any
    prose, **always** run the `explain-diff-html` skill. Do not ask the user
    whether they want it, and do not defer it to the end.
    - Invoke it with the `Skill` tool under the name `explain-diff-html`.
    - **Scope it to the base branch vs. the current branch** — the base you
      resolved in step 1, not a hardcoded `main`. Pass the range explicitly,
      e.g. `Explain the change on <current-branch> compared to <base>
      (origin/<base>...HEAD).` Say which base you used.
    - If the current branch *is* the base branch, explain the uncommitted or
      most recent changes instead, and say that in your reply.
    - Follow that skill's own rules for the page: single self-contained HTML
      file, no external assets, saved **outside the repository**. Write it to
      the session scratchpad directory if the harness provides one; otherwise
      `/tmp/YYYY-MM-DD-explanation-<slug>.html`.
    - **Carry the findings forward.** When the page is done you know the
      motivation, the prior behaviour, the new mental model, the edge cases and
      the trade-offs. Keep those in hand — every later step draws on them:
      the `## Description` section is the page's summary in miniature, the
      `## Changes Made` bullets follow the page's conceptual grouping, and the
      trade-offs it surfaced are what you flag to the user at the end.
    - If the skill is unavailable or the run fails, say so plainly in your
      reply, fall back to reading the diff and surrounding code yourself, and
      **still deliver the PR description** — a failed HTML step never blocks
      the text deliverable.
    - Do **not** stop here. The page is the input to the description, not a
      substitute for it; the remaining steps still have to run.

3.  **Locate the template**: Find every candidate in one pass rather than
    guessing filenames one at a time — the casing and location both vary, and
    on a case-sensitive filesystem a missed variant reads as "no template":

    ```bash
    find .github docs . -maxdepth 2 -iname '*pull_request_template*' \
      -o -iname '*merge_request_template*' 2>/dev/null | sort -u
    ```

    Prefer matches in this order.
    - `.github/pull_request_template.md` (any casing)
    - `.github/PULL_REQUEST_TEMPLATE/` — a directory of templates
    - `pull_request_template.md` at the root, or under `docs/`
    - `.gitlab/merge_request_templates/` on GitLab-hosted repos
    - If multiple templates exist (e.g. in `.github/PULL_REQUEST_TEMPLATE/`),
      ask the user which one to use, or select the most appropriate one based on
      the context (e.g. `bug_fix.md` vs `feature.md`) and state which you chose.
    - If no template exists in the repository, use the **default template**
      below verbatim as the structure, and say clearly in your reply that the
      repository has no template of its own so this default was used:

      ```markdown
      ## Description

      <!-- Provide a clear summary of what this PR does and why. -->

      ## Type of Change

      - [ ] New feature
      - [ ] Bug fix
      - [ ] Refactoring (no functional changes)
      - [ ] Documentation update
      - [ ] Infrastructure / CI/CD
      - [ ] Performance improvement
      - [ ] Dependency or version bump

      ## Changes Made

      <!-- List the specific changes. Be precise. -->

      -
      -
      -
      ```

      Treat this default exactly as you would a repository template: keep every
      heading in order, strip the `<!-- ... -->` guidance comments from the
      final body, check only the `Type of Change` boxes the diff actually
      supports, and replace the empty `-` placeholders under `## Changes Made`
      with one bullet per real change (add or remove bullets as needed — three
      is a placeholder, not a quota). This default is deliberately
      toolchain-neutral: do not add ecosystem-specific items (a version bump in
      a parent POM, a changeset file, a lockfile refresh) unless this repository
      actually requires them.

4.  **Read the template**: Read the full content of the identified template
    file, including its HTML comments — they are the author's instructions to
    you.

5.  **Draft the description**: Produce a body that strictly follows the
    template's structure, drawing on the understanding you built in step 2.
    - **Headings**: Keep every heading from the template, in the template's
      order. Do not add, drop, or rename sections.
    - **Comments**: Remove the `<!-- ... -->` guidance comments in the final
      body — they are prompts for the author, not part of the description. Keep
      any comment the template explicitly says to keep.
    - **Checklists**: Review each item. Mark with `[x]` only what this change
      actually did. Leave everything else as `[ ]` — never check a box for work
      you have not verified. Prefer keeping non-applicable items unchecked over
      deleting them, for transparency.
    - **Content**: Fill each section with clear, specific summaries grounded in
      the diff you read and the explanation you wrote. Name real files, modules,
      and behaviours; avoid filler like "various improvements". If the page
      identified a motivation, an old-versus-new behaviour, or a trade-off, the
      description should say so too — in a sentence or two rather than a page.
    - **Related issues**: Link issues this PR fixes or relates to (e.g.
      `Fixes #123`) when the branch name, commits, or the user tell you which.
      Never invent an issue number.

6.  **Draft the title**: Propose a PR title alongside the body. Follow
    [Conventional Commits](https://www.conventionalcommits.org/) if the
    repository's existing commit or PR history uses it — check with
    `git log --oneline -20` rather than assuming (e.g. `feat(ui): add new
    button`, `fix(core): resolve crash`). Otherwise match the style actually in
    use.

7.  **Verification status**: The description should be honest about whether the
    change was verified. Discover the repository's own gate rather than assuming
    a toolchain:
    - Read `CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md` / the README — many
      repos state their verification command explicitly, and that statement
      wins over anything you infer.
    - Otherwise infer it from the project: `package.json` scripts
      (`npm run preflight`, `lint`, `test`, `build`), a Maven or Gradle build
      (`mvn clean install`, `./gradlew check`), `Makefile` targets, `cargo test`,
      `go test ./...`, `pytest`, or the steps in `.github/workflows/`.
    - If the user asks you to run it, run it and report the real result. If you
      have not run it, **do not claim it passed** — either leave the relevant
      checklist items unchecked, or note plainly that verification is pending.

8.  **Prepare the text**: Get the finished title and body into a usable shape.
    - Have the title ready on its own line and the body ready for a single
      fenced code block.
    - Write the body to `pr-description.md` **outside the repository** — the
      session scratchpad directory if the harness provides one, otherwise
      `/tmp` — unless the user asks otherwise. Keep the path, so the user can
      run `gh pr create --title "..." --body-file <path>` themselves.
    - Note anything the user still needs to handle: uncommitted changes, an
      unpushed branch, work sitting on `main`, an unverified build, or a missing
      issue link.

9.  **Deliver both**: Close the task with, in this order:
    - the PR title;
    - the PR body in a fenced code block;
    - the path to the `pr-description.md` file;
    - the path to the generated HTML explanation;
    - the short list of anything left for the user to handle.

    The user asked for one thing and gets both artifacts — they should never
    have to run a follow-up command to obtain the HTML.

## Principles

- **Understand before writing**: the HTML explanation comes first because it is
  the research. The description is what you write once you actually know the
  change, not a paraphrase of the diff.
- **Text and explanation, not actions**: your deliverables are a description
  and an HTML explanation of the change. Git and PR creation belong to the user.
- **Both artifacts, every time**: the HTML explanation runs under the hood as
  part of this skill. Never leave it as a suggestion for the user to run, and
  never stop once it exists — the description is the deliverable it serves.
- **Compliance**: never ignore the PR template. It exists for a reason.
- **Grounded**: every claim in the description must come from the diff, the
  commits, the explanation you built, or the user — never from guesswork.
- **Accuracy**: don't check boxes for tasks you haven't done or verified.
- **Completeness**: fill out all relevant sections, and flag the ones you could
  not fill and why.
