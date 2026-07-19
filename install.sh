#!/usr/bin/env bash
# Symlink dotfiles into their expected locations.
# Idempotent: safe to re-run. Existing real files are backed up with a timestamp.
#
# Usage:
#     ./install.sh                bare + a terminal: pick modules interactively
#     ./install.sh all            install every module, no prompt
#     ./install.sh tmux claude    install only the named modules
#     ./install.sh --dry-run ...  print what would happen, change nothing
#
# Modules: tmux git nvim ghostty claude codex
# With no TTY (piped/CI) and no module args, installs everything.

# Re-exec under bash when started via `sh install.sh` on a non-bash /bin/sh:
# the picker needs bash arrays and read -n. (This line is plain POSIX and runs
# before any bashism, so dash reaches it and hands off cleanly.)
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

set -eu

DOTFILES="$(cd "$(dirname "$0")" && pwd -P)"

# Module keys, one-line descriptions, and the install function for each. Keep
# the three arrays index-aligned.
KEY=(tmux git nvim ghostty claude codex)
DESC=(
  "tmux - vim-aware pane nav + mouse"
  "git - pull.rebase, rerere; identity in ~/.gitconfig.local"
  "nvim - LazyVim + tokyonight-storm"
  "ghostty - terminal config"
  "claude - Claude Code config, hooks, statusline, sbx-claude"
  "codex - Codex CLI agents, skills, plugins, sbx-codex"
)

DRY_RUN=0
requested=""
for arg in "$@"; do
  case "$arg" in
  -n | --dry-run) DRY_RUN=1 ;;
  -h | --help)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  all) requested="tmux git nvim ghostty claude codex" ;;
  tmux | git | nvim | ghostty | claude | codex) requested="$requested $arg" ;;
  *)
    printf 'unknown argument: %s (modules: %s)\n' "$arg" "${KEY[*]}" >&2
    exit 2
    ;;
  esac
done

run() {
  [ "$DRY_RUN" -eq 1 ] || "$@"
}

link() {
  src="$1"
  dest="$2"

  # Same file already - whether via a direct symlink, an ancestor-dir symlink,
  # or a hardlink. -ef follows symlinks in the path, so this catches the case
  # where $HOME/.config/foo is a symlink to $DOTFILES/foo and we're about to
  # clobber files inside the repo itself.
  if [ -e "$dest" ] && [ "$dest" -ef "$src" ]; then
    printf '  ok      %s\n' "$dest"
    return
  fi

  run mkdir -p "$(dirname "$dest")"

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
    printf '  backup  %s -> %s\n' "$dest" "$backup"
    run mv "$dest" "$backup"
  fi

  run ln -s "$src" "$dest"
  printf '  link    %s -> %s\n' "$dest" "$src"
}

setup_git_identity() {
  local_path="$HOME/.gitconfig.local"
  name=$(git config --file "$local_path" user.name 2>/dev/null || true)
  email=$(git config --file "$local_path" user.email 2>/dev/null || true)

  if [ -n "$name" ] && [ -n "$email" ]; then
    printf '  ok      %s (user.name, user.email set)\n' "$local_path"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  would prompt for git user.name and user.email -> %s\n' "$local_path"
    return
  fi
  if [ ! -t 0 ]; then
    printf '  skip    %s (no TTY; create manually)\n' "$local_path"
    return
  fi

  printf '\nGit identity is missing - writing to %s\n' "$local_path"
  if [ -z "$name" ]; then
    printf '  Name:  '
    read -r name
  fi
  if [ -z "$email" ]; then
    printf '  Email: '
    read -r email
  fi

  if [ -z "$name" ] || [ -z "$email" ]; then
    printf '  skip    %s (name and email required)\n' "$local_path"
    return
  fi

  git config --file "$local_path" user.name "$name"
  git config --file "$local_path" user.email "$email"
  printf '  wrote   %s\n' "$local_path"
}

mod_tmux() {
  link "$DOTFILES/.tmux.conf" "$HOME/.tmux.conf"
}

mod_git() {
  link "$DOTFILES/.gitconfig" "$HOME/.gitconfig"
  setup_git_identity
}

mod_nvim() {
  link "$DOTFILES/nvim" "$HOME/.config/nvim"
}

mod_ghostty() {
  link "$DOTFILES/ghostty/config" "$HOME/.config/ghostty/config"
}

mod_claude() {
  # Host-only Claude config: settings.json stays out of the sbx kit because its
  # hooks would hand a sandboxed agent a persistence mechanism (see the kit's
  # spec.yaml).
  link "$DOTFILES/.claude/settings.json" "$HOME/.claude/settings.json"
  link "$DOTFILES/.claude/hooks" "$HOME/.claude/hooks"

  # The rest of the Claude config is canonical in the sbx kit tree so the same
  # files ship into Docker Sandboxes; the host links point there. Whole-directory
  # symlinks: the dir itself is the link, so files added later appear with no re-run.
  CLAUDE_KIT="$DOTFILES/sbx/claude-kit/files/home/.claude"
  link "$CLAUDE_KIT/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  link "$CLAUDE_KIT/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
  for d in skills agents commands; do
    [ -d "$CLAUDE_KIT/$d" ] && link "$CLAUDE_KIT/$d" "$HOME/.claude/$d"
  done

  link "$DOTFILES/bin/sbx-claude" "$HOME/.local/bin/sbx-claude"
}

mod_codex() {
  link "$DOTFILES/bin/sbx-codex" "$HOME/.local/bin/sbx-codex"
  # codex/install.sh owns codex config (backup, rule-state, plugins); delegate
  # so this script never duplicates or conflicts with that logic.
  if [ "$DRY_RUN" -eq 1 ]; then
    "$DOTFILES/codex/install.sh" --dry-run
  else
    "$DOTFILES/codex/install.sh"
  fi
}

# Check managed locations for symlinks that point into $DOTFILES but no longer
# resolve - usually files that were renamed or removed in the repo.
prune_stale() {
  found=0
  for dir in "$HOME" "$HOME/.config/ghostty" "$HOME/.claude" "$HOME/.codex" "$HOME/.local/bin"; do
    [ -d "$dir" ] || continue
    # Globs instead of find output: entry names with spaces stay intact, and
    # depth 1 avoids crossing into the repo via the dir symlinks.
    for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
      [ -L "$entry" ] || continue
      target=$(readlink "$entry")
      case "$target" in
      "$DOTFILES"/*)
        if [ ! -e "$entry" ]; then
          printf '  stale   %s -> %s (target missing)\n' "$entry" "$target"
          found=$((found + 1))
        fi
        ;;
      esac
    done
  done
  [ "$found" -eq 0 ] || printf '  (%d stale link(s) above - remove with: rm <path>)\n' "$found"
}

# Interactive checkbox picker. Arrow keys or j/k move, space toggles, a toggles
# all, enter confirms, q cancels. No dependencies; restores the terminal on any
# exit. Sets PICKED to the space-separated chosen keys; returns 1 on cancel.
pick() {
  local n=${#KEY[@]} cur=0 i key seq c allon saved cols
  local sel=()
  for ((i = 0; i < n; i++)); do sel[i]=1; done # default: everything checked

  saved=$(stty -g)
  cols=$(tput cols 2>/dev/null || echo 80)
  # Traps BEFORE touching the terminal, so a signal in the setup window still
  # restores. Restore lives ONLY in the EXIT trap: it runs last, after the
  # `read` builtin's own termios unwind-protect (which re-applies the raw state
  # read saw on entry). Restoring inside INT/TERM would be clobbered by that
  # unwind, so INT/TERM only exit - the still-armed EXIT trap does the restore.
  trap 'stty "$saved" 2>/dev/null; printf "\033[?25h"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  stty -echo -icanon min 1 time 0
  printf '\033[?25l' # hide cursor

  _draw() {
    local i mark ptr line
    for ((i = 0; i < n; i++)); do
      [ "${sel[i]}" -eq 1 ] && mark="x" || mark=" "
      [ "$i" -eq "$cur" ] && ptr=">" || ptr=" "
      line="  $ptr [$mark] ${DESC[i]}"
      printf '\r\033[K%s\n' "${line:0:cols}" # truncate to width so lines never wrap
    done
    c=0
    for ((i = 0; i < n; i++)); do [ "${sel[i]}" -eq 1 ] && c=$((c + 1)); done
    line="  $c selected  (up/down or j/k, space toggle, a all, enter confirm, q cancel)"
    printf '\r\033[K%s\n' "${line:0:cols}"
  }

  printf '\n  Install dotfiles\n\n'
  _draw
  local rows=$((n + 1))

  while :; do
    if ! IFS= read -rsn1 key; then
      # read failed without a caught signal (EOF/hangup): abort, never confirm.
      stty "$saved" 2>/dev/null
      printf '\033[?25h'
      trap - EXIT INT TERM
      PICKED=""
      return 1
    fi
    case "$key" in
    '' | $'\n' | $'\r') break ;; # enter confirms
    $'\033')                     # escape sequence (arrow keys, both normal and application mode)
      IFS= read -rsn2 -t 1 seq 2>/dev/null || seq=""
      case "$seq" in
      '[A' | 'OA') cur=$(((cur - 1 + n) % n)) ;;
      '[B' | 'OB') cur=$(((cur + 1) % n)) ;;
      esac
      ;;
    k | K) cur=$(((cur - 1 + n) % n)) ;;
    j | J) cur=$(((cur + 1) % n)) ;;
    ' ') sel[cur]=$((1 - sel[cur])) ;;
    a | A)
      allon=1
      for ((i = 0; i < n; i++)); do [ "${sel[i]}" -eq 0 ] && allon=0; done
      for ((i = 0; i < n; i++)); do sel[i]=$((1 - allon)); done
      ;;
    q | Q)
      stty "$saved" 2>/dev/null
      printf '\033[?25h'
      trap - EXIT INT TERM
      PICKED=""
      return 1
      ;;
    esac
    printf '\033[%dA' "$rows"
    _draw
  done

  stty "$saved" 2>/dev/null
  printf '\033[?25h'
  trap - EXIT INT TERM
  PICKED=""
  for ((i = 0; i < n; i++)); do
    [ "${sel[i]}" -eq 1 ] && PICKED="$PICKED ${KEY[i]}"
  done
  return 0 # not the loop's status: a trailing unchecked item leaves [ ] false
}

# Decide the module set: explicit args win; otherwise an interactive terminal
# gets the picker; everything else (piped/CI) installs all.
selected=""
if [ -n "$requested" ]; then
  selected="$requested"
elif [ -t 0 ] && [ -t 1 ] && [ -n "${BASH_VERSION:-}" ]; then
  if pick; then
    selected="$PICKED"
  else
    echo "Cancelled."
    exit 0
  fi
else
  selected="tmux git nvim ghostty claude codex"
fi

# Normalize whitespace for the report.
selected=$(printf '%s' "$selected" | tr -s ' ' | sed 's/^ //;s/ $//')
if [ -z "$selected" ]; then
  echo "Nothing selected."
  exit 0
fi

printf 'Installing [%s] from %s%s\n' "$selected" "$DOTFILES" "$([ "$DRY_RUN" -eq 1 ] && echo ' (dry-run)' || true)"
for m in $selected; do
  printf '\n(%s)\n' "$m"
  "mod_$m"
done

echo
prune_stale
echo "Done."
