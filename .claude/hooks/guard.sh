#!/bin/bash
# PreToolUse guard: my work ships under my name only - keep tool attribution out
# of anything that leaves the machine. Fires on Bash, Write, Edit, NotebookEdit,
# and MCP tools. Read-only inspection (git log/show/grep/diff, MCP reads) is
# never blocked, so history audits still work. Belt-and-braces on top of the
# blanked "attribution" setting.

payload=$(cat)

markers='co-authored-by:.{0,60}(claude|anthropic)'
markers+='|noreply@anthropic\.com'
markers+='|generated (with|by).{0,25}claude'
markers+='|claude\.(com|ai)/(claude-)?code'
markers+='|'"$(printf '\360\237\244\226')"  # robot emoji, octal bytes so bash 3.2 printf works and this file stays ASCII

tool=$(printf '%s' "$payload" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"

block() { printf '%s\n' "$1" >&2; exit 2; }
has() { printf '%s' "$payload" | grep -qiE "$1"; }

# Write/Edit/NotebookEdit: scan file content. Exempt the live tool config under
# $HOME and this dotfiles repo, which legitimately quote the marker strings.
# Other repos' .claude/.codex directories are NOT exempt - their content is
# committed and leaves the machine.
case "$tool" in
  Write|Edit|NotebookEdit)
    fpath=$(printf '%s' "$payload" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
    case "$fpath" in "$HOME/.claude/"*|"$HOME/.codex/"*|*/dotfiles/*) exit 0 ;; esac
    case "$(basename "$fpath")" in
      CLAUDE.md|CLAUDE.local.md|AGENTS.md|.mcp.json|.gitignore.local) exit 0 ;;
    esac
    if has "$markers"; then
      block "Blocked: this file content contains tool attribution (co-author trailer / generated-with footer / vendor link / robot emoji). Personal policy: work is authored under my name only. Remove the text entirely - do not rephrase, encode, or route it through a file."
    fi
    exit 0 ;;
esac

# MCP mutations (PRs, issues, comments, reviews) never reach the Bash scanner:
# scan their input directly. Read-style tools stay exempt so audits work.
case "$tool" in
  mcp__*)
    if printf '%s' "$tool" | grep -qE '(^|_)(fetch|get|list|read|search|view|find|status)(_|$)'; then
      exit 0
    fi
    if has "$markers"; then
      block "Blocked: this tool input contains tool attribution (co-author trailer / generated-with footer / vendor link / robot emoji). Remove the text entirely - do not rephrase or encode it."
    fi
    exit 0 ;;
esac

[ "$tool" = "Bash" ] || exit 0

# Work on the decoded command via jq; fall back to the raw JSON-escaped payload
# when jq is missing (weaker matching, still fail-safe).
cmd=$(printf '%s' "$payload" | jq -r '(.tool_input.command // empty) | if type == "array" then join(" ") else . end' 2>/dev/null) || cmd=''
[ -n "$cmd" ] || cmd=$payload
# Quote-stripped copy for structural subcommand/flag matching, so a quoted flag
# (git push "-f") reads the same as bare. The file-path extraction in section 5
# uses the original $cmd, which needs the quotes to bound paths with spaces.
scan=$(printf '%s' "$cmd" | tr -d "\"'")
has_cmd() { printf '%s' "$scan" | grep -qiE "$1"; }

# Resolve repo git aliases so the subcommand-keyed checks below also cover an
# alias that expands to that subcommand (alias.pu=push -> `git pu --force`).
alias_commit='' ; alias_push='' ; alias_outbound='' ; alias_forcecmd=''
if [ -n "$root" ] && git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  while read -r akey aval; do
    an=${akey#alias.}
    case "$an" in ''|*[!A-Za-z0-9._-]*) continue ;; esac
    case " $aval " in *[!A-Za-z-]commit[!A-Za-z-]*|*[!A-Za-z-]am[!A-Za-z-]*) alias_commit="$alias_commit|$an" ;; esac
    case " $aval " in *[!A-Za-z-]push[!A-Za-z-]*) alias_push="$alias_push|$an" ;; esac
    # An alias whose value already carries a force push (`push --force`,
    # `!git push -f`, `push +HEAD`) makes even a bare `git <alias>` a force push.
    case " $aval " in *' --force'*|*' -f '*|*'+'*) alias_forcecmd="$alias_forcecmd|$an" ;; esac
    case " $aval " in
      *[!A-Za-z-]commit[!A-Za-z-]*|*[!A-Za-z-]push[!A-Za-z-]*|*[!A-Za-z-]tag[!A-Za-z-]*|\
*[!A-Za-z-]am[!A-Za-z-]*|*[!A-Za-z-]apply[!A-Za-z-]*|*[!A-Za-z-]notes[!A-Za-z-]*|\
*cherry-pick*|*send-email*|*rebase*|*revert*)
        alias_outbound="$alias_outbound|$an" ;;
    esac
  done <<ALIASES
$(git -C "$root" config --get-regexp '^alias\.' 2>/dev/null)
ALIASES
fi

# 1) Identity is never overridden, whatever the name used: no --author on
#    commit/am (or an alias for them), no -c user.*, no git config user.* write,
#    no GIT_AUTHOR_*/GIT_COMMITTER_* assignments. (git log --author is a filter,
#    not an override - it stays allowed.)
identity='(^|[;&|[:space:]"])GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL|DATE)='
identity+="|git[^;&|]*[[:space:]](commit|am${alias_commit})[^;&|]*[[:space:]]--author"
identity+='|git[^;&|]*[[:space:]]-c[[:space:]]+user\.(name|email)'
# git config user.name/email <value> is a persistent override; a trailing
# value (not an operator/redirect) distinguishes it from a read.
identity+='|git[^;&|]*[[:space:]]config[^;&|]*[[:space:]]user\.(name|email)[[:space:]]+[^-;&|> ]'
if has_cmd "$identity"; then
  block "Blocked: git author/committer identity overrides are forbidden. Commit with the configured identity."
fi

# 2) Force pushes as a whole token after the push verb (or a push alias):
#    --force/--force-with-lease, a bundled short flag carrying -f (-fu, -uf), or
#    +refspec. The verb needs a right boundary so a push alias like `pu` does
#    not prefix-match `pull`. An alias whose value already forces is blocked on
#    bare invocation.
force="git[^;&|]*[[:space:]](push${alias_push})([[:space:]][^;&|]*)?[[:space:]](--force|-[a-z0-9]*f[a-z0-9]*([[:space:]]|\$)|\\+[^[:space:]])"
if [ -n "$alias_forcecmd" ]; then
  force+="|git[^;&|]*[[:space:]](${alias_forcecmd#|})([[:space:]]|\$)"
fi
if has_cmd "$force"; then
  block "Blocked: force pushes are forbidden. Create a new commit or branch instead."
fi

# 3) Inline attribution in a command that can leave the machine. Match the
#    subcommand after any git global flags (--no-pager, -c, --git-dir), and
#    treat aliases that expand to an outbound verb (ci = commit) the same.
verbs="commit|push|tag|notes|am|apply|send-email|cherry-pick|rebase|revert${alias_outbound}"
outbound="git[^;&|]*[[:space:]]($verbs)([[:space:]]|\$)|gh |curl |wget |git-filter"
if has_cmd "$outbound" && has_cmd "$markers"; then
  block "Blocked: this command carries tool attribution text. Remove it entirely - do not rephrase, encode, or write it to a file. (Auditing history is fine: read-only git log/show/grep are allowed.)"
fi

# 4) gh mutations built from substitutions cannot be inspected - refuse them.
gh_mutation='gh[[:space:]][^;&|]*(create|edit|comment|review|merge|close|reopen|--body|--notes|--title|--field|--input|-F|-X|--method)'
if has_cmd "$gh_mutation" && has_cmd '\$\(|`'; then
  block "Blocked: outbound GitHub content built from command substitution cannot be inspected. Expand it into a literal string or a file first."
fi

# 5) Files fed to outbound commands (gh --body-file, -F body=@x, curl -d @x):
#    Bash-written files never reach the Write scanner, so scan them here.
#    Quote-aware so paths with spaces are still inspected.
if has_cmd 'gh |curl |wget '; then
  opts='--body-file|--notes-file|--raw-field|--field|--file|--input|-F'
  opt_files=$(printf '%s\n' "$cmd" \
    | grep -oE -- "($opts)([= ][[:space:]]*|[A-Za-z_-]*=)(\"[^\"]*\"|'[^']*'|[^\"'[:space:]]+)" \
    | sed -E "s/^($opts)([= ][[:space:]]*|[A-Za-z_-]*=)//")
  at_files=$(printf '%s\n' "$cmd" | grep -oE -- "@(\"[^\"]*\"|'[^']*'|[^\"'[:space:]]+)")
  bad=$(printf '%s\n%s\n' "$opt_files" "$at_files" | while IFS= read -r bf; do
    [ -n "$bf" ] || continue
    case "$bf" in (*=@*) bf=${bf#*=@} ;; esac
    bf=${bf#@}; bf=${bf#\"}; bf=${bf%\"}; bf=${bf#\'}; bf=${bf%\'}; bf=${bf#@}
    [ -f "$bf" ] || continue
    if grep -qiE "$markers" "$bf"; then printf '%s\n' "$bf"; break; fi
  done)
  if [ -n "$bad" ]; then
    block "Blocked: a file passed to an outbound command contains tool attribution: $bad. Strip it from that file before sending."
  fi
fi

[ -n "$root" ] && git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# 6) Push-time backstop: refuse to push local commits whose messages or added
#    content carry attribution, however they got there. Content scanning skips
#    the policy files that legitimately quote markers, and skips this dotfiles
#    repo, whose tracked content contains them by design.
if has_cmd 'git ' && has_cmd 'push'; then
  if git -C "$root" log --branches --not --remotes --format='%B' 2>/dev/null | grep -qiE "$markers"; then
    block "Blocked: an unpushed commit carries tool attribution in its message. Find it: git log --branches --not --remotes --format='%h %s' and inspect with git show; rebase/amend to strip the trailer before pushing."
  fi
  case "$root" in
  */dotfiles) ;;
  *)
    if git -C "$root" log --branches --not --remotes --format= -p -- . \
        ':(exclude)*CLAUDE.md' ':(exclude)*CLAUDE.local.md' ':(exclude)*AGENTS.md' \
        ':(exclude)*.claude/*' ':(exclude)*.codex/*' 2>/dev/null | grep -qiE "$markers"; then
      block "Blocked: an unpushed commit adds tool attribution to file content. Find it: git log --branches --not --remotes -p, then amend it out before pushing."
    fi
    ;;
  esac
fi

exit 0
