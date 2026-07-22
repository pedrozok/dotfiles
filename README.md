# dotfiles

My personal macOS configuration: terminal, editor, git, and setup for the
Claude Code and Codex CLIs. It is opinionated - the CLI configs enforce my own
engineering standards and an authorship policy (see Attribution guards below) -
so treat it as a reference to fork and adapt, not a turnkey framework.
Everything installs by symlink from a single source of truth (this repo).

## What's here

| Path | What |
|---|---|
| `.tmux.conf` | tmux - vim-aware pane nav + mouse |
| `.gitconfig` | git - pull.rebase, rerere, fetch.prune (identity kept in `~/.gitconfig.local`) |
| `nvim/` | Neovim - LazyVim + tokyonight-storm |
| `ghostty/config` | Ghostty terminal |
| `.claude/` | Claude Code, host-only - settings.json, hooks |
| `sbx/claude-kit/` | Claude Code, shared - skills, agents, commands, CLAUDE.md, statusline as a Docker Sandboxes kit |
| `sbx/codex-kit/` | Codex CLI, shared - AGENTS.md, agents, skills, command rules as a Docker Sandboxes kit |
| `bin/` | `sbx-claude` and `sbx-codex`, wrappers that run an agent in a per-project Docker Sandbox |
| `codex/` | Codex CLI, host-only - config template, hooks.json, guard hook, its own install scripts |

## Requirements

- macOS. The install scripts assume BSD userland.
- The CLI tools the configs drive: neovim, tmux, fzf, fd, ripgrep, jq, gh,
  lazygit, node, tree-sitter-cli, z. Install them however you manage packages.
- python3 - the Codex guard hook (`codex/hooks/guard.py`) runs under it.
- Optional, per feature:
  - Claude Code and/or the Codex CLI, for the `.claude/` and `codex/` config.
  - `sbx` (Docker Sandboxes) for the `sbx-claude` / `sbx-codex` wrappers.
  - An authenticated `gh` plus the matching MCP connector (GitHub, Jira, or
    Asana) for the triage/ship agent workflows.

## Install on a fresh Mac

```sh
# 1. Clone this repo anywhere (path is remembered via symlinks).
#    Replace <you> with your GitHub username here and below.
git clone git@github.com:<you>/dotfiles.git ~/Dev/_tools/dotfiles
cd ~/Dev/_tools/dotfiles

# 2. Install the CLI tools the configs use, however you manage packages:
#    neovim tmux fzf fd ripgrep jq gh lazygit node tree-sitter-cli
# 3. Link configs into place
./install.sh
```

Run bare in a terminal, `./install.sh` opens an interactive picker (arrow keys
or j/k to move, space to toggle, `a` for all, enter to confirm, q to cancel)
over the modules: `tmux git nvim ghostty claude codex`. The `codex` module runs
`codex/install.sh` for you, so there is no separate step. To skip the prompt:

```sh
./install.sh all             # every module
./install.sh tmux claude     # only these
./install.sh --dry-run all   # preview, change nothing
```

Piped or non-interactive (no TTY), `./install.sh` installs everything.

On first run the `git` module prompts for name and email if `~/.gitconfig.local`
isn't set (it's outside the repo - your identity never gets committed). Re-runs
skip the prompt once the file exists.

`fzf` and `z` need a hook in your shell rc (not tracked here): `eval "$(fzf --zsh)"` and the `z` init line for wherever it is installed.

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
- also unset the co-author suppression in `.claude/settings.json` (and its kit
  copy under `sbx/claude-kit/`): `attribution` blanking and
  `includeCoAuthoredBy: false` strip trailers independently of the hooks;
- drop the matching lines from CLAUDE.md / AGENTS.md.

## Agent workflows: triage and ship

Both kits ship two multi-agent skills for working a tracker backlog:

- `/triage` - takes items labeled `need-triage`, investigates the codebase, and
  rewrites each into a fully specified ticket labeled `ready-for-dev`, checked
  by a panel of reviewer agents.
- `/ship` - takes `ready-for-dev` items, implements each in an isolated
  worktree, gets the branch green, opens a draft PR, and runs an adversarial
  reviewer panel before marking it ready.

They work with GitHub, Jira, or Asana and need the matching MCP connector plus
an authenticated `gh`; PR hosting is GitHub-only. The role definitions live
under each kit's `agents/` and `skills/`, shared by both CLIs.

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
  in sync with the host copy in `.claude/`. Each kit's `spec.yaml` has the
  opt-in steps if you want hooks anyway.
- If `~/Screenshots` exists on the host, the wrappers mount it into the
  sandbox as a read-only extra workspace at the same path, so screenshots can
  be referenced in prompts. It's passed on every run; a sandbox created before
  the folder existed needs an `sbx rm <agent>-<project>` to pick it up.
- Commits made inside a sandbox use the project repo's `.git/config`, which
  the sandbox shares through the workspace mount. The wrappers seed
  `user.name`/`user.email` into it from the host config on launch (skipped
  when the project already sets its own), so in-sandbox commits are authored
  by you even though `~/.gitconfig.local` never leaves the host.
- On an sbx too old for `--kit`, the wrappers stage the config into
  `.sbx-claude/` / `.sbx-codex/` in the workspace and print the one command to
  apply it inside the sandbox. Gitignore those in projects where this runs.
- Remote Control (`/remote-control`) fails inside sbx with a 403 transport
  error on any network policy: the sandbox's forward proxy rewrites the
  `Authorization` header to inject the real credential, which clobbers RC's
  per-session scoped tokens ([docker/sbx-releases#8]). Until that's fixed
  upstream, the claude kit ships `rc-claude` (in the sandbox's
  `~/.local/bin`): it bootstraps [sbx-claude-code-rc-shim] - a mitmproxy
  addon that sends only the RC scoped-token requests direct, keeping
  everything else on the injecting proxy and all egress under sbx's network
  policy - and launches claude through it. First run needs egress to
  github.com and sudo (to trust the shim's CA); the shim is pinned to a
  reviewed commit in `rc-claude`. Sandboxes created before the kit change
  need an `sbx rm <agent>-<project>` to pick it up.

[docker/sbx-releases#8]: https://github.com/docker/sbx-releases/issues/8
[sbx-claude-code-rc-shim]: https://github.com/jrhender/sbx-claude-code-rc-shim

## Scripts

- `./install.sh` - symlinks dotfiles into place, by module. Bare in a terminal it opens an interactive picker; or pass module names (`tmux git nvim ghostty claude codex`) or `all`. Re-running is safe; existing real files are backed up with a timestamp before being replaced. Pass `--dry-run` to preview. Reports symlinks that point into this repo but no longer resolve. The `codex` module delegates to `codex/install.sh`.
- `./codex/install.sh` - installs the Codex config (invoked by the `codex` module, or run directly): links AGENTS.md, agents, skills, and hooks; copies the command rules file (Codex ignores symlinked rules files) and seeds `codex/config.toml` once (Codex writes machine state into the live file - merge template changes by hand); adds the curated plugins. Tracks backups and rule state. Supports `--dry-run`.
- `./uninstall.sh` and `./codex/uninstall.sh` - each removes what its matching installer created. `./uninstall.sh` does not restore `.backup.*` files; `./codex/uninstall.sh` restores from its own backup manifest. Both support `--dry-run`.
