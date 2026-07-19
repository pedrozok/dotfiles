#!/usr/bin/env python3

import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote_plus


TOOL_NAMES = r"codex|openai|chatgpt|claude|anthropic|gemini|copilot|cursor"
ATTRIBUTION = re.compile(
    rf"co-authored-by:.{{0,80}}({TOOL_NAMES})"
    rf"|assisted-by:.{{0,80}}({TOOL_NAMES})"
    r"|noreply@(openai|chatgpt|anthropic)\.com"
    rf"|generated (with|by).{{0,40}}({TOOL_NAMES})"
    r"|chatgpt\.com/codex|claude\.ai|anthropic\.com|cursor\.com"
    r"|github\.com/features/copilot|copilot\.microsoft\.com|githubcopilot\.com"
    r"|\U0001f916|\\ud83e\\udd16",
    re.IGNORECASE | re.DOTALL,
)
TOOL_BRANCH = re.compile(rf"(?:^|[/_.-])({TOOL_NAMES})(?:$|[/_.-])", re.IGNORECASE)
IDENTITY_VARIABLE = re.compile(r"^GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL|DATE)=", re.IGNORECASE)
READ_ACTION = re.compile(r"(?:^|_)(fetch|get|list|read|search|view|find|status)(?:_|$)")
GIT_OUTBOUND = {"am", "apply", "cherry-pick", "commit", "notes", "push", "rebase", "revert", "send-email", "tag"}
GH_MUTATIONS = {
    "close",
    "comment",
    "create",
    "delete",
    "edit",
    "lock",
    "merge",
    "ready",
    "reopen",
    "review",
    "unlock",
    "update",
}
SHELLS = {"bash", "dash", "ksh", "sh", "zsh"}


def block(reason):
    print(f"Blocked: {reason}", file=sys.stderr)
    raise SystemExit(2)


def contains_attribution(value):
    return bool(ATTRIBUTION.search(value))


def is_policy_path(path):
    normalized = os.path.normpath(path.replace("\\", "/"))
    return normalized in {"codex/AGENTS.md", "codex/hooks/guard.py"} or normalized.endswith(
        ("/.codex/AGENTS.md", "/.codex/hooks/guard.py")
    )


def patch_sections(patch):
    headers = list(
        re.finditer(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$", patch, re.MULTILINE)
    )
    sections = []
    for index, header in enumerate(headers):
        end = headers[index + 1].start() if index + 1 < len(headers) else len(patch)
        section = patch[header.start() : end]
        moved = re.search(r"^\*\*\* Move to: (.+)$", section, re.MULTILINE)
        path = moved.group(1).strip() if moved else header.group(1).strip()
        added = "\n".join(
            line[1:]
            for line in section.splitlines()
            if line.startswith("+") and not line.startswith("+++")
        )
        sections.append((path, added))
    return sections


def scan_file_write(tool_input):
    if not isinstance(tool_input, dict):
        if contains_attribution(json.dumps(tool_input, ensure_ascii=False)):
            block("file content contains prohibited tool attribution")
        return

    path = str(tool_input.get("file_path") or tool_input.get("path") or "")
    patch = str(
        tool_input.get("patch")
        or tool_input.get("command")
        or tool_input.get("input")
        or ""
    )
    if patch and "*** Begin Patch" in patch:
        sections = patch_sections(patch)
        if not sections:
            if contains_attribution(patch):
                block("patch content contains prohibited tool attribution")
            return
        for section_path, added in sections:
            if not is_policy_path(section_path) and contains_attribution(added):
                block(f"added lines for {section_path} contain prohibited tool attribution")
        return

    if not is_policy_path(path) and contains_attribution(
        json.dumps(tool_input, ensure_ascii=False)
    ):
        block("file content contains prohibited tool attribution")


def parse_js_string(source, start):
    quote = source[start]
    if quote not in "'\"`":
        block("wrapped tool input is not a static string")

    escapes = {
        "b": "\b",
        "f": "\f",
        "n": "\n",
        "r": "\r",
        "t": "\t",
        "v": "\v",
        "0": "\0",
    }
    value = []
    index = start + 1
    while index < len(source):
        character = source[index]
        if character == quote:
            return "".join(value), index + 1
        if quote == "`" and character == "$" and index + 1 < len(source) and source[index + 1] == "{":
            block("wrapped tool input uses dynamic template interpolation")
        if character != "\\":
            value.append(character)
            index += 1
            continue
        if index + 1 >= len(source):
            block("wrapped tool input contains an incomplete string escape")
        escaped = source[index + 1]
        if escaped in "\n\r":
            index += 2
            if escaped == "\r" and index < len(source) and source[index] == "\n":
                index += 1
            continue
        if escaped == "x":
            digits = source[index + 2 : index + 4]
            if len(digits) != 2 or not all(character in "0123456789abcdefABCDEF" for character in digits):
                block("wrapped tool input contains an invalid hexadecimal escape")
            value.append(chr(int(digits, 16)))
            index += 4
            continue
        if escaped == "u":
            if index + 2 < len(source) and source[index + 2] == "{":
                end = source.find("}", index + 3)
                digits = source[index + 3 : end] if end != -1 else ""
                if not digits or not all(character in "0123456789abcdefABCDEF" for character in digits):
                    block("wrapped tool input contains an invalid Unicode escape")
                value.append(chr(int(digits, 16)))
                index = end + 1
                continue
            digits = source[index + 2 : index + 6]
            if len(digits) != 4 or not all(character in "0123456789abcdefABCDEF" for character in digits):
                block("wrapped tool input contains an invalid Unicode escape")
            value.append(chr(int(digits, 16)))
            index += 6
            continue
        value.append(escapes.get(escaped, escaped))
        index += 2
    block("wrapped tool input contains an unterminated string")


def wrapped_calls(source):
    calls = []
    references = []
    dynamic = False
    pattern = re.compile(r"\btools\.([A-Za-z_$][A-Za-z0-9_$]*)")
    index = 0
    while index < len(source):
        if source[index] in "'\"`":
            _, index = parse_js_string(source, index)
            continue
        if source.startswith("//", index):
            newline = source.find("\n", index + 2)
            index = len(source) if newline == -1 else newline + 1
            continue
        if source.startswith("/*", index):
            end = source.find("*/", index + 2)
            if end == -1:
                block("wrapped tool script contains an unterminated comment")
            index = end + 2
            continue
        if source.startswith("tools", index) and re.match(r"tools\s*\[", source[index:]):
            dynamic = True
        match = pattern.match(source, index)
        if not match:
            index += 1
            continue
        tool = match.group(1)
        if tool in {"exec_command", "apply_patch"}:
            references.append(tool)
        open_paren = match.end()
        while open_paren < len(source) and source[open_paren].isspace():
            open_paren += 1
        if open_paren >= len(source) or source[open_paren] != "(":
            index = match.end()
            continue
        depth = 1
        cursor = open_paren + 1
        start = cursor
        while cursor < len(source) and depth:
            character = source[cursor]
            if character in "'\"`":
                _, cursor = parse_js_string(source, cursor)
                continue
            if source.startswith("//", cursor):
                newline = source.find("\n", cursor + 2)
                cursor = len(source) if newline == -1 else newline + 1
                continue
            if source.startswith("/*", cursor):
                end = source.find("*/", cursor + 2)
                if end == -1:
                    block(f"wrapped {tool} call contains an unterminated comment")
                cursor = end + 2
                continue
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    calls.append((tool, source[start:cursor]))
                    break
            cursor += 1
        if depth:
            block(f"wrapped {tool} call is not balanced")
        index = open_paren + 1
    return calls, references, dynamic


def js_property_string(arguments, name):
    match = re.search(
        rf"(?:^|[,{{])\s*(?:{re.escape(name)}|['\"]{re.escape(name)}['\"])\s*:\s*",
        arguments,
    )
    if not match or match.end() >= len(arguments):
        block(f"wrapped tool call has no static {name} property")
    return parse_js_string(arguments, match.end())[0]


def js_strings(source):
    values = []
    index = 0
    while index < len(source):
        if source[index] in "'\"`":
            value, index = parse_js_string(source, index)
            values.append(value)
        else:
            index += 1
    return values


def static_js_data(source):
    if "..." in source:
        return False
    parts = []
    index = 0
    while index < len(source):
        if source[index] in "'\"`":
            _, index = parse_js_string(source, index)
            parts.append("")
        else:
            parts.append(source[index])
            index += 1
    remainder = "".join(parts)
    remainder = re.sub(r"\b[A-Za-z_$][A-Za-z0-9_$]*\s*:", "", remainder)
    remainder = re.sub(r"\b(?:true|false|null)\b", "", remainder)
    remainder = re.sub(r"-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", "", remainder)
    return not re.search(r"[^\s{}\[\],:]", remainder)


def scan_wrapped(source, cwd):
    calls, references, dynamic = wrapped_calls(source)
    if dynamic:
        block("wrapped tool selection cannot be inspected safely")

    guarded = {"exec_command", "apply_patch"}
    direct = [name for name, _ in calls if name in guarded]
    if len(references) != len(direct):
        block("wrapped command or patch call is not directly inspectable")

    for tool, arguments in calls:
        if tool == "exec_command":
            scan_script(js_property_string(arguments, "cmd"), cwd)
        elif tool == "apply_patch":
            stripped = arguments.lstrip()
            if not stripped:
                block("wrapped patch input is empty")
            patch = parse_js_string(stripped, 0)[0]
            scan_file_write({"command": patch})
        elif tool.startswith(("mcp__", "app__")):
            values = js_strings(arguments)
            lower_tool = tool.lower()
            if any(name in lower_tool for name in ("create_branch", "update_ref")) and any(
                TOOL_BRANCH.search(value) for value in values
            ):
                block("tool names are forbidden in branch names")
            if not READ_ACTION.search(lower_tool) and not static_js_data(arguments):
                block("outbound wrapped tool input cannot be inspected safely")
            scan_external_tool(tool, {"values": values})


def split_segments(script):
    try:
        lexer = shlex.shlex(script, posix=True, punctuation_chars=";&|()")
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError as error:
        block(f"shell command could not be parsed safely: {error}")

    segments = []
    current = []
    for token in tokens:
        if token and all(character in ";&|()" for character in token):
            if current:
                segments.append(current)
                current = []
        else:
            current.append(token)
    if current:
        segments.append(current)
    return segments


def read_input_file(path, cwd):
    candidate = Path(path)
    if not candidate.is_absolute():
        candidate = Path(cwd) / candidate
    try:
        return candidate.read_text()
    except (OSError, UnicodeError) as error:
        block(f"outbound content file could not be inspected: {candidate}: {error}")


def scan_file_arguments(arguments, cwd, options):
    for index, argument in enumerate(arguments):
        path = None
        if argument in options and index + 1 < len(arguments):
            path = arguments[index + 1]
        else:
            for option in options:
                if argument.startswith(option + "="):
                    path = argument.split("=", 1)[1].lstrip("@")
                    break
            if argument.startswith("body=@"):
                path = argument.removeprefix("body=@")
            elif (
                argument.startswith("-F")
                and not argument.startswith("--")
                and ("=@" in argument or argument[2:].startswith("@"))
            ):
                path = argument[2:]
        if path and "=@" in path:
            path = path.split("=@", 1)[1]
        if path:
            path = path.lstrip("@")
        if path == "-":
            block("outbound content from stdin cannot be inspected safely")
        if path and contains_attribution(read_input_file(path, cwd)):
            block(f"outbound content file contains prohibited tool attribution: {path}")


def git_context(arguments, cwd):
    repo = Path(cwd)
    options_with_values = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}
    global_flags = {
        "-v",
        "--version",
        "-h",
        "--help",
        "-p",
        "--paginate",
        "-P",
        "--no-pager",
        "--html-path",
        "--man-path",
        "--info-path",
        "--no-replace-objects",
        "--no-lazy-fetch",
        "--no-optional-locks",
        "--no-advice",
        "--bare",
        "--literal-pathspecs",
        "--glob-pathspecs",
        "--noglob-pathspecs",
        "--icase-pathspecs",
    }
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        option = argument.split("=", 1)[0]
        if option in options_with_values:
            if "=" in argument:
                value = argument.split("=", 1)[1]
            elif index + 1 < len(arguments):
                value = arguments[index + 1]
                index += 1
            else:
                block(f"Git global option requires a value: {option}")
            if "$" in value or "`" in value:
                block("Git global option values cannot be inspected safely")
            if option == "-C":
                candidate = Path(value)
                repo = candidate if candidate.is_absolute() else repo / candidate
            if option in {"-c", "--config-env"} and value.lower().startswith(
                ("user.name=", "user.email=")
            ):
                block("Git author or committer identity overrides are forbidden")
            index += 1
        elif option == "--exec-path" or option == "--list-cmds":
            index += 1
        elif argument in global_flags:
            index += 1
        elif argument.startswith("-"):
            block(f"Git global option cannot be inspected safely: {argument}")
        else:
            if "$" in argument or "`" in argument:
                block("Git subcommand cannot be inspected safely")
            return repo, argument, arguments[index + 1 :]
    return repo, "", []


def branch_names(command, arguments):
    if command == "branch":
        return [argument for argument in arguments if not argument.startswith("-")][:1]
    if command in {"checkout", "switch"}:
        for index, argument in enumerate(arguments):
            if argument in {"-b", "-B", "-c", "-C"} and index + 1 < len(arguments):
                return [arguments[index + 1]]
    if command == "push":
        names = []
        for argument in arguments:
            if ":" in argument:
                names.append(argument.split(":", 1)[1])
        return names
    return []


def git_output(repo, *arguments):
    result = subprocess.run(
        ["git", "-C", str(repo), *arguments],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def push_remote(repo, requested):
    remotes = git_output(repo, "remote").splitlines()
    if requested:
        if requested in remotes:
            return requested
        for remote in remotes:
            if requested == git_output(repo, "remote", "get-url", remote):
                return remote
        return ""

    branch = git_output(repo, "symbolic-ref", "--quiet", "--short", "HEAD")
    candidates = []
    if branch:
        candidates.extend(
            (
                git_output(repo, "config", "--get", f"branch.{branch}.pushRemote"),
                git_output(repo, "config", "--get", "remote.pushDefault"),
                git_output(repo, "config", "--get", f"branch.{branch}.remote"),
            )
        )
    candidates.extend(remotes if len(remotes) == 1 else [])
    return next((candidate for candidate in candidates if candidate), "")


def local_branches(repo):
    output = git_output(repo, "for-each-ref", "--format=%(refname)", "refs/heads")
    return output.splitlines() if output else []


def matching_branches(repo, remote):
    if not remote:
        return local_branches(repo)
    remote_names = {
        ref.removeprefix(f"refs/remotes/{remote}/")
        for ref in git_output(
            repo, "for-each-ref", "--format=%(refname)", f"refs/remotes/{remote}"
        ).splitlines()
    }
    return [
        ref
        for ref in local_branches(repo)
        if ref.removeprefix("refs/heads/") in remote_names
    ]


def push_scope(repo, arguments):
    options_with_values = {"--exec", "--push-option", "--receive-pack", "--repo", "-o"}
    flags = set()
    positionals = []
    repository_option = ""
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        option = argument.split("=", 1)[0]
        if option in options_with_values:
            flags.add(option)
            if option == "--repo":
                repository_option = (
                    argument.split("=", 1)[1]
                    if "=" in argument
                    else arguments[index + 1] if index + 1 < len(arguments) else ""
                )
            index += 1 if "=" in argument else 2
        elif argument.startswith("-"):
            flags.add(option)
            index += 1
        else:
            positionals.append(argument)
            index += 1

    requested_remote = repository_option or (positionals[0] if positionals else "")
    remote = push_remote(repo, requested_remote)
    refspecs = positionals if repository_option else positionals[1:] if positionals else []
    if "--delete" in flags:
        return remote, [], []

    commits = []
    tags = []
    if "--mirror" in flags:
        commits = ["--all"]
        tags = ["refs/tags"]
    elif "--all" in flags or "--branches" in flags:
        commits = local_branches(repo)
    elif refspecs:
        if refspecs[0] == "tag" and len(refspecs) >= 2:
            tag = f"refs/tags/{refspecs[1]}"
            commits = [tag]
            tags = [tag]
        else:
            for refspec in refspecs:
                source = refspec.lstrip("+").split(":", 1)[0]
                if not source:
                    continue
                commits.append(source)
                resolved = git_output(repo, "rev-parse", "--symbolic-full-name", source)
                if resolved.startswith("refs/tags/"):
                    tags.append(resolved)
    else:
        mode = git_output(repo, "config", "--get", "push.default") or "simple"
        if mode == "matching":
            commits = matching_branches(repo, remote)
        elif mode != "nothing":
            commits = ["HEAD"]

    if "--tags" in flags:
        tag_refs = git_output(repo, "for-each-ref", "--format=%(refname)", "refs/tags")
        tags.extend(tag_refs.splitlines() if tag_refs else [])
        commits.extend(tag_refs.splitlines() if tag_refs else [])
    if "--follow-tags" in flags:
        for commit in commits or ["HEAD"]:
            tag_refs = git_output(repo, "tag", "--merged", commit)
            tags.extend(f"refs/tags/{tag}" for tag in tag_refs.splitlines() if tag)
    return remote, list(dict.fromkeys(commits)), list(dict.fromkeys(tags))


def scan_push_history(repo, arguments):
    remote, commits, tags = push_scope(repo, arguments)
    if not commits and not tags:
        return

    log_arguments = ["log", *commits]
    if remote:
        log_arguments.extend(("--not", f"--remotes={remote}"))
    log_arguments.append("--format=%B")
    log = subprocess.run(
        ["git", "-C", str(repo), *log_arguments],
        capture_output=True,
        text=True,
        check=False,
    )
    tag_messages = ""
    if tags:
        tag_result = subprocess.run(
            ["git", "-C", str(repo), "for-each-ref", "--format=%(contents)", *tags],
            capture_output=True,
            text=True,
            check=False,
        )
        if tag_result.returncode != 0:
            block(f"Git tag scope could not be inspected safely: {repo}")
        tag_messages = tag_result.stdout
    if log.returncode != 0:
        block(f"Git push scope could not be inspected safely: {repo}")
    if contains_attribution(log.stdout) or contains_attribution(tag_messages):
        block("a commit or tag selected for push contains prohibited tool attribution")


def scan_git(arguments, cwd, inherited_identity=False, seen_aliases=None):
    repo, command, command_arguments = git_context(arguments, cwd)
    seen_aliases = set() if seen_aliases is None else seen_aliases
    if inherited_identity or any(IDENTITY_VARIABLE.match(argument) for argument in arguments):
        block("Git author or committer identity overrides are forbidden")
    # --author only overrides identity on commit; on log/shortlog it is a
    # read-only filter. An alias for commit reaches this via expansion below.
    if command == "commit" and any(
        argument == "--author" or argument.startswith("--author=")
        for argument in command_arguments
    ):
        block("Git author or committer identity overrides are forbidden")

    if command == "config":
        for index, argument in enumerate(command_arguments):
            if (
                argument in {"user.name", "user.email"}
                and index + 1 < len(command_arguments)
                and not command_arguments[index + 1].startswith("-")
            ):
                block("Setting git user.name or user.email is forbidden; use the configured identity")

    if command and command not in seen_aliases:
        alias = subprocess.run(
            ["git", "-C", str(repo), "config", "--get", f"alias.{command}"],
            capture_output=True,
            text=True,
            check=False,
        )
        if alias.returncode == 0 and alias.stdout.strip():
            seen_aliases.add(command)
            expansion = alias.stdout.strip()
            if expansion.startswith("!"):
                scan_script(expansion[1:] + " " + shlex.join(command_arguments), str(repo))
            else:
                try:
                    alias_arguments = shlex.split(expansion)
                except ValueError as error:
                    block(f"Git alias could not be inspected safely: {command}: {error}")
                scan_git(alias_arguments + command_arguments, str(repo), inherited_identity, seen_aliases)
            return

    for branch in branch_names(command, command_arguments):
        if TOOL_BRANCH.search(branch):
            block("tool names are forbidden in branch names")

    if command == "push":
        if any("$" in argument or "`" in argument for argument in command_arguments):
            block("Git push arguments cannot be inspected safely")
        if any(
            argument.startswith("--force")
            or argument.startswith("+")
            or (argument.startswith("-") and not argument.startswith("--") and "f" in argument[1:])
            for argument in command_arguments
        ):
            block("force pushes are forbidden")
        scan_push_history(repo, command_arguments)

    if command in GIT_OUTBOUND:
        if command in {"commit", "notes", "tag"} and any(
            "$(" in argument or "`" in argument for argument in command_arguments
        ):
            block("Git metadata substitution cannot be inspected safely")
        if contains_attribution(" ".join(command_arguments)):
            block("Git command contains prohibited tool attribution")
        scan_file_arguments(command_arguments, str(repo), {"-F", "--file"})


def gh_is_mutation(arguments):
    if not arguments:
        return False
    if arguments[0] == "api":
        method = ""
        for index, argument in enumerate(arguments):
            if argument in {"-X", "--method"} and index + 1 < len(arguments):
                method = arguments[index + 1].upper()
            elif argument.startswith("--method="):
                method = argument.split("=", 1)[1].upper()
        return method not in {"", "GET"} or any(
            argument in {"-f", "-F", "--field", "--raw-field", "--input"}
            or argument.startswith(("-f=", "-F=", "--field=", "--raw-field=", "--input="))
            for argument in arguments
        )
    return any(argument in GH_MUTATIONS for argument in arguments[:3])


def scan_gh(arguments, cwd):
    if arguments and arguments[0] == "alias" and any(
        argument in {"set", "import"} for argument in arguments[1:3]
    ):
        block("gh alias creation is forbidden; run the underlying gh command directly")
    if not gh_is_mutation(arguments):
        return
    text = " ".join(arguments)
    if "$(" in text or "`" in text:
        block("outbound GitHub content substitution cannot be inspected safely")
    if contains_attribution(text):
        block("GitHub command contains prohibited tool attribution")
    if any(TOOL_BRANCH.search(argument) for argument in arguments if "/" in argument or ":" in argument):
        block("tool names are forbidden in branch names")
    scan_file_arguments(
        arguments,
        cwd,
        {"--body-file", "--notes-file", "--file", "--input", "--field", "--raw-field", "-F"},
    )


def scan_http(arguments, cwd):
    if contains_attribution(" ".join(arguments)):
        block("outbound HTTP command contains prohibited tool attribution")
    data_options = {"-d", "--data", "--data-binary", "--data-ascii", "--data-urlencode", "-F", "--form", "-T", "--upload-file"}
    file_options = {"--post-file", "--body-file"}
    for index, argument in enumerate(arguments):
        value = None
        forced_file = False
        if argument in file_options and index + 1 < len(arguments):
            value, forced_file = arguments[index + 1], True
        elif argument in data_options and index + 1 < len(arguments):
            value = arguments[index + 1]
        else:
            for option in file_options:
                if argument.startswith(option + "="):
                    value, forced_file = argument.split("=", 1)[1], True
            for option in data_options:
                if argument.startswith(option + "="):
                    value = argument.split("=", 1)[1]
        if value is None:
            continue
        path = value if forced_file else None
        if path is None and "=@" in value:
            path = value.split("=@", 1)[1]
        elif path is None and value.startswith("@"):
            path = value[1:]
        if not path:
            continue
        candidate = Path(path)
        if not candidate.is_absolute():
            candidate = Path(cwd) / candidate
        try:
            content = candidate.read_text()
        except (OSError, UnicodeError):
            # An unreadable or binary upload target is not inspectable text;
            # inline attribution is already caught above.
            continue
        if contains_attribution(content):
            block(f"outbound content file contains prohibited tool attribution: {path}")


def scan_script(script, cwd):
    identity_exported = bool(
        re.search(r"(?:^|[;&|]\s*)export\s+GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL|DATE)=", script)
    )
    current_cwd = Path(cwd)
    for segment in split_segments(script):
        if not segment:
            continue
        if segment[0] == "cd" and len(segment) >= 2:
            candidate = Path(segment[1])
            current_cwd = candidate if candidate.is_absolute() else current_cwd / candidate
            continue

        index = 0
        identity = identity_exported
        while index < len(segment) and "=" in segment[index] and not segment[index].startswith("-"):
            identity = identity or bool(IDENTITY_VARIABLE.match(segment[index]))
            index += 1
        while index < len(segment) and Path(segment[index]).name in {"command", "env", "sudo"}:
            index += 1
            while index < len(segment) and segment[index].startswith("-"):
                index += 1
            while index < len(segment) and "=" in segment[index] and not segment[index].startswith("-"):
                identity = identity or bool(IDENTITY_VARIABLE.match(segment[index]))
                index += 1
        if index >= len(segment):
            continue

        executable = Path(segment[index]).name
        arguments = segment[index + 1 :]
        if executable in SHELLS:
            for option_index, option in enumerate(arguments):
                if "c" in option.lstrip("-") and option.startswith("-") and option_index + 1 < len(arguments):
                    scan_script(arguments[option_index + 1], str(current_cwd))
                    break
        elif executable == "eval":
            scan_script(" ".join(arguments), str(current_cwd))
        elif executable == "xargs" and any(Path(argument).name == "git" for argument in arguments):
            git_index = next(
                offset for offset, argument in enumerate(arguments) if Path(argument).name == "git"
            )
            scan_git(arguments[git_index + 1 :], str(current_cwd), identity)
        elif executable == "git":
            scan_git(arguments, str(current_cwd), identity)
        elif executable == "gh":
            scan_gh(arguments, str(current_cwd))
        elif executable in {"curl", "wget"}:
            scan_http(arguments, str(current_cwd))


def scan_external_tool(tool, tool_input):
    lower_tool = tool.lower()
    serialized = unquote_plus(json.dumps(tool_input, ensure_ascii=False))
    branch_tool = any(name in lower_tool for name in ("create_branch", "update_ref"))
    branch_values = []
    if isinstance(tool_input, dict):
        branch_values = [
            str(value)
            for key, value in tool_input.items()
            if "branch" in str(key).lower() or str(key).lower() in {"ref", "head"}
        ]
    if branch_tool and any(TOOL_BRANCH.search(value) for value in branch_values):
        block("tool names are forbidden in branch names")

    read_only = bool(READ_ACTION.search(lower_tool))
    if lower_tool.startswith("mcp__codex_apps__") and read_only:
        return
    if read_only and not any(name in lower_tool for name in ("browser", "http", "web")):
        return
    if contains_attribution(serialized):
        block("outbound tool input contains prohibited tool attribution")


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        block(f"hook input is not valid JSON: {error}")

    tool = str(payload.get("tool_name") or "")
    tool_input = payload.get("tool_input") or {}
    lower_tool = tool.lower()

    if lower_tool == "functions.exec":
        if not isinstance(tool_input, str):
            block("wrapped tool input is not a script")
        scan_wrapped(tool_input, str(payload.get("cwd") or os.getcwd()))
        return

    if tool == "apply_patch" or lower_tool in {"edit", "write", "notebookedit"}:
        scan_file_write(tool_input)
        return

    command = ""
    if isinstance(tool_input, dict):
        raw_command = tool_input.get("command") or tool_input.get("cmd") or ""
        if isinstance(raw_command, list):
            command = shlex.join(str(part) for part in raw_command)
        else:
            command = str(raw_command)
    if command:
        scan_script(command, str(payload.get("cwd") or os.getcwd()))
        return

    if tool.startswith("mcp__") or tool.startswith("app__"):
        scan_external_tool(tool, tool_input)


if __name__ == "__main__":
    main()
