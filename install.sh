#!/bin/sh
# Symlink dotfiles into their expected locations.
# Idempotent: safe to re-run. Existing real files are backed up with a timestamp.
#
# Usage:
#     ./install.sh              install/update links
#     ./install.sh --dry-run    print what would happen, change nothing

set -eu

DOTFILES="$(cd "$(dirname "$0")" && pwd -P)"

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            printf 'unknown argument: %s\n' "$arg" >&2
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

    # Same file already — whether via a direct symlink, an ancestor-dir symlink,
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

link_tree() {
    # Link every file in $1 into $2, keeping filenames. New files added to the
    # source dir get picked up automatically on the next run.
    src_dir="$1"
    dest_dir="$2"
    [ -d "$src_dir" ] || return 0
    for src in "$src_dir"/*; do
        [ -e "$src" ] || continue
        link "$src" "$dest_dir/$(basename "$src")"
    done
}

# Check managed locations for symlinks that point into $DOTFILES but no longer
# resolve — these are usually files that were renamed or removed in the repo.
prune_stale() {
    # Directories we own symlinks in.
    found=0
    for dir in "$HOME" "$HOME/.config/ghostty" "$HOME/.claude" "$HOME/.claude/commands"; do
        [ -d "$dir" ] || continue
        # -maxdepth 1 to avoid crossing into the repo via the dir symlinks.
        for entry in $(find "$dir" -maxdepth 1 -type l 2>/dev/null); do
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
    [ "$found" -eq 0 ] || printf '  (%d stale link(s) above — remove with: rm <path>)\n' "$found"
}

printf 'Linking dotfiles from %s%s\n' "$DOTFILES" "$([ "$DRY_RUN" -eq 1 ] && echo ' (dry-run)' || true)"

link "$DOTFILES/.tmux.conf"                    "$HOME/.tmux.conf"
link "$DOTFILES/.gitconfig"                    "$HOME/.gitconfig"
link "$DOTFILES/nvim"                          "$HOME/.config/nvim"
link "$DOTFILES/ghostty/config"                "$HOME/.config/ghostty/config"
link "$DOTFILES/.claude/settings.json"         "$HOME/.claude/settings.json"
link "$DOTFILES/.claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"

link_tree "$DOTFILES/.claude/commands" "$HOME/.claude/commands"

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

    printf '\nGit identity is missing — writing to %s\n' "$local_path"
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

setup_git_identity

prune_stale

echo "Done."
