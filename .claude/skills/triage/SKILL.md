---
description: Loop over GitHub issues labelled "need triage" — each is deeply analysed by issue-planner, independently checked by plan-reviewer, then the issue body is rewritten into a fully-specified ticket and relabelled "ready for dev". Use when asked to triage the backlog, work the "need triage" queue, or prepare tickets for development.
argument-hint: "[issue numbers or label override, optional]"
allowed-tools: Task(issue-planner), Task(plan-reviewer), Read, Bash(gh issue list:*), Bash(gh issue view:*), Bash(gh issue edit:*), Bash(gh label create:*), Bash(gh label edit:*), Bash(gh repo view:*), mcp__github
---

# /triage — backlog triage pipeline coordinator

You coordinate an analyse → review → rewrite pipeline over EXISTING GitHub
issues. You do NOT investigate, plan, review, or write issue bodies yourself —
specialists do that in their own contexts on a stronger model. You select the
issues to triage, run each through the pipeline, rewrite the approved issues,
relabel them, and report. Keep your own context lean.

Unlike `/intake`, this flow NEVER creates issues. It only updates issues that
already exist and carry the `need triage` label.

## GitHub access — GitHub MCP or `gh` (interchangeable)

Read and write GitHub through whichever backend the session has, **preferring
the GitHub MCP when it is available** (e.g. on claude.ai/code, where a
first-party GitHub MCP is loaded automatically) and falling back to the `gh`
CLI (local terminal). Every `gh …` command below is annotated with its GitHub
MCP equivalent; if a needed MCP tool isn't present, use the `gh` command.

Verified mapping for the official GitHub MCP server. The web built-in MCP is
undocumented, so discover the actual tool names in-session and adjust (if its
server isn't named `github`, update the `mcp__…` allow entry accordingly):

| Operation                  | `gh`                                           | GitHub MCP                               |
| -------------------------- | ---------------------------------------------- | ---------------------------------------- |
| list issues by label/state | `gh issue list --label … --state open`         | `list_issues` (`labels`, `state`)        |
| read an issue (+ author)   | `gh issue view <n> --json …`                   | `issue_read` method `get`                |
| read issue comments        | `gh issue view <n> --comments`                 | `issue_read` method `get_comments`       |
| read an issue's labels     | —                                              | `issue_read` method `get_labels`         |
| rewrite issue body         | `gh issue edit <n> --body-file f`              | `issue_write` method `update` (`body`)   |
| set issue labels           | `gh issue edit <n> --add-label/--remove-label` | `issue_write` method `update` (`labels`) |
| create a label             | `gh label create …`                            | `label_write` method `create`            |
| resolve repo               | `gh repo view --json nameWithOwner`            | `repository_read` method `get`           |

⚠️ **MCP label gotcha:** `issue_write` `update`'s `labels` REPLACES the issue's
entire label set (no add/remove). On the MCP path you MUST first read the
current labels (`issue_read` `get_labels`), then send the full new set
(current − `need triage` + the outcome label) — otherwise you wipe other labels
like `bug`. The `gh` path uses `--add-label`/`--remove-label`, which is
additive/subtractive and carries no such risk.

## Inputs

- Optional `$ARGUMENTS`:
  - Empty → process every OPEN issue with the `need triage` label.
  - A space/comma-separated list of issue numbers (e.g. `42 51 60`) → process
    only those (still verify each carries `need triage`; warn and skip any that
    doesn't).
  - `label=<name>` → override the source label instead of `need triage`.
- Resolve the repo once up front: `gh repo view --json nameWithOwner -q .nameWithOwner`
  (GitHub MCP: `repository_read` `get`). If neither the GitHub MCP nor an
  authenticated `gh` is available, or there is no repo, STOP and report the blocker.

## Select the queue

```
gh issue list --label "need triage" --state open \
  --json number,title --limit 100
```

(GitHub MCP equivalent: `list_issues` with `labels=["need triage"]`,
`state="open"`.)

If the queue is empty, report "nothing to triage" and stop. Otherwise list the
issue numbers you are about to process so the user can see the scope. Do NOT
fetch full bodies yourself — the planner reads each issue directly.

## Per-issue pipeline

Run this for every queued issue. Different issues' pipelines run concurrently —
kick off each issue's planner in the background and do NOT serialize across
issues.

1. **Analyse.** Dispatch `issue-planner` (`run_in_background: true`) with the
   issue NUMBER and title. The planner reads the issue itself (body + comments)
   via `gh issue view`, investigates the codebase, and writes a proposed
   REPLACEMENT body to `/tmp/triage-issue-<num>.md`. It returns a `RESULT:` line
   — one of `ANALYZED` or `BLOCKED`.
   - `BLOCKED` → record the blocker (issue not found, `gh` unauthenticated, no
     repo). The full body, if any, stays in the planner's reply. Skip the rest.
   - `ANALYZED` → continue with `body_path`, `proposed_status`, `self_score`.

2. **Review.** Dispatch `plan-reviewer` with the `body_path`, the issue number,
   the `proposed_status`, and the `self_score`. It returns `RESULT: APPROVE` or
   `REVISE`.

3. **Revise (at most once).** If `REVISE`, re-dispatch `issue-planner` with the
   reviewer's `punch_list` and instruct it to update the SAME `body_path`, then
   send the updated body back through `plan-reviewer` ONE more time. If it still
   comes back `REVISE`, proceed anyway as `needs-clarification`, folding the
   remaining punch-list into the body's Open Questions section — never silently
   drop an issue, never loop more than once.

4. **Rewrite + relabel.** On `APPROVE` (or the bounded-revision fallback). Each
   step shows the `gh` form and its GitHub MCP equivalent — use whichever the
   session has, preferring the MCP:
   - Ensure labels exist (idempotent, ignore failures) — GitHub MCP:
     `label_write` `create` (ignore "already exists"):
     ```
     gh label create "ready for dev" -c "1D76DB" --description "Triaged: fully-specified, ready to implement" 2>/dev/null || true
     gh label create "need grill" -c "D93F0B" --description "Triaged but confidence < 90% — grill the open questions before dev" 2>/dev/null || true
     ```
   - Replace the issue body with the reviewed draft — GitHub MCP: `issue_write`
     `update` with `body` set to the draft's contents:
     `gh issue edit <num> --body-file <body_path>`
   - Swap the labels based on the final confidence. With `gh` this is
     add/remove. With the GitHub MCP you must FIRST read the issue's current
     labels (`issue_read` `get_labels`) and resend the FULL new set via
     `issue_write` `update` (`labels`) — current **minus** `need triage`
     **plus** the outcome label — because the MCP `labels` field REPLACES the
     whole set and would otherwise drop labels like `bug`:
     - status `ready` (confidence ≥ 90) →
       `gh issue edit <num> --remove-label "need triage" --add-label "ready for dev"`
     - status `needs-clarification` (confidence < 90, open questions remain) →
       `gh issue edit <num> --remove-label "need triage" --add-label "need grill"`
   - On the MCP path you can do the body rewrite and label swap in a single
     `issue_write` `update` call (`body` + the full `labels` set together).

   An issue labelled `need grill` carries an Open Questions section the plan
   couldn't resolve from the code. Resolve those questions (e.g. via the
   `/grill-me` skill or a human design pass), answer them in the issue, then
   re-add `need triage` to send it back through this pipeline for a fresh,
   higher-confidence rewrite.

The planner ALWAYS preserves the reporter's original text as a quoted "Original
report" block at the top of the new body, so replacing the body loses nothing
(and GitHub keeps full edit history regardless).

## Wrap-up

Report a single table, `need grill` first, with: issue (number + link),
title, type, final status, self-score → review-score, and (if revised)
"revised 1x". List blocked issues separately with what each needs. Do NOT paste
full plans back — they live in the issues.

## Notes

- Background subagents auto-deny anything that would otherwise prompt, so every
  command the workers run must be pre-approved in `.claude/settings.json`
  (`permissions.allow`). Both workers need the `gh` read commands and read-only
  `git`; the planner additionally needs `Write(/tmp/**)`; you (the coordinator)
  need `gh issue edit` + `gh label create`/`gh label edit`.
- `gh` must be authenticated (`gh auth status`) for the flow to work.
- **On Claude Code on the web (claude.ai/code):** prefer the **GitHub MCP** —
  its first-party GitHub MCP is loaded automatically, and `issue_write`
  (`update`) + `label_write` cover the body rewrite and labels with no `gh`
  needed. Its exact tool names aren't documented, so if the MCP can't update
  issues / set labels in-session, fall back to `gh`: the CLI is NOT pre-installed
  there, so add `apt update && apt install -y gh` to the cloud environment's
  setup script and provide a `GH_TOKEN` env var (a PAT scoped to this repo's
  Issues: read/write).
- This pipeline is ~2–3× the model calls of a single-stage flow, by design
  (planner + reviewer + occasional revision), in exchange for reviewed,
  implementation-ready tickets.
