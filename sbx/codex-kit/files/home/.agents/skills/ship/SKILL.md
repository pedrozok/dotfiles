---
name: ship
description: Implement existing GitHub, Jira, or Asana items tagged ready-for-dev through isolated issue-implementer agents, adversarial pr-reviewer panels, bounded fix rounds, and a final draft-to-ready gate. Use when asked to ship the backlog, implement the ready-for-dev queue, or turn triaged tickets into reviewed pull requests without merging them.
---

# Ship ready tracker items

Coordinate an implement -> review -> address -> ready pipeline. Keep implementation and review work in named subagents and keep the coordinator focused on queue state, judgment, and external mutations. Never merge a pull request.

## Prepare

1. Read `../../references/trackers.md` completely.
2. Parse optional arguments in any order:
   - `github`, `jira`, or `asana` forces the tracker.
   - Item ids restrict the queue; verify each has the source tag.
   - `label=<name>` overrides `ready-for-dev`.
   - `panel=2|3` selects the reviewer count; default to 2.
3. Resolve the tracker and context once. Confirm the code is hosted on GitHub.
4. List the source queue. Treat a missing label as an empty queue.
5. Detect in-flight work before dispatch:
   - For GitHub, search open PR bodies for the exact `Closes #<id>` link.
   - For Jira and Asana, inspect item comments for `Draft PR opened: <url>`, verify that PR is open, and search open PR bodies for the Jira key or Asana gid when a prior run may have stopped before commenting.
6. Classify an item with an open linked PR:
   - A draft PR resumes at the review-panel stage using its current branch and checks.
   - A ready or otherwise finalized PR is reported as in flight and skipped.
   - A closed PR without a merged implementation returns to the implementation queue only after confirming the tracker still carries the source tag.
7. Announce new, resumed, and skipped items. Never double-implement an item with an open linked PR.

Before spawning a role, inspect the available collaboration tool schema. If it exposes a custom-agent selector, select the named agent. If it exposes only a thread `task_name`, read `$CODEX_HOME/agents/<role>.toml` (`~/.codex/agents` when `CODEX_HOME` is unset) and prepend that file's complete `developer_instructions` to the dispatch message. A matching task name alone does not load the role. Use a fresh child context when the API supports it; the injected role, tracker adapter, parameters, repository files, and applicable `AGENTS.md` are sufficient.

## Run each item

Codex subagents share the filesystem and some spawn APIs provide neither a working directory nor hard worktree isolation. Create a distinct temporary Git worktree for every implementer and reviewer, pass its absolute path in the dispatch, and remove it after that agent finishes.

Honor the session's actual child-thread limit and reserve the root thread. Batch excess work. A three-reviewer panel occupies every child slot in a four-thread session. When the spawn API cannot enforce the child working directory, first confirm that every available edit surface accepts absolute target paths. If any required edit surface cannot target the temporary worktree, block the write-heavy dispatch. Otherwise run implementers one at a time, require absolute edit paths under the supplied worktree, capture the coordinator worktree's status before dispatch, and verify it is byte-for-byte unchanged afterward. Stop on any unexpected coordinator-worktree change; never clean it up automatically.

### Implement

Create a detached worktree from the current remote default branch under the session temp directory. Spawn the `issue-implementer` role using the dispatch rule above and give it the complete tracker adapter plus:

```text
Parameters: mode=A, tracker=<tracker>, context=<context>, item=<id>, title=<title>, worktree=<absolute path>
```

Tell the agent to run commands in that worktree and use absolute paths under it for every edit. On `BLOCKED`, record the blocker and stop that item. On `IMPLEMENTED`, immediately comment `Draft PR opened: <url>` on the tracker item, then continue with the returned PR, branch, checks, and score. Verify the coordinator worktree is unchanged. Remove the temporary worktree after the agent finishes; the pushed branch and PR carry state.

### Review panel

For new or resumed draft PRs, fetch the branch and create one detached temporary worktree at `origin/<branch>` per reviewer. Spawn a concurrent panel of `pr-reviewer` roles using the dispatch rule above. Give each the complete tracker adapter, its worktree path, and one lens:

- `correctness + regressions in callers`
- `tests + acceptance-criteria coverage`
- With `panel=3`: `security + performance + scope creep`

```text
Parameters: tracker=<tracker>, context=<context>, item=<id>, pr=<pr>, branch=<branch>, worktree=<absolute path>, lens=<lens>, full_suite=<true|false>
```

Tell every reviewer to run all commands in its supplied worktree. Wait for every reviewer, then remove the panel worktrees. When the repository has no CI, set `full_suite=true` only for the first reviewer so exactly one worktree runs the full recorded suite. Other reviewers run fast checks only.

Merge duplicate findings. A finding is blocking if any reviewer marks it blocking. Note independently repeated findings as high-confidence. The panel requests revision if any reviewer requests revision.

### Decide and address

Inspect every non-empty panel punch list, including nits from an approving panel:

- Accept blocking findings by default. Decline one only after verifying it is wrong, and post the reason on the PR.
- Accept cheap, clear nits; decline the rest with a short PR comment.
- If at least one finding is accepted, fetch the PR branch, create a new detached temporary worktree at `origin/<branch>`, and re-dispatch the `issue-implementer` role there using the dispatch rule above:

```text
Parameters: mode=B, tracker=<tracker>, context=<context>, item=<id>, pr=<pr>, branch=<branch>, worktree=<absolute path>, punch_list=<accepted findings>
```

Require absolute edits under the supplied worktree and verify the coordinator worktree remains unchanged. Remove the temporary worktree after the agent finishes. Run a fresh full review panel after any code change, including an accepted nit. Re-detect CI and reassign the single full-suite reviewer when needed. Declined nits do not require another round.

Allow at most two address -> review rounds. If blocking findings remain, keep the PR draft, ensure `needs-human` exists, remove `ready-for-dev`, add `needs-human`, and report the unresolved findings. Never loop indefinitely.

### Finalize

Finalize only with zero unresolved blocking findings and a real green signal: green CI, or the designated no-CI reviewer observed the complete recorded suite pass.

1. Ensure both `in-review` and `needs-human` exist.
2. Retag the tracker item first: remove `ready-for-dev`, add `in-review`, preserving unrelated labels.
3. Run `gh pr ready <pr>` in the foreground. Never use a connector mutation for this gate.
4. If the user declines or the command fails, remove `in-review`, add `needs-human`, leave the draft open, and report the failure. Do not re-add `ready-for-dev` because the open-PR guard would strand it.
5. Leave the item open. GitHub closes through `Closes #<id>` on human merge; Jira and Asana remain for the human to move after merge.

Force pushes remain forbidden throughout. Use new commits or a new branch when history needs correction.

Use `git worktree remove <path>` for cleanup after confirming the agent has finished. If cleanup reports uncommitted work, stop and preserve the worktree instead of forcing removal.

## Finish

Report one compact table with `needs-human` and blocked items first: linked item, title, linked PR, checks, review rounds, and final state. Include in-flight items skipped during queue selection. Do not paste diffs or full review bodies into chat.
