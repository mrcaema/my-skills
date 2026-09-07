# my-skills

Canonical, machine-independent home for the agent skills shared by **Claude Code** and
**Antigravity (Gemini)** — on Linux and macOS. Everything lives once in `skills/`;
`sync-skills.sh` installs it into the two places the tools actually read.

```
~/.agents/skills/<name>/SKILL.md   canonical source — edit here, nowhere else
~/.claude/skills/<name>            relative symlink -> ../../.agents/skills/<name>
~/.gemini/config/skills/<name>     real copy (Antigravity does not follow symlinks reliably)
                                   older builds read ~/.gemini/skills; the script detects which
```

Repo: <https://github.com/mrcaema/my-skills>

`.skill-lock.json` is the registry of skills installed by the community `skills` CLI
(`orca skills install/update` writes it too). It is committed so every machine agrees on
provenance and versions.

## Set up a new machine (Linux or macOS)

```bash
git clone git@github.com:mrcaema/my-skills.git ~/.agents
~/.agents/sync-skills.sh --adopt --prune
```

- `--adopt` folds any skill directory already sitting in `~/.claude/skills` or
  `~/.gemini/skills` into `skills/` before linking it back, so a machine that was set up by
  hand does not end up with two divergent copies. Anything it promotes shows up as a new
  directory in `git status` — review before committing.
- `--prune` removes symlinks and mirror copies left over from skills that no longer exist.
- `-n` dry-runs the whole thing.

If that machine already has a `~/.agents` directory, `git clone` will refuse to write into
it. Adopt it instead of deleting it:

```bash
cd ~/.agents
git init -b main
git remote add origin git@github.com:mrcaema/my-skills.git
git fetch origin
git reset origin/main    # HEAD and index = remote; your local files are left untouched
git status               # every local difference shows up here — keep it or `git checkout -- <path>`
./sync-skills.sh --adopt --prune
```

The script is written for bash 3.2 and BSD userland, so **stock macOS needs nothing
installed** — no Homebrew bash, no GNU coreutils. It uses `rsync` when present and falls
back to `cp -R`.

## Antigravity's skills directory

Antigravity has moved this location, so it differs **by build, not by operating system** —
do not assume one path for Linux and another for macOS. Current builds read
`~/.gemini/config/skills`; older ones read `~/.gemini/skills`. The script resolves it:

1. `GEMINI_SKILLS_DIR` if set — always wins.
2. An existing `~/.gemini/skills`, so a machine already synced that way keeps working.
3. `~/.gemini/config/skills` when a `~/.gemini/config` directory exists.

Every run prints the directory it chose (`Antigravity: …`), and warns if both candidates
exist — that means one is a leftover nothing reads.

To find out which one your build wants, ask Antigravity's own bundled `migrate-workflows`
skill, which documents the global skills path:

```bash
grep -o "\.gemini/[a-z/]*skills" ~/.gemini/*/builtin/skills/migrate-workflows/SKILL.md | sort -u
ls -d ~/.gemini/skills ~/.gemini/config/skills 2>/dev/null   # which ones actually exist
```

**Upgrading a machine that was synced to the old path.** Rule 2 keeps choosing the stale
`~/.gemini/skills`, and it does so silently — the mirror reports success into a directory
Antigravity no longer reads. Once the grep above says `config/skills`, retire the old copy:

```bash
rm -rf ~/.gemini/skills
~/.agents/sync-skills.sh          # now resolves to ~/.gemini/config/skills
```

Nothing is lost: `~/.agents/skills` is the canonical source and the mirror is only a
snapshot of it. To force some third location instead:

```bash
GEMINI_SKILLS_DIR="$HOME/some/other/path" ~/.agents/sync-skills.sh
```

`AGENTS_DIR` and `CLAUDE_SKILLS_DIR` work the same way.

## Day to day

```bash
cd ~/.agents && git pull && ./sync-skills.sh   # take the other machine's changes
# edit skills/<name>/SKILL.md ...
./sync-skills.sh                                # push the edit into the Antigravity copy
git add -A && git commit && git push            # share it
```

Claude Code needs no re-sync after an edit — it reads through the symlink. The Antigravity
copy is a snapshot, so **`./sync-skills.sh` after every edit** is what keeps the two sides
from drifting apart.

`gemini-exclude.txt` lists skills deliberately not mirrored to Antigravity. It is currently
empty — every skill goes to both agents.

## House rules

- **No absolute paths inside a skill.** `/home/you/...` breaks the moment the repo lands on
  a Mac, where home is `/Users/you`. Keep skill contents path-relative or `$HOME`-relative.
- **No secrets, no client-identifying content.** This repo is public.
- Skill directory names must not collide case-insensitively — macOS filesystems are
  case-insensitive by default and would merge them.
