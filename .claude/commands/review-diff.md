---
description: Code review local uncommitted changes (like /code-review but against git diff instead of a PR)
allowed-tools: Bash(git diff:*), Bash(git status:*), Bash(git log:*), Bash(git rev-parse:*), Bash(git diff-tree:*), Read, Glob, Grep, Agent
---

Provide a code review for all uncommitted local changes (staged + unstaged), using the same rigor as a PR code review.
**Agent assumptions (applies to all agents and subagents):**

- All tools are functional and will work without error. Do not test tools or make exploratory calls.
- Only call a tool if it is required to complete the task. Every tool call should have a clear purpose.
  To do this, follow these steps precisely:

1. Launch a haiku agent to check if there are any uncommitted changes (staged or unstaged). Run `git diff HEAD` and `git status`. If the working tree is clean with no changes, stop and report "No changes to review."
2. Launch a haiku agent to return a list of file paths (not their contents) for all relevant CLAUDE.md files including:
   - The root CLAUDE.md file, if it exists
   - Any CLAUDE.md files in directories containing files modified in the diff
   - The user's global CLAUDE.md at ~/.claude/CLAUDE.md, if it exists
3. Launch a sonnet agent to view the full diff (`git diff HEAD`) and return a summary of the changes. The agent should also return the list of changed files.
4. Launch 4 agents in parallel to independently review the changes. Each agent should return the list of issues, where each issue includes:
   - File path and approximate line number
   - Description of the issue
   - Reason it was flagged (e.g. "CLAUDE.md adherence", "bug", "security", "logic error")
     The agents should do the following:
     Agents 1 + 2: CLAUDE.md compliance sonnet agents
     Audit changes for CLAUDE.md compliance in parallel. When evaluating compliance for a file, only consider CLAUDE.md files that share a file path with the file or its parents.
     Agent 3: Opus bug agent (parallel with agent 4)
     Scan for obvious bugs. Focus only on the diff itself without reading extra context beyond the changed lines. Flag only significant bugs; ignore nitpicks and likely false positives. Do not flag issues that cannot be validated without looking at context outside of the git diff.
     Agent 4: Opus bug agent (parallel with agent 3)
     Look for problems in the introduced code. This could be security issues, incorrect logic, race conditions, unhandled edge cases, etc. Only look for issues within the changed code.
     **CRITICAL: We only want HIGH SIGNAL issues.** Flag issues where:
   - The code will fail to compile or parse (syntax errors, type errors, missing imports, unresolved references)
   - The code will definitely produce wrong results regardless of inputs (clear logic errors)
   - Clear, unambiguous CLAUDE.md violations where you can quote the exact rule being broken
   - Security vulnerabilities (injection, auth bypass, data leaks)
   - Race conditions that will manifest in practice
     Do NOT flag:
   - Code style or quality concerns
   - Potential issues that depend on specific inputs or state
   - Subjective suggestions or improvements
   - Issues that a linter, typechecker, or compiler would catch
   - Pre-existing issues (code that was not changed in this diff)
     If you are not certain an issue is real, do not flag it. False positives erode trust and waste reviewer time.
     Each subagent should be given a summary of the changes (from step 3) for context on the author's intent.
5. For each issue found in the previous step by agents 3 and 4, launch parallel subagents to validate the issue. Use Opus subagents for bugs and logic issues, and sonnet agents for CLAUDE.md violations. Each subagent should:
   - Receive the issue description and the relevant diff context
   - Read the actual file to verify the issue exists in the current code
   - Score the issue on this scale:
     - 0: False positive that doesn't stand up to scrutiny, or a pre-existing issue
     - 25: Might be real, but may also be a false positive. Could not verify.
     - 50: Verified real issue, but might be a nitpick or rare in practice
     - 75: Double-checked and very likely real. Will directly impact functionality, or directly violates CLAUDE.md
     - 100: Confirmed with certainty. Will happen frequently. Evidence directly confirms it.
6. Filter out any issues with a score less than 75.
7. Output the final review to the terminal in this format:

---

If issues were found:

### Diff Review

Found N issues:

1. **[severity]** description — file:line
   Explanation and suggested fix.
2. ...

---

If no issues were found:

### Diff Review

## No issues found. Checked for bugs and CLAUDE.md compliance.
