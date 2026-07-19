---
name: triage
description: Loop over tracker items tagged "need-triage" - each is deeply analysed by an issue-planner agent, then independently checked by a PANEL of plan-reviewer agents, then the item body is rewritten into a fully-specified ticket and retagged "ready-for-dev". Works with GitHub issues, Jira, or Asana. Use when asked to triage the backlog, work the need-triage queue, or prepare tickets for development.
argument-hint: "[github|jira|asana] [item ids] [label=<override>] [panel=2|3]"
allowed-tools: Task(issue-planner), Task(plan-reviewer), Read, Bash(gh issue list:*), Bash(gh issue view:*), Bash(gh issue edit:*), Bash(gh issue comment:*), Bash(gh label create:*), Bash(gh label edit:*), Bash(gh label list:*), Bash(gh repo view:*), Bash(gh search issues:*), mcp__github, mcp__claude_ai_Atlassian, mcp__claude_ai_Asana
---

# /triage - backlog triage pipeline coordinator

You coordinate an analyse -> review -> rewrite pipeline over EXISTING tracker
items. You do NOT investigate, plan, review, or write item bodies yourself -
agents do that in their own contexts. You select the items, run each through
the pipeline, rewrite the approved ones, retag them, and report. Keep your own
context lean.

This flow NEVER creates items. It only updates items that already exist and
carry the `need-triage` tag.

## Tracker access

Read `~/.claude/skills/trackers.md` FIRST. It defines how to pick the tracker
(argument > project CLAUDE.md > probe), the state tags, and the concrete
list/read/rewrite/retag/comment operation per platform. Resolve the tracker
and its context once, up front.

## Dispatching the pipeline agents

The reasoning is done by two dedicated agents - `issue-planner` and
`plan-reviewer`. Their model (`opus`), reasoning effort (`xhigh`), read-only
tool restrictions, and project memory are pinned in their definitions and
enforced by the harness, so you do NOT set those and they cannot silently
degrade. Your only setup job per dispatch: give each agent the tracker adapter
and its parameters.

Build every `Task(...)` dispatch prompt as: the FULL text of `trackers.md`
(so the agent has the operation table for the tracker), then a `Parameters:`
block. The agent's role prompt is injected by the harness - do not repeat it.

## Inputs

Optional `$ARGUMENTS`, in any order:

- A platform word (`github`, `jira`, `asana`) - forces the tracker.
- A space/comma-separated list of item ids (issue numbers, Jira keys, or task
  gids) - process only those; verify each carries `need-triage`, warn and skip
  any that does not.
- `label=<name>` - override the source tag instead of `need-triage`.
- `panel=<2|3>` - number of reviewers in the review panel (default 2).
- Empty - process every open item tagged `need-triage`.

## Select the queue

List open items with the source tag (see trackers.md). If the source label
does not exist yet, or the queue is empty, report "nothing to triage" and stop
(a missing label is an empty queue, not an error). Otherwise list the item ids you are about
to process so the user sees the scope. Do NOT fetch full bodies yourself - the
planner reads each item directly.

## Per-item pipeline

Run this for every queued item. Different items' pipelines run concurrently -
kick off each item's planner in the background and do NOT serialize across
items.

1. **Analyse.** Dispatch `Task(issue-planner)` in the background (trackers.md +
   the block below). Use your session scratchpad directory for `body_path`.

   > Parameters: tracker=<tracker>, context=<repo | cloudId+project | workspace+project>,
   > item=<id>, title=<title>, body_path=<scratchpad>/triage-item-<id>.md

   The planner reads the item, investigates the codebase, writes a proposed
   REPLACEMENT body to `body_path`, and returns `RESULT: ANALYZED` or
   `BLOCKED`.

   - `BLOCKED` -> record the blocker (item not found, tracker unauthenticated,
     no repo). Skip the rest for this item.
   - `ANALYZED` -> continue with `body_path`, `proposed_status`, `self_score`.

2. **Review panel (always more than one reviewer).** Dispatch a PANEL of
   `Task(plan-reviewer)` agents concurrently - same trackers.md + the block
   below, differing only in `lens`. Default 2 reviewers; `panel=3` adds the
   third:

   - reviewer 1: `lens=root-cause evidence + plan specificity`
   - reviewer 2: `lens=test strategy + acceptance criteria + edge cases`
   - reviewer 3 (only when `panel=3`):
     `lens=cross-cutting: security/perf/migrations/back-compat`

   > Parameters: tracker=<tracker>, context=<...>, item=<id>,
   > body_path=<...>, proposed_status=<...>, self_score=<NN>, lens=<lens>

   Each returns `RESULT: APPROVE` or `REVISE`. A plan-reviewer returns REVISE
   only for a real inadequacy (dropped original text, evidence that does not
   hold, hand-waving, inadequate tests) - never for a cosmetic nit, so the
   panel converges. Aggregate: the panel APPROVES only if EVERY reviewer
   APPROVES; ANY REVISE -> REVISE. Union and dedupe the punch-lists;
   `review_score` = MIN across reviewers; the panel `final_status` is
   `needs-clarification` if ANY reviewer returns that, else `ready`.

3. **Revise (at most once).** If the panel says REVISE, re-dispatch the planner
   with the same trackers.md + the block below (the merged, deduped panel
   punch-list), and instruct it to update the SAME `body_path`:

   > Parameters: tracker=<tracker>, context=<...>, item=<id>,
   > body_path=<...>, punch_list=<merged list>

   Then send the updated body back through the panel ONE more time. If it still
   comes back REVISE, do NOT loop again: re-dispatch the planner a final time
   with `mode=fold` (this is a formatting pass, not a review round):

   > Parameters: mode=fold, tracker=<tracker>, context=<...>, item=<id>,
   > body_path=<...>, punch_list=<remaining list>

   The planner sets status `needs-clarification`, moves every remaining
   punch-list item into the body's Open Questions section, and rewrites
   `body_path`. A fold ALWAYS results in `final_status=needs-clarification` ->
   the item is tagged `need-grill` in step 4; the unresolved items are captured,
   never silently dropped.

4. **Rewrite + retag.** On APPROVE (or the bounded-revision fallback), using
   the trackers.md operations:
   - Ensure the outcome tags exist where the platform needs it (idempotent,
     ignore "already exists").
   - Determine the outcome status: a `mode=fold` fallback is ALWAYS
     `needs-clarification`; otherwise use the panel's `final_status` - NOT the
     score alone, since a reviewer can APPROVE at score >= 90 yet still return
     `needs-clarification` for a genuine open question.
   - Write the reviewed draft body AND swap the tags (mind the read-then-write
     label semantics on the MCP paths):
     - `ready` -> body = draft; remove `need-triage`, add `ready-for-dev`
     - `needs-clarification` -> body = draft; remove `need-triage`, add
       `need-grill`
   - **Asana:** the body write and the state swap are the SINGLE
     read-strip-append `asana_update_task(notes)` call defined in trackers.md -
     never a body write followed by a separate state write.

   An item tagged `need-grill` carries an Open Questions section the plan
   could not resolve from the code. Resolve those questions (e.g. via the
   `/grill-me` skill or a human design pass), answer them on the item, then
   re-add `need-triage` (and remove `need-grill`) to send it back through this
   pipeline for a fresh, higher-confidence rewrite.

The planner ALWAYS preserves the reporter's original text as a quoted
"Original report" block at the top of the new body, so replacing the body
loses nothing.

## Wrap-up

Report a single table, `need-grill` first, with: item (id + link), title,
type, final status, self-score -> panel-score (min), reviewer verdicts, and (if
revised) "revised 1x". List blocked items separately with what each needs. Do
NOT paste full plans back - they live on the items.

## Notes

- Background agents auto-deny anything that would otherwise prompt, so the
  tracker reads they run (plus read-only `git` and the scratchpad write) must
  be pre-approved in the project's `.claude/settings.json` `permissions.allow`.
  You (the coordinator) own all tracker writes.
- The panel is 2-3x the reviewer cost of a single-reviewer flow, by design -
  independent lenses catch what one reviewer misses. Scale the panel to the
  risk (2 default, 3 for large changes).
