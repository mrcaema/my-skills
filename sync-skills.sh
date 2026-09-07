#!/usr/bin/env bash
#
# sync-skills.sh — install the canonical skills in ~/.agents/skills into the
# places Claude Code and Antigravity actually read from.
#
#   ~/.agents/skills/<name>   canonical source (this git repo)
#   ~/.claude/skills/<name>   relative symlink  -> ../../.agents/skills/<name>
#   <antigravity>/<name>      real copy (Antigravity does not follow symlinks reliably)
#                             ~/.gemini/config/skills on newer builds, else ~/.gemini/skills
#
# Idempotent. Portable: Linux (GNU) and macOS (BSD userland, bash 3.2).
# Run it after every `git pull`, and after editing any skill.

set -eu

AGENTS_DIR="${AGENTS_DIR:-$HOME/.agents}"
SKILLS_DIR="$AGENTS_DIR/skills"
CLAUDE_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
# Antigravity's global skills directory: newer builds read ~/.gemini/config/skills
# (see its own migrate-workflows builtin), older ones ~/.gemini/skills. Prefer an
# existing ~/.gemini/skills so machines already set up that way keep working.
if [ -n "${GEMINI_SKILLS_DIR:-}" ]; then
  GEMINI_DIR="$GEMINI_SKILLS_DIR"
elif [ -d "$HOME/.gemini/skills" ]; then
  GEMINI_DIR="$HOME/.gemini/skills"
elif [ -d "$HOME/.gemini/config" ]; then
  GEMINI_DIR="$HOME/.gemini/config/skills"
else
  GEMINI_DIR="$HOME/.gemini/skills"
fi
EXCLUDE_FILE="$AGENTS_DIR/gemini-exclude.txt"

DRY_RUN=0
ADOPT=0
PRUNE=0
DO_CLAUDE=1
DO_GEMINI=1

usage() {
  cat <<'USAGE'
Usage: sync-skills.sh [options]

  --adopt        Move stray real directories found in ~/.claude/skills or
                 ~/.gemini/skills into ~/.agents/skills first, then link/copy
                 them back. Use this the first time on a machine that already
                 had hand-installed skills.
  --prune        Delete entries in the target directories that no longer exist
                 in ~/.agents/skills (or that are excluded from Antigravity).
                 Without it, orphans are only reported.
  --claude-only  Skip the Antigravity (~/.gemini/skills) mirror.
  --gemini-only  Skip the Claude Code (~/.claude/skills) symlinks.
  -n, --dry-run  Print what would happen, change nothing.
  -h, --help     This text.

Environment overrides: AGENTS_DIR, CLAUDE_SKILLS_DIR, GEMINI_SKILLS_DIR.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --adopt) ADOPT=1 ;;
    --prune) PRUNE=1 ;;
    --claude-only) DO_GEMINI=0 ;;
    --gemini-only) DO_CLAUDE=0 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  would: %s\n' "$*"
  else
    "$@"
  fi
}

[ -d "$SKILLS_DIR" ] || { echo "no canonical skills directory at $SKILLS_DIR" >&2; exit 1; }

# ---------------------------------------------------------------- helpers
# Immediate subdirectory names of $1, sorted. Portable: no `find -printf`.
list_dirs() {
  local path name
  [ -d "$1" ] || return 0
  for path in "$1"/*/; do
    [ -d "$path" ] || continue            # unmatched glob, or a dangling link
    name=${path%/}
    name=${name##*/}
    printf '%s\n' "$name"
  done | LC_ALL=C sort
}

skill_names() { list_dirs "$SKILLS_DIR"; }

# Path of $1 expressed relative to directory $2. Portable: GNU `realpath
# --relative-to` does not exist on macOS.
relpath() {
  local target="${1%/}" base="${2%/}" common up=""
  common="$base"
  while [ -n "$common" ] && [ "$common" != "/" ] && [ "${target#"$common"/}" = "$target" ]; do
    common=$(dirname "$common")
    up="../$up"
  done
  if [ "$common" = "/" ] || [ -z "$common" ]; then
    printf '%s\n' "$up${target#/}"
  else
    printf '%s\n' "$up${target#"$common"/}"
  fi
}

is_excluded() {
  local line
  [ -f "$EXCLUDE_FILE" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    [ "$line" = "$1" ] && return 0
  done < "$EXCLUDE_FILE"
  return 1
}

# --------------------------------------------------------------------- adopt
adopt_from() {
  local dir="$1" name entry
  [ -d "$dir" ] || return 0
  while IFS= read -r name; do
    entry="$dir/$name"
    [ -L "$entry" ] && continue           # already a symlink, nothing to adopt
    if [ -e "$SKILLS_DIR/$name" ]; then
      # An identical copy is just the Antigravity mirror doing its job — stay quiet.
      if ! diff -rq "$entry" "$SKILLS_DIR/$name" >/dev/null 2>&1; then
        echo "  ! $name differs from the canonical copy in $SKILLS_DIR — left alone, merge by hand"
      fi
      continue
    fi
    echo "  + adopting $entry -> $SKILLS_DIR/$name"
    run mv "$entry" "$SKILLS_DIR/$name"
  done < <(list_dirs "$dir")
}

if [ "$ADOPT" -eq 1 ]; then
  echo "Adopting stray skill directories into $SKILLS_DIR"
  if [ "$DO_CLAUDE" -eq 1 ]; then adopt_from "$CLAUDE_DIR"; fi
  if [ "$DO_GEMINI" -eq 1 ]; then adopt_from "$GEMINI_DIR"; fi
fi

# ------------------------------------------------------- Claude Code symlinks
if [ "$DO_CLAUDE" -eq 1 ]; then
  echo "Claude Code: $CLAUDE_DIR"
  run mkdir -p "$CLAUDE_DIR"
  linked=0; relinked=0; skipped=0; total=0
  while IFS= read -r name; do
    total=$((total + 1))
    src="$SKILLS_DIR/$name"
    dst="$CLAUDE_DIR/$name"
    rel=$(relpath "$src" "$CLAUDE_DIR")
    if [ -L "$dst" ]; then
      current=$(readlink "$dst")
      [ "$current" = "$rel" ] && continue
      echo "  ~ relinking $name ($current -> $rel)"
      run rm "$dst"
      run ln -s "$rel" "$dst"
      relinked=$((relinked + 1))
    elif [ -e "$dst" ]; then
      echo "  ! $name is a real directory here — rerun with --adopt to fold it into $SKILLS_DIR"
      skipped=$((skipped + 1))
    else
      echo "  + linking $name"
      run ln -s "$rel" "$dst"
      linked=$((linked + 1))
    fi
  done < <(skill_names)

  # links left dangling by a deleted skill (portable equivalent of `find -xtype l`)
  for dead in "$CLAUDE_DIR"/*; do
    [ -L "$dead" ] || continue
    [ -e "$dead" ] && continue
    if [ "$PRUNE" -eq 1 ]; then
      echo "  - removing broken link ${dead##*/}"
      run rm "$dead"
    else
      echo "  ? broken link ${dead##*/} (use --prune to remove)"
    fi
  done

  echo "  linked=$linked relinked=$relinked skipped=$skipped up-to-date=$((total - linked - relinked - skipped))"
fi

# --------------------------------------------------------- Antigravity copies
copy_tree() {
  if command -v rsync >/dev/null 2>&1; then
    run rsync -a --delete "$1/" "$2/"
  else
    run rm -rf "$2"
    run cp -R "$1" "$2"
  fi
}

if [ "$DO_GEMINI" -eq 1 ]; then
  echo "Antigravity: $GEMINI_DIR"
  run mkdir -p "$GEMINI_DIR"
  copied=0; excluded=0
  while IFS= read -r name; do
    if is_excluded "$name"; then
      excluded=$((excluded + 1))
      continue
    fi
    src="$SKILLS_DIR/$name"
    dst="$GEMINI_DIR/$name"
    if [ -L "$dst" ]; then
      echo "  ~ replacing symlink $name with a real copy"
      run rm "$dst"
    fi
    if ! diff -rq "$src" "$dst" >/dev/null 2>&1; then
      echo "  + copying $name"
      copy_tree "$src" "$dst"
      copied=$((copied + 1))
    fi
  done < <(skill_names)

  # entries in the mirror that are no longer canonical (deleted, or newly excluded)
  while IFS= read -r name; do
    if [ -d "$SKILLS_DIR/$name" ] && ! is_excluded "$name"; then
      continue
    fi
    if [ "$PRUNE" -eq 1 ]; then
      echo "  - removing orphan $name"
      run rm -rf "${GEMINI_DIR:?}/$name"
    else
      echo "  ? orphan $name (use --prune to remove)"
    fi
  done < <(list_dirs "$GEMINI_DIR")

  echo "  copied=$copied excluded=$excluded"
fi

if [ "$DRY_RUN" -eq 1 ]; then echo "(dry run — nothing was changed)"; fi
exit 0
