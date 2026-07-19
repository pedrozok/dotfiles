---
name: ship
description: Work the "ready-for-dev" queue - for each tracker item (GitHub issue, Jira, or Asana), an issue-implementer agent re-assesses the triaged plan, implements it in an isolated worktree, gets the branch green, and opens a DRAFT PR cross-linked to the item; a PANEL of pr-reviewer agents then adversarially reviews it; the coordinator decides which findings to address, re-dispatches the implementer to fix them, and only flips the PR draft to ready once it is green and clean. Use when asked to ship the backlog, implement the ready-for-dev queue, or turn triaged tickets into reviewed PRs.
argument-hint: "[github|jira|asana] [item ids] [label=<override>] [panel=2|3]"
allowed-tools: Task(issue-implementer), Task(pr-reviewer), Read, Bash(gh issue list:*), Bash(gh issue view:*), Bash(gh issue edit:*), Bash(gh issue comment:*), Bash(gh label create:*), Bash(gh label edit:*), Bash(gh label list:*), Bash(gh repo view:*), Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr checks:*), Bash(gh pr comment:*), mcp__github, mcp__claude_ai_Atlassian, mcp__claude_ai_Asana
---

# /ship - implement and review the ready-for-dev queue

You coordinate an implement -> review -> address -> ready pipeline over
EXISTING tracker items that triage already tagged `ready-for-dev`. You do NOT
implement, review code, or write PRs yourself - agents do that in their own
contexts. You select the items, fan out one implementer per item (maximally
parallel, isolated worktrees), run each PR through an adversarial review PANEL,
**decide which findings are worth addressing**, re-dispatch the implementer to
fix the accepted ones, and only when a PR is green and clean do you flip it
from draft to ready. Keep your own context lean.

This is the downstream partner of `/triage`: triage turns raw items into
fully-specified `ready-for-dev` tickets; `/ship` turns those tickets into
reviewed, green, ready-to-merge PRs. `/ship` NEVER merges - a human merges.

## Tracker access

Read `~/.claude/skills/trackers.md` FIRST. It defines how to pick the tracker,
the state tags, the per-platform operations, and how to cross-link a PR to an
item. Resolve the tracker and its context once, up front. The PR side always
goes through `gh` (or the GitHub MCP) regardless of tracker; if the code is not
hosted on GitHub, STOP and report the blocker (see the Known limitations note
in trackers.md).

## Dispatching the pipeline agents

The engineering and review are done by two dedicated agents -
`issue-implementer` and `pr-reviewer`. Their model (`opus`), reasoning effort
(`xhigh`), tool restrictions (the reviewer physically cannot edit code), and
project memory are pinned in their definitions and enforced by the harness, so
you do NOT set those and they cannot silently degrade. Your setup job per
dispatch: give each agent `isolation: "worktree"`, the tracker adapter, and its
parameters.

Build every `Task(...)` dispatch prompt as: the FULL text of `trackers.md`,
then a `Parameters:` block. The agent's role prompt is injected by the harness
- do not repeat it. Every implementer AND every reviewer runs with
`isolation: "worktree"` so parallel branches and check-runs never collide.

## Inputs

Optional `$ARGUMENTS`, in any order:

- A platform word (`github`, `jira`, `asana`) - forces the tracker.
- A space/comma-separated list of item ids - process only those; verify each
  carries `ready-for-dev`, warn and skip any that does not.
- `label=<name>` - override the source tag instead of `ready-for-dev`.
- `panel=<2|3>` - number of reviewers in the review panel (default 2).
- Empty - process every open item tagged `ready-for-dev`.

## Select the queue

List open items with the source tag (see trackers.md). If the source label
does not exist yet (a fresh repo where `/triage` never ran), treat the queue as
empty and report "nothing to ship" rather than erroring. Detect items that
already have a linked PR so a re-run does not double-implement:

- github: search the exact cross-link the implementer writes, not the bare id -
  `gh pr list --state open --search '"Closes #<id>" in:body'` - so a number
  like `42` does not false-match an unrelated PR body.
- jira/asana: check the item's comments/stories for the "Draft PR opened:
  <url>" comment this pipeline posts after implementing (step 1), and confirm
  that PR is still open (`gh pr view <url>`). Also check open PRs for the item,
  in case a prior run died between opening the PR and posting the comment - GH
  search drops punctuation, so do not search a raw URL: search the quoted Jira
  key, or list open PR bodies (`gh pr list --state open --json number,body`)
  and match the Asana task gid locally.

Classify an item with a linked PR instead of skipping it blindly:

- An open **draft** PR resumes at the review-panel stage on its existing
  branch and checks - a run that died mid-pipeline heals on the next run.
- An open **ready** or otherwise finalized PR is in flight with a human:
  report it in the wrap-up and skip.
- A **closed** PR without a merged implementation returns the item to the
  implementation queue, after confirming it still carries the source tag.

Announce new, resumed, and skipped items in the scope list so nothing is
lost silently. Never double-implement an item with an open linked PR.

If the queue is empty, report "nothing to ship" and stop. Otherwise list the
item ids you are about to process so the user sees the scope. Do NOT read full
bodies yourself - the implementer reads each item directly.

## Per-item pipeline

Run this for EVERY queued item. **Parallelize across items** - kick off each
item's implementer in the background and do NOT serialize. Within a single
item the steps are sequential (you cannot review a PR that does not exist
yet), but many items are in flight at once.

1. **Implement.** Dispatch `Task(issue-implementer)` with
   `isolation: "worktree"`, background (trackers.md + the block below):

   > Parameters: mode=A, tracker=<tracker>, context=<...>, item=<id>,
   > title=<title>

   It re-assesses the plan, implements, greens the branch, opens a **draft** PR
   cross-linked to the item, and returns a `RESULT:` line.

   - `BLOCKED` -> record the blocker; skip the rest for this item.
   - `IMPLEMENTED` -> **link the PR on the item** before continuing: post a
     comment on the item pointing at the new PR ("Draft PR opened: <url>", via
     the trackers.md comment operation). Then continue with `pr`, `branch`,
     `checks`, `self_score`.

2. **Adversarial review panel (more than one reviewer, always).** Dispatch a
   PANEL of `Task(pr-reviewer)` agents concurrently, EACH with
   `isolation: "worktree"` (so each reads the branch state in its own tree),
   same trackers.md + the block below, differing only in `lens`. Default 2
   reviewers; `panel=3` adds the third:

   - reviewer 1: `lens=correctness + regressions in callers of changed code`
   - reviewer 2: `lens=tests + acceptance-criteria coverage`
   - reviewer 3 (only when `panel=3`): `lens=security + performance + scope creep`

   > Parameters: tracker=<tracker>, context=<...>, item=<id>, pr=<pr>,
   > branch=<branch>, lens=<lens>

   If the repo has NO CI (`gh pr checks` reports no checks), also pass
   `full_suite=true` to reviewer 1 ONLY - it re-runs the full recorded
   green-check suite (e2e included) serially in its worktree, so exactly one
   reviewer verifies the heavy checks and the others stay on fast checks (no
   parallel e2e contention). This is what makes the no-CI green signal real
   rather than implementer-attested.

   Each reads the diff, confirms green (see the reviewer's CI/no-CI rule),
   posts findings ON the PR, and returns `RESULT: APPROVE` or `REVISE` plus a
   `punch_list`. A reviewer APPROVES when it has ZERO blocking findings (nits
   alone never force REVISE), so the panel converges. Merge the panel: a
   finding is **blocking** if ANY reviewer marks it blocking; dedupe
   overlapping findings and note which the panel raised independently (those
   are the highest-confidence). The panel verdict is REVISE if ANY reviewer
   returns REVISE, else APPROVE.

3. **Decide and address (you own this judgment - bounded to 2 rounds).**
   On a REVISE from the panel, YOU decide which merged findings are worth
   acting on. Read the PR diff and the merged punch-list:

   - Treat **blocking** findings as must-fix by default; a finding multiple
     reviewers raised independently is near-certain - do not wave it off.
     Override only with an explicit reason (the reviewer is wrong - verify
     against the code first).
   - Treat **nits** as optional; accept the cheap/clear ones, skip the rest.
   - For every finding you DECLINE, post a brief reply on the PR saying why, so
     the trail is honest (`gh pr comment <pr> --body "..."`).
   - If you accept >= 1 finding, re-dispatch `Task(issue-implementer)` in mode
     B (`isolation: "worktree"`, background) with parameters: mode=B,
     tracker=<tracker>, context=<...>, item=<id>, pr=<pr>, branch=<branch>, and
     the **filtered** list of accepted items only. Then send the updated PR back
     through the FULL step-2 review panel ONE more time - re-detect no-CI and
     re-assign `full_suite` so the heavy suite runs against the fixed branch,
     not the round-1 code.
   - Bound the loop to **at most 2 address->review rounds**. If blocking
     findings remain after that, stop iterating, leave the PR as draft, ensure
     `needs-human` exists, and retag the item OFF the queue (remove
     `ready-for-dev`, add `needs-human`) - same as the finalize-decline path, so
     it never sits on `ready-for-dev` with an open draft PR - then report it.
     Never loop forever, never flip a PR with unresolved blocking findings.

4. **Finalize - flip draft -> ready.** Only when the PR has **zero unaddressed
   blocking findings AND it is genuinely green**: CI green via
   `gh pr checks <pr>` where the repo has CI, or - when the repo has NO CI
   configured (`gh pr checks` reports no checks) - the designated full-suite
   reviewer (step 2) re-ran the entire recorded green-check suite and it
   passed. A red check is never finalized; "no CI" is not "red"; pending CI is
   waited out, not finalized.

   - Ensure the `in-review` tag exists (idempotent, ignore "already exists"),
     since a fresh repo has none (github: `gh label create ... 2>/dev/null ||
     true`; jira: free-form, nothing to do; asana: per the state mechanism).
   - Retag the item FIRST, before the visible flip, so a decline/failure at the
     flip never leaves a ready PR against a still-`ready-for-dev` item: remove
     `ready-for-dev`, add `in-review` (github/jira via label swap - mind the
     read-then-write MCP semantics; asana via the single-write state
     mechanism).
   - Then flip the PR out of draft: `gh pr ready <pr>`. This is the gate the
     whole pipeline exists to protect. `gh pr ready` is deliberately NOT in the
     project's `permissions.allow` NOR in this skill's `allowed-tools`, so a
     background worker agent auto-denies it and even you, the foreground
     coordinator, get an interactive prompt - the human confirms every flip.
     Never add it to either list, and run `/ship` in the foreground so this
     step is not auto-denied. The flip goes through `gh pr ready` ONLY - never
     through a GitHub MCP pull-request mutation, which would bypass this
     prompt.
   - **If the flip is declined or fails**, do not leave the item mislabeled:
     remove `in-review`, ensure and add `needs-human`, leave the draft PR open,
     and report it as not-finalized - a human then flips or closes it (the
     pipeline does not auto-retry a flip a human declined). Do NOT re-add
     `ready-for-dev`: the still-open draft PR would make every future `/ship`
     skip the item via the linked-PR guard, stranding it.
   - Leave the item open. On a github tracker, `Closes #<n>` closes it on human
     merge; on jira/asana, the human moves the item after merging.

## Wrap-up

Report a single table, `needs-human` / blocked first, with: item (id + link),
title, PR (number + link), checks (green/red), review rounds (e.g. "panel
reviewed, 1 address round"), and final state (`ready` / `needs-human` /
`blocked` / `in-flight` - the last for items skipped at select-queue because a
prior run's PR is still open; give the PR link, leave checks/rounds blank). Do NOT paste diffs or full review bodies back - they live on the
PRs.

## Notes

- Background agents auto-deny anything that would otherwise prompt, so every
  command the workers run must be pre-approved in the project's
  `.claude/settings.json` (`permissions.allow`): the implementer needs git
  write (branch/commit/push/worktree/fetch/checkout), `gh pr
  create/edit/view/checks/comment/diff`, tracker reads, and the project's
  build/test runners; each reviewer needs `gh pr diff/view/checks/review/
  comment`, tracker reads, and the build/test runners (read-only otherwise).
  Project toolchains vary - a repo using cargo, go, gradle, pytest, etc. needs
  those commands allowed too, or the green step silently fails under auto-deny.
- **Worktree isolation keeps parallel work from stomping the filesystem.**
  Dispatch the implementer AND every panel reviewer with `isolation:
  "worktree"`; without it, concurrent workers would collide in one tree. Pushed
  branches and PRs persist; worktrees are cleaned up automatically. Worktrees
  do NOT isolate ports, services, or test databases - that is why reviewers
  confirm green via `gh pr checks` (CI already ran the full suite) rather than
  starting dev servers or running the full e2e suite in parallel.
- On re-dispatch (mode B), a fresh worktree is created - the implementer
  fetches the existing PR branch (by name, or detached with a
  `push HEAD:<branch>` if another worktree still holds it), so the branch
  (which lives on the remote) carries state across rounds, not the worktree.
- `/ship` NEVER merges. The final state is a green, reviewed, ready (non-draft)
  PR; a human merges it.
- This pipeline is expensive by design: per item it is implement + a review
  panel, plus up to 2 address+review rounds. Parallelism across items is what
  keeps wall-clock reasonable - lean into it.
