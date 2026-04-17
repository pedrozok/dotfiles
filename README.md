# dotfiles

Personal configuration shared across my Macs.

## What's here

| Path | What |
|---|---|
| `.tmux.conf` | tmux — vim-aware pane nav + mouse |
| `.gitconfig` | git — pull.rebase, rerere, fetch.prune (identity kept in `~/.gitconfig.local`) |
| `nvim/` | Neovim — LazyVim + tokyonight-storm |
| `ghostty/config` | Ghostty terminal |
| `.claude/` | Claude Code — settings, statusline, custom commands |
| `Brewfile` | Homebrew formulas, casks, VS Code extensions |

## Install on a fresh Mac

```sh
# 1. Install Homebrew first (it installs nothing automatically)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Clone this repo anywhere (path is remembered via symlinks)
git clone git@github.com:<you>/dotfiles.git ~/Dev/_tools/dotfiles
cd ~/Dev/_tools/dotfiles

# 3. Install packages
brew bundle --file=Brewfile

# 4. Link configs into place
./install.sh
```

On first run `install.sh` prompts for git name and email if `~/.gitconfig.local` isn't set (it's outside the repo — your identity never gets committed). Re-runs skip the prompt once the file exists.

## Updating

```sh
git pull
./install.sh            # idempotent; only re-links what changed
brew bundle --file=Brewfile
```

## Scripts

- `./install.sh` — symlinks dotfiles into their expected locations. Re-running is safe; existing real files are backed up with a timestamp before being replaced. Pass `--dry-run` to preview. Reports symlinks that point into this repo but no longer resolve.
- `./uninstall.sh` — removes only symlinks that point into this repo. Does not restore `.backup.*` files. Supports `--dry-run`.

## Regenerating the Brewfile

Run on the Mac whose state you want to mirror to others:

```sh
brew bundle dump --describe --file=Brewfile --force
```
