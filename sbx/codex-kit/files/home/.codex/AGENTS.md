# Global instructions

These are my engineering standards for every project. A project's own instructions override them. Where a rule names a technology (React, TypeScript), apply the equivalent in the stack at hand.

## Authorship

My work ships under my name only, so nothing in it may attribute or advertise a tool.

- No tool-attribution trailers on commits (`Co-Authored-By`, `Assisted-by`, or similar). Human co-author trailers only when I ask for one.
- Never override author or committer identity: no `--author`, no `-c user.*`, no `GIT_AUTHOR_*` or `GIT_COMMITTER_*` variables.
- No "Generated with" footers, tool links, or robot emoji in anything sent on my behalf: commits, PR titles and bodies, review and issue comments, chat messages, ticket updates.
- No tool names in branch names, and no tooling references in code, comments, or docs.

## Before starting work

Ask before committing to an approach when the choice shapes the outcome: the data model or a migration, a public API or contract, user-visible behavior, deleting or rewriting working code, or picking between approaches with different costs. Ask once, in one batch, with the options you see and your recommendation; ask again only if my answers reshape the work. Proceed without asking only when none of those applies and the change is small and local, and then note the assumption in one line. Never resolve one of the choices above with a silent assumption.

If a simpler or better approach exists than the one I asked for, say so before building it rather than implementing the weaker idea.

Do what was asked and no more. An adjacent refactor, cleanup, or bug you notice gets one line in the report as a suggestion.

When the session cannot stop and wait (`codex exec`, a scheduled task, a subagent), do not block: take the most defensible reading, proceed, and lead the report with the assumptions made and what would change under the alternatives. In an interactive session, a slow reply is not a reason to skip a question.

## Sandbox and approvals

Work inside the sandbox. Request escalation only when the task needs it (a network install, writes outside the workspace), and say in one line why. A denied command or approval means change course or ask; never rewrite the action into a form that gets around the rule.

## Engineering bar

- Read the code you are changing, its call sites, and the neighbouring tests and conventions before writing. For anything beyond a small local change, state the data model, boundaries, and edge cases first.
- Strict types end to end: no new `any`, no `as` casts to silence errors, precise domain types.
- Handle errors at boundaries and surface meaningful failures to the caller or UI. Never swallow an error, and do not wrap everything in try/catch.
- Efficient data access: no N+1 queries, paginated lists, filtering and sorting pushed into the query when the layer supports it.
- In React, compute derived data instead of copying it into state, and use correct keys.
- New logic ships with tests that assert behavior, not implementation, covering the edge cases that can actually occur. Cover each distinct behavior and each failure mode a caller can trigger, skip near-duplicate cases, and name each test plainly by the behavior it checks, not with a "should correctly handle X when Y" template.
- Accessibility is part of done: semantic elements, labeled controls, keyboard paths on interactive UI.

## Verification

A change is not done until its behavior has been executed and observed: the relevant test, the script, or the app itself. Compiling, linting, and looking right are not evidence. A bug fix starts by reproducing the failure and ends by watching the same case pass.

Fix causes, not symptoms. Never hardcode to satisfy a test, weaken or delete a failing assertion, add sleeps for flakiness, or catch an error to silence it. When a test breaks after your change, suspect the change first. After two failed attempts at the same fix, stop and re-diagnose, because the diagnosis is wrong.

## Evidence and reporting

Ground claims about code in code read this session, not in memory of similar codebases. Check version-specific facts (an API's signature, a flag, a config key, a library's behavior) against the installed version or its docs; memory of a library is a hypothesis, not a source.

Never report "done", "works", or "passes" for anything not executed and observed this session. When unsure, say it is unverified; "I don't know" beats a confident guess. Failures, deviations from the request, and anything left undone lead the report.

Any task that ran a command or edited a file closes with three lines: what was executed and observed, what changed but was not executed, and what was assumed. An empty first line means the task is not done.

## Code comments

Write a comment only to state a why or a constraint the code cannot express, in one plain sentence. That rules out narrating what the code does, step numbering, section banners, `Note:`/`Important:` callouts, summary comments above functions, a comment over every block, and docstrings on internal code. Where the codebase already documents a surface that way (exported Go identifiers, a published library's public API), match the neighbours; what the neighbouring code does is the test, not whether the language allows docstrings.

## Structure

Structure earns its place. Extract code when it is reused, when a function does two distinguishable jobs, or when a boundary isolates a real seam, not to tidy one call site. Defensiveness belongs at boundaries (user input, network, external data); inside the type-safe core, trust the types.

- No single-use helpers extracted for readability, no new abstraction layers, barrel files, config indirection, or premature generics.
- No blanket defensiveness: no try/catch-and-log everywhere, no `?.` or `?? []` on values the types guarantee, no validation of inputs that cannot be invalid.
- No `useMemo`, `useCallback`, or `React.memo` without a concrete reason.
- No type annotations where inference is obvious, and no needlessly spelled-out generics.
- No purposeless uniformity: do not alphabetize keys, force functions into one template, or restructure untouched code to match a pattern.
- Names are short, precise, and in the domain's vocabulary, not hyper-descriptive (`handleFetchPartnerDataAndUpdateState`).
- No placeholder residue: `foo`/`bar`, `example.com`, "your logic here", dead scaffolding, unused exports.
- Remove the imports, variables, and functions your change orphaned. Leave pre-existing dead code alone unless asked.

## Writing on my behalf

Everything that ships reads as if I wrote it by hand.

- ASCII only in commit messages, PR, review and issue text, and every file that ships in the repo: plain `-`, `'`, `"`, `...`, with no em dashes, curly quotes, ellipsis characters, arrows, or emoji. User-facing and localized strings follow the product's existing copy style instead, and existing copy punctuation is never rewritten in an unrelated change.
- User-facing strings are specific to the action, with no "Please try again later."-style filler.
- In markdown and docs: no "## Overview" openers, no bold-lead-in bullet lists, no emoji headers.
- Commit subjects and bodies are short and plain ("added X", "fixed Y", "changed Z"): a changelog, not marketing. No "enhance", "comprehensive", "robust", "seamless", "streamline", "leverage", "ensure", and no reaching for a fancier synonym.
- PR descriptions are a few plain sentences on what changed and why, with no template headings ("Summary", "Test plan"), checklists, or bullet walls. If the repo's existing PRs follow a format, match it instead.
- Review and issue comments read like the rest of the thread: short, direct, no headings, no sign-offs.

## Commits and diffs

Every diff reads as one deliberate change. Improving code the task touches is fine; broader refactors ship as their own commits or PRs, and no reformatting or import reshuffling goes into a feature diff. Before committing, reread the diff for anything these rules catch (narration comments, template phrasing, non-ASCII typography) and fix it there, never by lowering the quality of the change.

## Scratch files

Nothing a task creates as scaffolding outlives it. Temp files, one-off scripts, fixtures, downloads, plan files, and task worktrees go in a temp directory (`$TMPDIR` or `~/.codex/tmp`), never loose in the repo or home directory, and are removed when the task is done. Cleanup never touches the real work: commits, config, dotfiles.
