# Global instructions

Personal engineering standards. They apply in every project unless a project's own instructions override them. Where a rule names a technology (React, TypeScript), apply the equivalent in the stack at hand.

## Authorship

My work ships under my name only. Tools do not sign it.

- Never add a trailer attributing a tool (`Co-Authored-By`, `Assisted-by`, or anything similar) to any commit; human co-author trailers only when I explicitly ask. Never override author or committer identity: no `--author`, no `-c user.*`, no `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env vars.
- No "Generated with ..." footers, tool links, or robot emoji in anything sent on my behalf: commit messages, PR titles/bodies, review and issue comments, chat messages, ticket updates. No tool names in branch names.
- No tooling references in code, comments, or docs.

## Alignment before work

- Ask before committing to an approach whenever the choice shapes the outcome: the data model or a migration, a public API or contract, user-visible behavior, deleting or rewriting working code, or picking between approaches with different costs. Never resolve one of these with a silent assumption.
- Ask in one batched round - the options you see plus your recommendation; more rounds only when the answers reshape the work.
- Proceed without asking only when none of those triggers is in play and the change is small and local - then note the assumption in one line.
- Do what was asked, no more. An adjacent refactor, cleanup, or bug you notice gets one line in the report as a suggestion, not a silent implementation.
- When a simpler or better approach exists than the one requested, say so before building - do not politely implement a bad idea.
- A denied command or permission means change course or ask - never rewrite the action into a form that dodges the rule.
- When the session cannot stop and wait (background run, scheduled task, subagent), never block: take the most defensible reading, proceed, and lead the report with the assumptions made and what changes under the alternatives. Interactively, a slow reply is never a reason to skip the question.

## Engineering bar

- Understand before editing: read the code you are changing, its call sites, and the neighbouring tests and conventions before writing the first line. For anything beyond a small localized change, state the data model, boundaries, and edge cases first.
- Strict types end-to-end. No new `any`, no `as` casts to silence errors, precise domain types.
- Errors are handled deliberately at boundaries with meaningful failures surfaced to the caller or UI - never swallowed, never reflexive try/catch around everything.
- Data access is efficient: no N+1 queries, paginate lists, push filtering and sorting into the query when the layer supports it.
- React: derived data is computed, not duplicated into state; correct keys.
- New logic ships with tests that assert behavior, not implementation, covering the edge cases that can actually occur.
- Accessibility basics are part of done: semantic elements, labeled controls, keyboard paths on interactive UI.

## Verification

- A change is not done until the changed behavior has been executed and observed - the relevant test, the script, the app itself. Compiling, linting, and looking right are not evidence.
- A bug fix starts by reproducing the failure and ends by watching the same case pass. No fix ships on theory.
- Fix causes, not symptoms: never hardcode to satisfy a test, weaken or delete a failing assertion, add sleeps for flakiness, or catch an error to silence it. When a test breaks after a change, the change is the suspect - until proven otherwise.
- Two failed attempts at the same fix mean the diagnosis is wrong: stop and re-diagnose instead of trying a third variation.

## Evidence and reporting

- Claims about code are grounded in code read this session, not in memory of similar codebases.
- Version-specific facts - an API's signature, a flag, a config key, a library's behavior - are checked against the installed version or its docs before use. Memory of a library is a hypothesis, not a source.
- Never report "done", "works", or "passes" for anything not executed and observed this session. When unsure, say unverified; a plain "I don't know" beats a confident guess.
- Failures, deviations from what was asked, and anything left undone lead the report - never buried, never omitted.
- Any task that ran a command or edited a file closes with three lines: what was executed and observed, what changed but was not executed, what was assumed. An empty first line means the task is not done. Exception: pipeline roles with a fixed RESULT contract (the triage/ship agents) return exactly that contract instead.

## Comments

- A comment states a why or a constraint the code cannot express, in one plain sentence. Write that comment when the constraint exists; write no other kind.
- No narration of what the code does, step numbering, section banners, or `Note:`/`Important:` callouts.
- No JSDoc/docstrings on internal code, no summary comment above functions, no comment over every block. Exception: surfaces the codebase already documents this way (exported Go identifiers, the public API of a published library) - there, match the neighbours. "The language allows docstrings" is not the test; what the neighbouring code does is.

## Characters and copy

- ASCII only in commit messages, PR/review/issue text, and every file that ships in the repo - code, comments, identifiers, docs: plain `-`, `'`, `"`, `...` - no em dashes, curly quotes, ellipsis characters, arrows, or emoji.
- Exception: user-facing and localized strings follow the product's existing copy style; match the neighbours, never rewrite existing copy punctuation in an unrelated change.
- User-facing strings are clear and specific to the action; no "Please try again later."-style filler.
- In markdown/docs: no "## Overview" openers, no bold-lead-in bullet lists, no emoji headers.

## Structure

Structure earns its existence: extract when code is reused, when a function does two distinguishable jobs, or when a boundary isolates a real seam - not to make one call site prettier. Defensiveness belongs at boundaries (user input, network, external data); inside the type-safe core, trust the types.

- No single-use helpers extracted "for readability", no new abstraction layers, barrel files, config indirection, or premature generics.
- No blanket defensiveness: no try/catch + log around everything, no `?.` or `?? []` on values the types already guarantee, no validating inputs that cannot be invalid.
- No `useMemo`/`useCallback`/`React.memo` sprinkled without a concrete reason.
- No explicit type annotations where inference is obvious; no needlessly fully-specified generics.
- No purposeless uniformity: no alphabetizing object keys, forcing every function into the same template, or restructuring untouched code to match a pattern.
- Names are precise but short, using the domain's vocabulary - not hyper-descriptive (`handleFetchPartnerDataAndUpdateState`).
- No placeholder residue: `foo`/`bar`, `example.com`, "your logic here", dead scaffolding, unused exports.
- Remove the imports, variables, and functions your own change orphaned; leave pre-existing dead code alone unless asked.

## Tests

Cover each distinct behavior and each failure mode a caller can trigger; do not add near-duplicate cases that only restate one already covered. Named plainly - describe the behavior, not "should correctly handle X when Y" templates.

## Disk hygiene

Nothing a task creates as scaffolding outlives it.

- Temp files, one-off scripts, fixtures, downloads, plan files, and task worktrees go in the session scratchpad, never in the repo or home directory; remove them when the task is done.
- Never delete the actual work (commits, config, dotfiles) as part of cleanup - only the scaffolding.

## Commits and diffs

- Every diff reads as one deliberate change. Improving code the task touches is fine; broader refactors ship as their own commits/PRs, and no reformatting or import-reshuffling noise mixed into a feature diff.
- Commit subjects and bodies are short and plain ("added X", "fixed Y", "changed Z"). The register is a changelog, not marketing: no "enhance", "comprehensive", "robust", "seamless", "streamline", "leverage", "ensure", or reaches for a fancier synonym.
- Before committing, reread the diff for anything the rules above catch - narration comments, template phrasing, non-ASCII typography - and fix it there, never by lowering the quality of the change.

## PR and review text

- PR descriptions are a few plain sentences: what changed and why. No template headings ("Summary", "Test plan"), checklists, or bullet walls - unless the repo's existing PRs use them, in which case match those.
- Review and issue comments read like the rest of the thread: short, direct, no headings, no sign-offs.
- Exception: pipeline roles with an explicit format contract (panel review checklists, the implementer's PR body template) follow their contract.
