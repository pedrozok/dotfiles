# dotfiles

My personal macOS configuration: terminal, editor, git, and setup for the
Claude Code and Codex CLIs. It is opinionated - the CLI configs enforce my own
engineering standards and an authorship policy (see Attribution guards below) -
so treat it as a reference to fork and adapt, not a turnkey framework.
Everything installs by symlink from a single source of truth (this repo).

## What's here

| Path | What |
|---|---|
| `.zshrc` | zsh - oh-my-zsh, nvm, pyenv, z, JDK switcher (per-machine config kept in `~/.zshrc.local`) |
| `.tmux.conf` | tmux - vim-aware pane nav + mouse |
| `.gitconfig` | git - pull.rebase, rerere, fetch.prune, SSH-signed commits through 1Password, fsck on fetch (identity and signing key kept in `~/.gitconfig.local`) |
| `Brewfile` | Homebrew formulae and casks for a fresh Mac |
| `npm/npmrc` | npm install gates, added to `~/.npmrc` by the `npm` module |
| `nvim/` | Neovim - LazyVim + tokyonight-storm |
| `ghostty/config` | Ghostty terminal |
| `.claude/` | Claude Code, host-only - settings.json, hooks |
| `sbx/claude-kit/` | Claude Code, shared - skills, CLAUDE.md, statusline as a Docker Sandboxes kit |
| `sbx/codex-kit/` | Codex CLI, shared - AGENTS.md, skills, command rules as a Docker Sandboxes kit |
| `bin/` | `sbx-claude` and `sbx-codex`, wrappers that run an agent in a per-project Docker Sandbox |
| `codex/` | Codex CLI, host-only - config template, hooks.json, guard hook, its own install scripts |
| `opencode/opencode.json` | OpenCode - Ollama as a provider, with GLM and Kimi cloud models (prompts and code go to those providers; check client agreements before using them on a client repo) |

## Requirements

- macOS. The install scripts assume BSD userland.
- The CLI tools the configs drive: neovim, tmux, fzf, fd, ripgrep, jq, gh,
  lazygit, node, tree-sitter-cli, z. Install them however you manage packages.
- python3 - the Codex guard hook (`codex/hooks/guard.py`) runs under it.
- Optional, per feature:
  - Claude Code and/or the Codex CLI, for the `.claude/` and `codex/` config.
  - `sbx` (Docker Sandboxes) for the `sbx-claude` / `sbx-codex` wrappers.
  - OpenCode plus the signed-in `ollama` CLI for `opencode/`. Pick a model with
    `opencode -m ollama/glm-5.3:cloud` or `/models`. OpenCode does not start
    `ollama serve`, so have it running first.

## Install on a fresh Mac

Clone this repo anywhere (the path is remembered via symlinks), replacing
`<you>` with your GitHub username here and below, and link the configs:

```sh
git clone git@github.com:<you>/dotfiles.git ~/Dev/_tools/dotfiles
cd ~/Dev/_tools/dotfiles
./install.sh
```

Then open a new terminal, so the Homebrew settings in `.zshrc` apply, and
install the tools. Delete Brewfile lines you do not use first.

```sh
brew bundle --file ~/Dev/_tools/dotfiles/Brewfile
git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
git clone https://github.com/nvm-sh/nvm.git ~/.nvm
git -C ~/.nvm checkout "$(git -C ~/.nvm describe --abbrev=0 --tags --match 'v[0-9]*' "$(git -C ~/.nvm rev-list --tags --max-count=1)")"
sudo ln -sfn /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-21.jdk
sudo ln -sfn /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk
```

oh-my-zsh and nvm come from git rather than their `curl | sh` installers. The
JDK links let `/usr/libexec/java_home` and the `jdk` function find Homebrew's
keg-only JDKs.

Run bare in a terminal, `./install.sh` opens an interactive picker (arrow keys
or j/k to move, space to toggle, `a` for all, enter to confirm, q to cancel)
over the modules: `zsh tmux git npm nvim ghostty claude codex opencode`. The `codex`
module runs `codex/install.sh` for you, so there is no separate step. To skip
the prompt:

```sh
./install.sh all             # every module
./install.sh tmux claude     # only these
./install.sh --dry-run all   # preview, change nothing
```

Piped or non-interactive (no TTY), `./install.sh` installs everything.

On first run the `git` module prompts for name and email if `~/.gitconfig.local`
isn't set (it's outside the repo - your identity never gets committed), then for
the public half of the SSH key that signs commits. `.gitconfig` signs every
commit and tag with 1Password's `op-ssh-sign`, so `git commit` fails until that
key is set. Re-runs skip the prompts once the values exist.

The `npm` module adds `ignore-scripts`, `min-release-age` and `allow-git` to
`~/.npmrc` and leaves any other line alone. It copies instead of linking because
`npm login` writes tokens into that file. The release-age and git settings need
npm 11.10 or later; an older npm ignores them silently.

The `zsh` module links `.zshrc`, which loads oh-my-zsh, nvm, pyenv, rbenv and z
when they are installed. It sources `~/.zshrc.local` last if it exists; put
anything specific to one machine there (paths, work aliases). That file is
outside the repo and never committed. Tokens go in neither file: they come from
1Password at run time, through `op run` or the `withsecrets` function
(`withsecrets .env.op npm run dev`). The fzf shell hook
(`eval "$(fzf --zsh)"`) is not in `.zshrc`; add it if you want it.

## Updating

```sh
git pull
./install.sh all        # idempotent; only re-links what changed (or pick a subset)
```

## Attribution guards

`.claude/hooks/guard.sh` (Claude Code) and `codex/hooks/guard.py` (Codex) are
PreToolUse hooks that enforce "my work ships under my name only". Before the
tool runs, they block:

- tool-attribution text - AI co-author trailers, "Generated with ..." footers,
  vendor links, the robot emoji - in commits, pushes, PR and issue bodies, MCP
  mutations, and file writes;
- git identity overrides: `--author`, `-c user.*`, `GIT_AUTHOR_*`, and
  `git config user.name/email`;
- force pushes.

Read-only actions (git log/show/diff, MCP reads) are never blocked. If you fork
this and want AI co-author trailers, or otherwise do not want this policy:

- remove the `hooks` block from `.claude/settings.json` and the entry in
  `codex/hooks.json`;
- also unset the attribution suppression in `.claude/settings.json` (and its
  kit copy under `sbx/claude-kit/`): the blank `attribution.commit` and
  `attribution.pr` and `attribution.sessionUrl: false` strip trailers and
  session links independently of the hooks;
- drop the matching lines from CLAUDE.md / AGENTS.md.

## Agent CLIs in Docker Sandboxes

Sandboxes are microVMs: they don't mount `~/.claude` or `~/.codex`, and
symlinks pointing outside the workspace don't resolve inside the VM. So the
canonical shared config lives under `sbx/claude-kit/` and `sbx/codex-kit/`
as real files; the install scripts symlink the host's `~/.claude`, `~/.codex`,
and `~/.agents` entries to them, and the kits copy the same files into a
sandbox's home at creation.

Two ways to use a kit:

```sh
# From a project directory, via the wrappers (use the local kit path;
# install.sh links them into ~/.local/bin - keep that on PATH):
sbx-claude
sbx-codex

# Or directly from git, without a local clone of this repo:
sbx run claude --kit "git+https://github.com/<you>/dotfiles.git#dir=sbx/claude-kit" .
sbx run codex --kit "git+https://github.com/<you>/dotfiles.git#dir=sbx/codex-kit" .
```

Notes:

- Agent login inside a sandbox is a one-time step per project - sandboxes
  persist, and the wrappers reattach to the existing one on re-run.
- Config changed inside a sandbox does not sync back. This repo is the source
  of truth; after changing a kit, recreate sandboxes to pick it up:
  `sbx rm <agent>-<project>` (`sbx-claude --name` / `sbx-codex --name` print
  the exact name).
- Hooks are deliberately not in the kits - they would give a sandboxed agent
  a persistence mechanism - and neither is Codex's `config.toml` (machine
  state). The claude kit ships a hooks-free `settings.json` so permissions,
  attribution blanking, and deny rules still apply inside sandboxes; keep it
  in sync with the host copy in `.claude/`. The host copy also turns on Claude
  Code's own sandbox, which the kit copy leaves out because the microVM is
  already the boundary. Each kit's `spec.yaml` has the
  opt-in steps if you want hooks anyway.
- The wrappers mount only the project. To give a new sandbox read-only access
  to other folders, list them in `SBX_SHARE` (space-separated, no spaces in
  the paths): `SBX_SHARE="$HOME/Downloads" sbx-claude`. Anything mounted is
  readable by the agent and by any code it runs. Mounts are fixed at creation,
  so an existing sandbox needs an `sbx rm <agent>-<project>` first.
- Commits made inside a sandbox use the project repo's `.git/config`, which
  the sandbox shares through the workspace mount. The wrappers seed
  `user.name`/`user.email` into it from the host config on launch (skipped
  when the project already sets its own), so in-sandbox commits are authored
  by you even though `~/.gitconfig.local` never leaves the host.
- On an sbx too old for `--kit`, the wrappers stage the config into
  `.sbx-claude/` / `.sbx-codex/` in the workspace and print the one command to
  apply it inside the sandbox. Gitignore those in projects where this runs.

## Scripts

- `./install.sh` - symlinks dotfiles into place, by module. Bare in a terminal it opens an interactive picker; or pass module names (`tmux git nvim ghostty claude codex opencode`) or `all`. Re-running is safe; existing real files are backed up with a timestamp before being replaced. Pass `--dry-run` to preview. Reports symlinks that point into this repo but no longer resolve. The `codex` module delegates to `codex/install.sh`.
- `./codex/install.sh` - installs the Codex config (invoked by the `codex` module, or run directly): links AGENTS.md, agents, skills, and hooks; copies the command rules file (Codex ignores symlinked rules files) and seeds `codex/config.toml` once (Codex writes machine state into the live file - merge template changes by hand); adds the curated plugins. Tracks backups and rule state. Supports `--dry-run`.
- `./uninstall.sh` and `./codex/uninstall.sh` - each removes what its matching installer created. `./uninstall.sh` does not restore `.backup.*` files; `./codex/uninstall.sh` restores from its own backup manifest. Both support `--dry-run`.
