# Tracker adapters - shared by /triage and /ship

Both skills coordinate work over items in an issue tracker. Every tracker
operation the pipelines need is defined here once, with the concrete tool per
platform. The coordinators inline this file into each agent dispatch instead of
naming platform commands inline.

Paired file: the codex twin lives at
`sbx/codex-kit/files/home/.agents/references/trackers.md` in the dotfiles
repo - keep behavior changes in sync.

## Picking the tracker

1. If the skill's arguments name one (`github`, `jira`, `asana`), use it.
2. Else check the project's CLAUDE.md for a tracker note (e.g. "tracker: jira,
   project PROJ").
3. Else probe: a GitHub remote plus an authenticated `gh` (or a GitHub MCP)
   suggests github; a connected Jira or Asana MCP suggests those. If more than
   one is plausible, ask the user when interactive; in a background run, pick
   the most likely and lead the final report with that assumption.

Resolve the tracker context ONCE up front and pass it to every subagent:

- github: repo (`gh repo view --json nameWithOwner -q .nameWithOwner`)
- jira: cloudId (`getAccessibleAtlassianResources`) + project key (from
  arguments or the project's CLAUDE.md; if absent, ask)
- asana: workspace + project gid (`asana_list_workspaces`,
  `asana_get_projects` or `asana_typeahead_search`)

If the chosen tracker's tooling is unavailable or unauthenticated, STOP and
report the blocker.

## State tags

Workflow state is a label (GitHub, Jira) or a tag / custom field / notes
marker (Asana, see the asana note) on the item. Kebab-case, because Jira
labels cannot contain spaces:

| tag             | meaning                                             |
| --------------- | --------------------------------------------------- |
| `need-triage`   | raw item, input queue for /triage                   |
| `need-grill`    | triaged, open questions remain - needs a human pass |
| `ready-for-dev` | triaged, fully specified, input queue for /ship     |
| `in-review`     | PR open, green, reviewed, awaiting human merge      |
| `needs-human`   | /ship stalled on blocking findings                  |

`label=<name>` in a skill's arguments overrides that skill's source tag.
Never change an item's native workflow status/column/section - state lives in
these tags only, so the pipelines never fight a project's board setup.

## Operations

Item id means: issue number (github), issue key like PROJ-123 (jira), task gid
(asana). MCP tool names below are the expected ones - discover the actual
names in-session and adapt; if an operation has no tool, use the fallback in
the platform notes.

| operation            | github (`gh` CLI, or GitHub MCP)                        | jira (Atlassian MCP)                                    | asana (Asana MCP)                                  |
| -------------------- | ------------------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------- |
| list queue           | `gh issue list --label <tag> --state open --json number,title --limit 100` | `searchJiraIssuesUsingJql` with `project = <KEY> AND labels = "<tag>" AND statusCategory != Done` | `asana_search_tasks` (project, incomplete), filter by state - see notes |
| read item            | `gh issue view <n> --json number,title,body,author`      | `getJiraIssue`                                           | `asana_get_task`                                    |
| read comments        | `gh issue view <n> --comments`                           | comments come with `getJiraIssue` (request the field)    | `asana_get_stories_for_task`                        |
| rewrite body         | `gh issue edit <n> --body-file <f>`                      | `editJiraIssue` (description)                            | `asana_update_task` (notes)                         |
| swap state tags      | `gh issue edit <n> --remove-label <a> --add-label <b>`   | `editJiraIssue` (labels - read-then-write, see notes)    | native tag / custom field / `[state: <tag>]` marker - see notes |
| comment              | `gh issue comment <n> --body "..."`                      | `addCommentToJiraIssue`                                  | `asana_create_task_story`                           |
| ensure tags exist    | `gh label create <tag> ... 2>/dev/null \|\| true`        | nothing - Jira labels are free-form                      | only if using native tags/custom field - see notes  |

## Platform notes

### github

Prefer the `gh` CLI locally; on claude.ai/code prefer the GitHub MCP (loaded
automatically there; `gh` is not preinstalled). MCP gotcha: `issue_write`
`update`'s `labels` field REPLACES the issue's entire label set. On the MCP
path, first read current labels (`issue_read` `get_labels`), then send the
full new set (current minus old tag plus new tag) - otherwise you wipe labels
like `bug`. The `gh` `--add-label`/`--remove-label` path is additive and safe.

### jira

The `labels` field on edit likewise replaces the whole set: read the issue's
current labels first and send the full new set. Descriptions may come back as
wiki markup, ADF, or markdown depending on the site - mirror the format you
read when writing back. Do not call `transitionJiraIssue`; state lives in
labels.

### asana

Comments are "stories". Asana has no free-form label like GitHub/Jira, so
state needs a writable channel. Probe the loaded Asana MCP in-session and use
the first that works:

1. Native tags, if the MCP exposes add/remove-tag on a task - closest to the
   GitHub/Jira model.
2. A dedicated single-select custom field (e.g. "Workflow state") on the
   project, set via `asana_update_task`, if custom-field writes are available.
3. Fallback marker: the COORDINATOR keeps state on a reserved LAST line of the
   task notes, exact format `[state: <tag>]`. The planner and implementer NEVER
   write this line - they only write the body, and the planner strips any
   trailing `[state: ...]` line before quoting the Original report. Rules that
   keep it consistent:
   - **Single write, read-strip-append.** Any time the coordinator writes the
     task (body rewrite, state change, or both), do it as ONE
     `asana_update_task(notes)` call: read the current notes, strip any
     existing trailing `[state: ...]` line AND the blank lines around it, then
     write `<body>`, one blank line, and exactly one `[state: <tag>]` as the
     final line (so the whitespace never accumulates across transitions). Never
     write the body in one call and the marker in another - a failure between
     them leaves the task stateless and unfindable.
   - **Filter by last line, not search.** Build the queue by listing the
     project's incomplete tasks and checking each task's FINAL notes line for
     `[state: <tag>]`. Do NOT use Asana full-text search for the marker - it
     tokenizes and drops punctuation, so the literal `[state: ...]` will not
     match reliably.
   - **Seeding.** A raw task enters the queue when a human adds
     `[state: need-triage]` as the final notes line, or by passing the task gid
     explicitly to /triage - an explicitly named task counts as tagged ONLY
     when its notes carry no existing `[state: ...]` marker (a task already in
     another state is warned and skipped, same as every platform); the
     coordinator writes the marker on its first update.

Whichever mechanism you use, writing state is the coordinator's job, never the
worker agents', and `[state: <tag>]` appears in exactly one place - never in
the body template. The marker fallback is the least-tested path: verify the
full round-trip (write state -> list queue -> rewrite body -> state survives)
the first time you run against a real Asana project, and prefer options 1-2
when the MCP supports them.

## Cross-linking a PR to an item (/ship only)

The code host is independent of the tracker; PRs go through `gh` (or the
GitHub MCP) either way. If the code is not hosted on GitHub, report BLOCKED -
other hosts are not wired up yet.

- tracker = github: put `Closes #<n>` in the PR body (auto-links and
  auto-closes on merge), and comment the PR URL on the issue.
- tracker = jira: put the issue key (e.g. `PROJ-123`) in the branch name and
  PR title (this powers Jira's GitHub integration where installed), the issue
  URL in the PR body, and comment the PR URL on the issue. Nothing auto-closes:
  the human moves the issue after merging.
- tracker = asana: put the task URL in the PR body and comment the PR URL on
  the task as a story. Nothing auto-closes.

## Safety constraints

- Tracker reads happen in the planner/implementer/reviewer agents; body
  rewrites, state changes, and coordinator comments stay in the foreground
  coordinator.
- Preserve unrelated labels and fields on every update.
- Never expose tokens, `.env` contents, connector credentials, or GitHub auth
  material.
- Never force push.

## Known limitations

- **PR hosting is GitHub-only.** `/ship` opens and reviews PRs through `gh` /
  the GitHub MCP regardless of tracker. On a repo whose code is NOT hosted on
  GitHub (e.g. Bitbucket, GitLab), `/ship` reports BLOCKED. `/triage` is
  unaffected - it never touches the code host. Pairing a non-GitHub tracker
  (Jira, Asana) with GitHub-hosted code is fully supported.
- **Asana state has no native label.** State uses a tag, a custom field, or the
  `[state: <tag>]` notes marker (see the asana note), chosen by what the loaded
  Asana MCP can actually write. Verify the round-trip on first use.
