---
description: Work the "ready for dev" queue — for each GitHub issue, an issue-implementer re-assesses the triaged plan, implements it in an isolated worktree, gets the branch green, and opens a DRAFT PR cross-linked to the issue; a pr-reviewer then adversarially reviews it; the coordinator decides which review comments to address, re-dispatches the implementer to fix them, and only flips the PR draft → ready once it is green and clean. Use when asked to ship the backlog, implement the "ready for dev" queue, or turn triaged tickets into reviewed PRs.
argument-hint: "[issue numbers or label override, optional]"
allowed-tools: Task(issue-implementer), Task(pr-reviewer), Read, Bash(gh issue list:*), Bash(gh issue view:*), Bash(gh issue edit:*), Bash(gh issue comment:*), Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr checks:*), Bash(gh pr ready:*), Bash(gh pr comment:*), Bash(gh pr edit:*), Bash(gh label create:*), Bash(gh label edit:*), Bash(gh label list:*), Bash(gh repo view:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(git status:*), mcp__github
---

# /ship — implement & review the "ready for dev" queue

You coordinate an implement → review → address → ready pipeline over EXISTING
GitHub issues that triage already labelled `ready for dev`. You do NOT implement,
review code, or write PRs yourself — specialists do that in their own contexts on
a stronger model. You select the issues, fan out one implementer per issue
(maximally parallel, isolated worktrees), run each PR through adversarial review,
**decide which review comments are worth addressing**, re-dispatch the
implementer to fix the accepted ones, and only when a PR is green and clean do
you flip it from draft to ready. Keep your own context lean.

This is the downstream partner of `/triage`: triage turns raw issues into
fully-specified `ready for dev` tickets; `/ship` turns those tickets into
reviewed, green, ready-to-merge PRs. `/ship` NEVER merges — a human merges.

## GitHub access — GitHub MCP or `gh` (interchangeable)

Read and write GitHub through whichever backend the session has, **preferring the
GitHub MCP when available** (e.g. on claude.ai/code, where a first-party GitHub
MCP is loaded automatically) and falling back to the `gh` CLI (local terminal).
Discover the actual MCP tool names in-session; if a needed MCP tool isn't
present, use the `gh` command.

| Operation                | `gh`                                            | GitHub MCP (typical)                       |
| ------------------------ | ----------------------------------------------- | ------------------------------------------ |
| list issues by label     | `gh issue list --label … --state open`          | `list_issues` (`labels`, `state`)          |
| read an issue            | `gh issue view <n> --json …`                    | `issue_read` `get`                         |
| comment on an issue      | `gh issue comment <n> --body "…"`               | `issue_write` `add_comment`                |
| set issue labels         | `gh issue edit <n> --add-label/--remove-label`  | `issue_write` `update` (`labels`)          |
| read a PR / its checks   | `gh pr view <n>` / `gh pr checks <n>`           | `pull_request_read`                        |
| read a PR's review       | `gh pr view <n> --comments`                     | `pull_request_read` (comments)             |
| flip draft → ready       | `gh pr ready <n>`                               | `pull_request_write` (`ready`)             |
| resolve repo             | `gh repo view --json nameWithOwner`             | `repository_read` `get`                    |

⚠️ **MCP label gotcha:** the MCP `labels` field REPLACES the issue's entire label
set. On the MCP path you MUST first read the current labels, then send the full
new set (current − `ready for dev` + the outcome label) — otherwise you wipe
labels like `bug`. The `gh` `--add-label`/`--remove-label` path is additive and
carries no such risk.

## Inputs

- Optional `$ARGUMENTS`:
  - Empty → process every OPEN issue with the `ready for dev` label.
  - A space/comma-separated list of issue numbers (e.g. `42 51 60`) → process
    only those (verify each carries `ready for dev`; warn and skip any that
    doesn't).
  - `label=<name>` → override the source label instead of `ready for dev`.
- Resolve the repo once up front: `gh repo view --json nameWithOwner -q .nameWithOwner`
  (MCP: `repository_read` `get`). If neither the GitHub MCP nor an authenticated
  `gh` is available, or there is no repo, STOP and report the blocker.

## Select the queue

```
gh issue list --label "ready for dev" --state open --json number,title --limit 100
```

(MCP: `list_issues` with `labels=["ready for dev"]`, `state="open"`.) Skip any
issue that already has an open linked PR (`gh pr list --search "<num> in:body"`
or check the issue's linked PRs) so a re-run doesn't double-implement.

If the queue is empty, report "nothing to ship" and stop. Otherwise list the
issue numbers you are about to process so the user sees the scope. Do NOT read
full bodies yourself — the implementer reads each issue directly.

## Per-issue pipeline

Run this for EVERY queued issue. **Parallelize across issues** — kick off each
issue's implementer in the background and do NOT serialize. Within a single
issue the steps are sequential (you can't review a PR that doesn't exist yet),
but many issues are in flight at once.

1. **Implement.** Dispatch `issue-implementer` with `isolation: "worktree"` and
   `run_in_background: true`, passing the issue NUMBER, title, and "Mode A —
   implement". Each agent gets its own worktree so parallel branches never
   collide. It re-assesses the plan, implements, greens the branch, opens a
   **draft** PR cross-linked to the issue, and returns a `RESULT:` line.
   - `BLOCKED` → record the blocker; skip the rest for this issue.
   - `IMPLEMENTED` → **link the PR on the issue** before continuing: post a
     comment on the issue pointing at the new PR
     (`gh issue comment <num> --body "🔗 Draft PR opened: #<pr> — <url>"`; MCP:
     `issue_write` `add_comment`). The PR body's `Closes #<num>` already wires up
     GitHub's auto-link, but this comment makes the link explicit and visible in
     the issue's timeline the moment the PR exists. Then continue with `pr`,
     `branch`, `checks`, `self_score`.

2. **Adversarial review.** Dispatch `pr-reviewer` (`run_in_background: true`)
   with the `pr`, the issue number, and the branch. It reads the diff, re-runs
   checks, posts findings ON the PR (severity-tagged), and returns
   `RESULT: APPROVE` or `REVISE` plus a `punch_list`.

3. **Decide & address (you own this judgment — bounded to 2 rounds).**
   On `REVISE`, YOU decide which findings are worth acting on — this is the human
   judgment step. Read the PR diff and the punch-list:
   - Treat **blocking** findings as must-fix by default. Override only with an
     explicit reason (e.g. the reviewer is wrong — verify against the code first).
   - Treat **nits** as optional; accept the cheap/clear ones, skip the rest.
   - For every finding you DECLINE, post a brief reply on the PR saying why, so
     the trail is honest (`gh pr comment <pr> --body "…"`).
   - If you accept ≥1 finding, re-dispatch `issue-implementer` in "Mode B —
     address" (`isolation: "worktree"`, `run_in_background: true`) with the `pr`,
     `branch`, and the **filtered** list of accepted items only. Then send the
     updated PR back through `pr-reviewer` ONE more time.
   - Bound the loop to **at most 2 address→review rounds**. If blocking findings
     remain after that, stop iterating, leave the PR as draft, label the issue
     `needs human`, and report it — never loop forever, never flip a PR with
     unresolved blocking findings.

4. **Finalize — flip draft → ready.** Only when the PR has **zero unaddressed
   blocking findings AND checks are genuinely green** (verify yourself:
   `gh pr checks <pr>` / MCP `pull_request_read`):
   - Flip it out of draft: `gh pr ready <pr>` (MCP: `pull_request_write`
     `ready`). This is the gate the whole pipeline exists to protect.
   - Relabel the issue: remove `ready for dev`, add `in review` (the PR is up,
     green, reviewed, awaiting human merge). On the MCP path, read current labels
     first and resend the full set minus `ready for dev` plus `in review`.
   - Leave the issue open — `Closes #<num>` in the PR closes it on human merge.

   Ensure labels exist first (idempotent, ignore failures) — MCP: `label_write`
   `create`:
   ```
   gh label create "in review" -c "0E8A16" --description "Implemented: green PR open, awaiting human merge" 2>/dev/null || true
   gh label create "needs human" -c "D93F0B" --description "Implementation stalled — blocking review findings need a human" 2>/dev/null || true
   ```

## Wrap-up

Report a single table, `needs human` / blocked first, with: issue (number +
link), title, PR (number + link), checks (green/red), review rounds (e.g.
"reviewed, 1 address round"), and final state (`ready` / `needs human` /
`blocked`). Do NOT paste diffs or full review bodies back — they live on the PRs.

## Notes

- **Background subagents auto-deny anything that would otherwise prompt**, so
  every command the workers run must be pre-approved in `.claude/settings.json`
  (`permissions.allow`). The implementer needs git write (branch/commit/push/
  worktree/fetch/checkout), `gh pr create/edit/view/checks/comment/diff`, and the
  project's build/test runners; the reviewer needs `gh pr diff/view/checks/
  review/comment` and the build/test runners (read-only otherwise). **Project
  toolchains vary** — the allow-list ships with the common JS/TS runners
  (npm/pnpm/yarn/bun/npx) plus make/just; a repo using other tools (cargo, go,
  gradle, pytest, …) needs those commands added to `permissions.allow`, or the
  green step will silently fail under auto-deny.
- **Worktree isolation is what makes parallelism safe.** Always dispatch
  `issue-implementer` with `isolation: "worktree"`; without it, concurrent
  implementers would stomp each other's working tree. The harness cleans up
  worktrees automatically; pushed branches and PRs persist.
- On re-dispatch (Mode B), a fresh worktree is created — the implementer fetches
  and checks out the existing PR branch by name, so the branch (which lives on
  the remote) is what carries state across rounds, not the worktree.
- `/ship` NEVER merges. The final state is a green, reviewed, ready (non-draft)
  PR; a human merges it.
- `gh` must be authenticated (`gh auth status`). **On claude.ai/code:** prefer
  the **GitHub MCP** (loaded automatically). If you must fall back to `gh` there,
  it isn't pre-installed — add `apt update && apt install -y gh` to the cloud
  environment's setup script and provide a repo-scoped `GH_TOKEN`.
- This pipeline is expensive by design: per issue it is at least
  implement + review, plus up to 2 address+review rounds, all on opus/xhigh.
  Parallelism across issues is what keeps wall-clock reasonable — lean into it.
