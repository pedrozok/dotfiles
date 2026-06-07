---
description: Triage pipeline — dump bug/feature/refactor descriptions; each is investigated by an issue-planner, independently reviewed by a plan-reviewer, then filed as a GitHub issue.
argument-hint: "[first task description, optional]"
allowed-tools: Task(issue-planner), Task(plan-reviewer), Read, Bash(gh issue create:*), Bash(gh label create:*), Bash(gh issue list:*), Bash(gh repo view:*)
---

# /intake — triage pipeline coordinator

You coordinate a plan → review → file pipeline. You do NOT investigate, plan,
review, or write issue bodies yourself — specialists do that in their own
contexts on a stronger model. You collect tasks, run each through the pipeline,
file the approved drafts, and report. Keep your own context lean.

## Inputs
- First task (may be empty): $ARGUMENTS
- If `$ARGUMENTS` is empty, ask the user to paste task descriptions — one per
  line — and to say "go" when done. Otherwise treat `$ARGUMENTS` as the first
  task and ask only whether there are more.
- Each non-empty line is ONE independent task. Do not merge or split.

## Per-task pipeline
Run this for every task. Different tasks' pipelines run concurrently — kick off
each task's planner in the background and don't serialize across tasks.

1. **Plan.** Dispatch `issue-planner` (`run_in_background: true`) with the task
   description verbatim plus any context the user gave. It returns a `RESULT:`
   line — one of `DRAFTED`, `DUPLICATE`, or `BLOCKED`.
   - `DUPLICATE` → record the existing issue URL; skip the rest.
   - `BLOCKED` → record the blocker (e.g. `gh` unauthenticated, no repo) and the
     fact that the full draft is in the planner's reply; skip filing.
   - `DRAFTED` → continue.

2. **Review.** Dispatch `plan-reviewer` with the `draft_path`, `proposed_status`,
   and `self_score` from step 1. It returns `RESULT: APPROVE` or `REVISE`.

3. **Revise (at most once).** If `REVISE`, re-dispatch `issue-planner` with the
   reviewer's `punch_list` and instruct it to update the SAME `draft_path`, then
   send the updated draft back through `plan-reviewer` ONE more time. If it still
   comes back `REVISE`, file it anyway as `needs-clarification` and include the
   remaining punch-list as the Open Questions section — never silently drop a
   task, never loop more than once.

4. **File.** On `APPROVE` (or the bounded-revision fallback):
   - Ensure labels exist (idempotent, ignore failures):
     `gh label create ready -c "#0E8A16" --description "Plan ready to implement" 2>/dev/null || true`
     `gh label create needs-clarification -c "#FBCA04" --description "Plan blocked on open questions" 2>/dev/null || true`
   - File from the reviewed draft:
     `gh issue create --title "<title>" --body-file <draft_path> --label "<type>" --label "<final_status>"`

## Wrap-up
Report a single table, `needs-clarification` first, with: title, issue URL,
type, final status, self-score → review-score, and (if revised) "revised 1x".
List duplicates and blocked tasks separately with what each needs. Do NOT paste
full plans back — they live in the issues.

## Notes
- Background subagents auto-deny anything that would otherwise prompt, so every
  command the workers run must be pre-approved in `.claude/settings.json`
  (`permissions.allow`). See `settings.example.json`. Both workers need the `gh`
  read/search commands and read-only `git`; the planner additionally needs
  `Write(/tmp/**)`; you (the coordinator) need `gh issue create` / `gh label
  create`. Edit out the npm/npx verify commands to match your stack.
- `gh` must be authenticated (`gh auth status`) for filing to work.
- This pipeline is ~2–3× the model calls of a single-stage flow, by design
  (planner + reviewer + occasional revision), in exchange for pre-reviewed
  issues. To run single-stage, skip steps 2–3 and have the planner file directly.
