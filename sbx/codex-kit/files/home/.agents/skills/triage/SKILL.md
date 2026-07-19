---
name: triage
description: Turn existing GitHub, Jira, or Asana items tagged need-triage into independently reviewed, implementation-ready plans using issue-planner and plan-reviewer subagents. Use when asked to triage a backlog, work the need-triage queue, prepare tickets for development, or process named tracker items through planning review.
---

# Triage tracker items

Coordinate an analyze -> review -> rewrite pipeline over existing tracker items. Do not investigate or draft plans in the coordinator context. Keep the main context focused on queue state, subagent results, and tracker mutations.

Never create new items. Process only existing items carrying the source tag.

## Prepare

1. Read `../../references/trackers.md` completely.
2. Parse optional arguments in any order:
   - `github`, `jira`, or `asana` forces the tracker.
   - Item ids restrict the queue; verify each has the source tag.
   - `label=<name>` overrides `need-triage`.
   - `panel=2|3` selects the reviewer count; default to 2.
3. Resolve the tracker and context once using the adapter.
4. List the queue. Treat a missing source label or empty result as "nothing to triage".
5. Announce the item ids before dispatch. Let planners read the full bodies.

Before spawning a role, inspect the available collaboration tool schema. If it exposes a custom-agent selector, select the named agent. If it exposes only a thread `task_name`, read `$CODEX_HOME/agents/<role>.toml` (`~/.codex/agents` when `CODEX_HOME` is unset) and prepend that file's complete `developer_instructions` to the dispatch message. A matching task name alone does not load the role. Use a fresh child context when the API supports it; the injected role, tracker adapter, parameters, repository files, and applicable `AGENTS.md` are sufficient.

## Run each item

Run independent item pipelines concurrently within the session's actual child-thread limit. Reserve the root thread and batch excess work. A three-reviewer panel needs all three child slots in a four-thread session and therefore runs without other children in flight. Each item pipeline is sequential internally.

### Analyze

Spawn the `issue-planner` role using the dispatch rule above. Put the complete tracker adapter and this parameter block in its message:

```text
Parameters: tracker=<tracker>, context=<repo | cloudId+project | workspace+project>, item=<id>, title=<title>, body_path=<temporary-directory>/triage-item-<id>.md
```

Create `body_path` in the session temp directory outside the repository. A blocked result ends this item's pipeline. An analyzed result supplies `body_path`, `proposed_status`, and `self_score`.

### Review

Spawn a concurrent panel of `plan-reviewer` roles using the dispatch rule above. Give each the complete tracker adapter and identical parameters except for its lens:

- `root-cause evidence + plan specificity`
- `test strategy + acceptance criteria + edge cases`
- With `panel=3`: `security + performance + migrations + compatibility`

```text
Parameters: tracker=<tracker>, context=<context>, item=<id>, body_path=<path>, proposed_status=<status>, self_score=<NN>, lens=<lens>
```

Wait for every reviewer. The panel approves only when every reviewer approves. Merge and deduplicate revision items. Use the minimum reviewer score. If any approval returns `needs-clarification`, the aggregate status is `needs-clarification`.

### Revise once

On revision, re-dispatch the same `issue-planner` with the merged punch list and the same `body_path`. Review the updated body with a fresh full panel once.

If the second panel still requests revision, dispatch the planner once with `mode=fold` and the remaining punch list. Do not run another review. The fold must preserve the plan, add the unresolved points as precise questions, and set `needs-clarification`.

### Rewrite and retag

After approval or fold:

- Ensure outcome tags exist where required.
- For `ready`, replace the item body with the reviewed draft, remove the source tag, and add `ready-for-dev`.
- For `needs-clarification`, replace the body, remove the source tag, and add `need-grill`.
- Preserve every unrelated label.
- For Asana marker state, combine the body rewrite and state transition into the adapter's single read-strip-append update.

The coordinator owns every tracker mutation. Subagents only read tracker state and write the temporary draft.

## Finish

Remove temporary draft files. Report one compact table with `need-grill` first: linked item, title, type, final status, self score -> minimum panel score, verdicts, and whether it was revised once. List blocked items separately with the exact requirement to unblock them. Do not paste full plans into chat.
