# Tracker adapters for triage and ship

Use this adapter for every tracker operation in the `triage` and `ship` skills. Discover the exact connected tool names at runtime and prefer purpose-built connectors for Jira or Asana. Prefer `gh` for local GitHub work when authenticated; use the GitHub connector when it is the available surface.

Paired file: the claude twin lives at `sbx/claude-kit/files/home/.claude/skills/trackers.md` in the dotfiles repo - keep behavior changes in sync.

## Choose the tracker

1. Use an explicitly named `github`, `jira`, or `asana` tracker.
2. Otherwise inspect applicable `AGENTS.md` and repository docs for a tracker declaration.
3. Otherwise probe read-only context: a GitHub remote plus authenticated GitHub tooling suggests GitHub; connected Jira or Asana tooling suggests those platforms.
4. Ask when more than one tracker remains plausible. In a non-interactive run, choose the strongest evidence and lead the report with the assumption.

Resolve context once:

- GitHub: `owner/repository`.
- Jira: cloud id and project key.
- Asana: workspace and project gid.

Stop when the selected tracker is unavailable or unauthenticated.

## State tags

Use kebab-case labels, tags, a dedicated custom field, or the Asana notes marker described below. Never change a native workflow status, board column, or section.

| Tag | Meaning |
| --- | --- |
| `need-triage` | Raw item waiting for planning |
| `need-grill` | Planned item with unresolved human questions |
| `ready-for-dev` | Reviewed plan ready for implementation |
| `in-review` | Green reviewed PR awaiting human merge |
| `needs-human` | Ship pipeline stopped with unresolved work |

`label=<name>` changes only the source tag for that invocation.

## Operations

### GitHub

- List queue: `gh issue list --label <tag> --state open --json number,title --limit 100`.
- Read item: `gh issue view <id> --json number,title,body,author,labels`.
- Read comments: `gh issue view <id> --comments`.
- Rewrite body: `gh issue edit <id> --body-file <path>`.
- Swap tags: `gh issue edit <id> --remove-label <old> --add-label <new>`.
- Comment: `gh issue comment <id> --body <text>`.
- Ensure tag: `gh label create <tag> --description <text> --color <hex>`; ignore only an already-exists result.

Connector label updates may replace the entire label set. Read current labels and send current minus the old state tag plus the new state tag. Preserve every unrelated label.

### Jira

- List with JQL: `project = <KEY> AND labels = "<tag>" AND statusCategory != Done`.
- Read the issue with comments and labels.
- Rewrite its description with the same markup format that was read.
- Swap state labels by reading the full label set and replacing only the pipeline tag.
- Add comments through the Jira connector.

Jira labels are free-form, so no ensure-tag operation is needed. Never transition the Jira workflow status.

### Asana

- List incomplete tasks in the selected project and filter by the configured state mechanism.
- Read the task and its stories.
- Rewrite notes and comment through the Asana connector.

Choose the first supported writable state mechanism:

1. Native task tags.
2. A dedicated single-select workflow-state custom field.
3. A final notes line with exact syntax `[state: <tag>]`.

For the notes marker:

- Read current notes, remove an existing final state marker and surrounding blank lines, then write the body, one blank line, and exactly one state marker as the final line.
- Combine every body rewrite and state transition into one update. Never write the body and marker separately.
- Build queues by examining the final notes line, not full-text search.
- An explicitly named unmarked task may enter triage; a task already carrying another state marker must be skipped.
- Exclude the marker from the original report preserved by the planner.
- Verify a real write -> list -> rewrite round trip before relying on this fallback in a workspace.

## Cross-link pull requests

Pull requests are GitHub-only even when the tracker is Jira or Asana. Stop when the code is hosted elsewhere.

- GitHub: include `Closes #<id>` in the PR body and comment the PR URL on the issue.
- Jira: put the issue key in the branch and PR title, include the issue URL in the PR body, and comment the PR URL on the issue.
- Asana: include the task URL in the PR body and comment the PR URL as a story.

Jira and Asana items do not close automatically. A human moves them after merge.

## Safety constraints

- Use tracker reads in planner, implementer, and reviewer agents. Keep body rewrites, state changes, and coordinator comments in the foreground coordinator.
- Preserve unrelated labels and fields on every update.
- Never expose tokens, `.env` contents, connector credentials, or GitHub auth material.
- Never force push.
