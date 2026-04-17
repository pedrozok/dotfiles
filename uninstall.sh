#!/bin/sh
# Remove symlinks created by install.sh. Only touches symlinks that point into
# $DOTFILES — never anything else. Does NOT restore .backup.* files; that's
# on you.
#
# Usage:
#     ./uninstall.sh              remove managed links
#     ./uninstall.sh --dry-run    print what would happen, change nothing

set -eu

DOTFILES="$(cd "$(dirname "$0")" && pwd -P)"

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            printf 'unknown argument: %s\n' "$arg" >&2
            exit 2
            ;;
    esac
done

unlink_if_ours() {
    dest="$1"
    if [ ! -L "$dest" ]; then
        printf '  skip    %s (not a symlink)\n' "$dest"
        return
    fi
    target=$(readlink "$dest")
    case "$target" in
        "$DOTFILES"/*)
            printf '  remove  %s -> %s\n' "$dest" "$target"
            [ "$DRY_RUN" -eq 1 ] || rm "$dest"
            ;;
        *)
            printf '  skip    %s -> %s (not ours)\n' "$dest" "$target"
            ;;
    esac
}

printf 'Removing managed symlinks from %s%s\n' "$DOTFILES" "$([ "$DRY_RUN" -eq 1 ] && echo ' (dry-run)' || true)"

unlink_if_ours "$HOME/.tmux.conf"
unlink_if_ours "$HOME/.gitconfig"
unlink_if_ours "$HOME/.config/nvim"
unlink_if_ours "$HOME/.config/ghostty/config"
unlink_if_ours "$HOME/.claude/settings.json"
unlink_if_ours "$HOME/.claude/statusline-command.sh"

# Per-file commands: iterate whatever's currently in the repo so the list stays
# in sync automatically.
if [ -d "$DOTFILES/.claude/commands" ]; then
    for src in "$DOTFILES/.claude/commands"/*; do
        [ -e "$src" ] || continue
        unlink_if_ours "$HOME/.claude/commands/$(basename "$src")"
    done
fi

echo "Done."
