#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
KIT=$(CDPATH= cd -- "$ROOT/../sbx/codex-kit/files/home" && pwd)
DRY_RUN=0
BACKUP_MANIFEST="$HOME/.codex/dotfiles-backups"
RULE_STATE="$HOME/.codex/dotfiles-rule-state"

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
elif [ "$#" -ne 0 ]; then
  printf 'usage: %s [--dry-run]\n' "$0" >&2
  exit 2
fi

unlink_if_ours() {
  dest=$1
  [ -L "$dest" ] || return 0
  case "$(readlink "$dest")" in
    "$ROOT"/* | "$KIT"/*)
      if [ "$DRY_RUN" -eq 0 ]; then
        rm "$dest"
      fi
      printf '  unlink  %s\n' "$dest"
      ;;
  esac
  return 0
}

unlink_if_ours "$HOME/.codex/AGENTS.md"
# config.toml is seeded (real file, accumulates machine state); the legacy
# symlink form is still removed if present.
unlink_if_ours "$HOME/.codex/config.toml"
unlink_if_ours "$HOME/.codex/hooks.json"
unlink_if_ours "$HOME/.codex/hooks"

unlink_if_ours "$HOME/.agents/references"

for directory in "$HOME/.codex/agents" "$HOME/.agents/skills"; do
  [ -d "$directory" ] || continue
  for dest in "$directory"/*; do
    unlink_if_ours "$dest"
  done
done

rules="$HOME/.codex/rules/dotfiles.rules"
if [ -f "$RULE_STATE" ]; then
  expected=$(cat "$RULE_STATE")
  if [ -f "$rules" ] && [ "$(cksum "$rules" | awk '{ print $1 ":" $2 }')" = "$expected" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
      rm "$rules"
    fi
    printf '  remove  %s\n' "$rules"
  elif [ -e "$rules" ] || [ -L "$rules" ]; then
    printf '  keep    %s (modified after installation)\n' "$rules"
  fi
  if [ "$DRY_RUN" -eq 0 ]; then
    rm "$RULE_STATE"
  fi
fi

if [ -f "$BACKUP_MANIFEST" ]; then
  reverse=$(mktemp "${TMPDIR:-/tmp}/codex-backups.XXXXXX")
  remaining=$(mktemp "${TMPDIR:-/tmp}/codex-backups.XXXXXX")
  trap 'rm -f "$reverse" "$remaining"' EXIT HUP INT TERM
  awk '{ lines[NR] = $0 } END { for (i = NR; i > 0; i--) print lines[i] }' "$BACKUP_MANIFEST" >"$reverse"
  tab=$(printf '\t')
  while IFS="$tab" read -r dest backup_path; do
    [ -n "$dest" ] && [ -n "$backup_path" ] || continue
    if [ ! -e "$dest" ] && [ ! -L "$dest" ] && [ -e "$backup_path" ]; then
      if [ "$DRY_RUN" -eq 0 ]; then
        mv "$backup_path" "$dest"
      fi
      printf '  restore %s <- %s\n' "$dest" "$backup_path"
    elif [ -e "$backup_path" ] || [ -L "$backup_path" ]; then
      printf '  keep    %s (destination occupied: %s)\n' "$backup_path" "$dest"
      printf '%s\t%s\n' "$dest" "$backup_path" >>"$remaining"
    fi
  done <"$reverse"
  if [ "$DRY_RUN" -eq 0 ]; then
    if [ -s "$remaining" ]; then
      awk '{ lines[NR] = $0 } END { for (i = NR; i > 0; i--) print lines[i] }' "$remaining" >"$BACKUP_MANIFEST"
    else
      rm "$BACKUP_MANIFEST"
    fi
  fi
fi
