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

run() {
  if [ "$DRY_RUN" -eq 0 ]; then
    "$@"
  fi
}

backup() {
  dest=$1
  backup_path="$dest.backup.$(date +%Y%m%d%H%M%S).$$"
  run mv "$dest" "$backup_path"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$(dirname "$BACKUP_MANIFEST")"
    printf '%s\t%s\n' "$dest" "$backup_path" >>"$BACKUP_MANIFEST"
  fi
  printf '  backup  %s -> %s\n' "$dest" "$backup_path"
}

link() {
  src=$1
  dest=$2

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    printf '  ok      %s\n' "$dest"
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup "$dest"
  fi
  run mkdir -p "$(dirname "$dest")"
  run ln -s "$src" "$dest"
  printf '  link    %s -> %s\n' "$dest" "$src"
}

fingerprint() {
  cksum "$1" | awk '{ print $1 ":" $2 }'
}

copy_rule() {
  src=$1
  dest=$2

  managed=0
  if [ -f "$RULE_STATE" ] && [ -f "$dest" ] && [ "$(fingerprint "$dest")" = "$(cat "$RULE_STATE")" ]; then
    managed=1
  elif [ -f "$dest" ] && cmp -s "$src" "$dest" && [ -L "$HOME/.codex/AGENTS.md" ] && [ "$(readlink "$HOME/.codex/AGENTS.md")" = "$KIT/.codex/AGENTS.md" ]; then
    managed=1
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$managed" -eq 0 ] && ! cmp -s "$src" "$dest"; then
      backup "$dest"
    elif [ "$managed" -eq 0 ]; then
      printf '  keep    %s (existing identical file is not installer-owned)\n' "$dest"
      return
    elif cmp -s "$src" "$dest"; then
      if [ "$DRY_RUN" -eq 0 ]; then
        fingerprint "$dest" >"$RULE_STATE"
      fi
      printf '  ok      %s\n' "$dest"
      return
    fi
  fi
  run mkdir -p "$(dirname "$dest")"
  run cp "$src" "$dest"
  if [ "$DRY_RUN" -eq 0 ]; then
    fingerprint "$dest" >"$RULE_STATE"
  fi
  printf '  copy    %s -> %s\n' "$dest" "$src"
}

ensure_plugin() {
  plugin=$1
  if ! command -v codex >/dev/null 2>&1; then
    printf '  skip    %s (codex not installed yet; re-run after installing it)\n' "$plugin"
    return
  fi
  if [ "$DRY_RUN" -ne 0 ]; then
    printf '  plugin  %s\n' "$plugin"
    return
  fi
  if codex plugin list --json 2>/dev/null | grep -Fq "\"pluginId\": \"$plugin\""; then
    printf '  ok      %s\n' "$plugin"
  elif codex plugin add "$plugin" >/dev/null 2>&1; then
    printf '  plugin  %s\n' "$plugin"
  else
    # A missing marketplace entry or a renamed plugin must not abort the whole
    # install; the plugin may also already be enabled via config.toml.
    printf '  warn    %s (could not add - add it by hand or check `codex plugin list`)\n' "$plugin"
  fi
}

prune_links() {
  directory=$1
  source_prefix=$2
  [ -d "$directory" ] || return 0
  for dest in "$directory"/*; do
    [ -L "$dest" ] || continue
    target=$(readlink "$dest")
    case "$target" in
      "$source_prefix"/*)
        [ -e "$target" ] && continue
        run rm "$dest"
        printf '  prune   %s\n' "$dest"
        ;;
    esac
  done
}

# config.toml is seeded, never linked: Codex writes machine state (trust
# levels, marketplaces, hook hashes) into the live file, and a symlink would
# route that state straight into the repo.
seed() {
  src=$1
  dest=$2
  if [ -L "$dest" ]; then
    case "$(readlink "$dest")" in
    "$ROOT"/*)
      # A previous version linked this file; materialize the live content as
      # a real file so machine state stops flowing into the repo.
      if [ "$DRY_RUN" -eq 0 ]; then
        cp "$dest" "$dest.materialize.$$"
        rm "$dest"
        mv "$dest.materialize.$$" "$dest"
      fi
      printf '  migrate %s (symlink into repo replaced with a real copy)\n' "$dest"
      return
      ;;
    esac
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    printf '  ok      %s (exists; template changes merge by hand from %s)\n' "$dest" "$src"
    return
  fi
  run mkdir -p "$(dirname "$dest")"
  run cp "$src" "$dest"
  printf '  seed    %s -> %s\n' "$dest" "$src"
}

link "$KIT/.codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
seed "$ROOT/config.toml" "$HOME/.codex/config.toml"
link "$ROOT/hooks.json" "$HOME/.codex/hooks.json"
link "$ROOT/hooks" "$HOME/.codex/hooks"

for agent in "$KIT"/.codex/agents/*.toml; do
  link "$agent" "$HOME/.codex/agents/$(basename "$agent")"
done

for skill in "$KIT"/.agents/skills/*; do
  [ -f "$skill/SKILL.md" ] || continue
  link "$skill" "$HOME/.agents/skills/$(basename "$skill")"
done

# Skills read ../../references/trackers.md; a real ~/.agents/references makes
# that resolve lexically too, not only through kernel symlink traversal.
link "$KIT/.agents/references" "$HOME/.agents/references"

prune_links "$HOME/.codex/agents" "$KIT/.codex/agents"
prune_links "$HOME/.agents/skills" "$KIT/.agents/skills"

# Codex ignores symlinked rule files.
copy_rule "$KIT/.codex/rules/dotfiles.rules" "$HOME/.codex/rules/dotfiles.rules"

for plugin in github@openai-curated atlassian-rovo@openai-curated asana@openai-curated; do
  ensure_plugin "$plugin"
done

printf '%s\n' 'Review and trust the updated user hook with /hooks in a new Codex session.'
