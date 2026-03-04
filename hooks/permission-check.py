#!/usr/bin/env python3
"""
Permission hook for claude-spectator sandbox.

Rewrites sandbox-run commands to use the plugin's binary and wraps
arguments in bash -c with shlex.quote() so shell metacharacters
(pipes, redirections, semicolons, etc.) execute INSIDE the sandbox.

Workaround for https://github.com/anthropics/claude-code/issues/15897:
updatedInput is broken when multiple PreToolUse hooks exist, so we use
deny+reason to force Claude to retry with the rewritten command, then
allow the full-path version on retry.
"""

import json
import os
import shlex
import sys


def get_plugin_root():
    """Resolve the plugin root directory."""
    if len(sys.argv) > 1 and sys.argv[1]:
        return sys.argv[1]
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(script_dir)


LOG_FILE = os.path.join(os.path.expanduser("~"), ".claude", "spectator-debug.log")


def debug(msg):
    """Write debug message to stderr AND a log file for diagnosis."""
    print(f"[claude-spectator] {msg}", file=sys.stderr)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"[claude-spectator] {msg}\n")
    except OSError:
        pass


def main():
    try:
        raw = sys.stdin.read()
        debug(f"stdin: {raw[:200]}")
        request = json.loads(raw)
    except (json.JSONDecodeError, ValueError) as e:
        debug(f"JSON parse error: {e}")
        return

    tool_name = request.get("tool_name", "")
    command = request.get("tool_input", {}).get("command", "")

    debug(f"tool_name={tool_name!r} command={command[:100]!r}")

    if tool_name != "Bash":
        return

    plugin_root = get_plugin_root()
    if not plugin_root:
        debug("no plugin_root resolved, skipping")
        return
    sandbox_bin = os.path.join(plugin_root, "bin", "sandbox-run")

    # Case 1: Full-path sandbox-run command → allow directly
    if command == sandbox_bin or command.startswith(sandbox_bin + " "):
        result = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": "sandbox-run auto-approved by claude-spectator",
            }
        }
        debug(f"ALLOW full-path command")
        sys.stdout.write(json.dumps(result) + "\n")
        sys.stdout.flush()
        return

    # Case 2: Bare "sandbox-run" command → deny with rewritten command
    if command == "sandbox-run" or command.startswith("sandbox-run "):
        sandbox_args = command[len("sandbox-run"):].lstrip()
        if sandbox_args:
            rewritten = sandbox_bin + " bash -c " + shlex.quote(sandbox_args)
        else:
            rewritten = sandbox_bin

        result = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    f"sandbox-run is not in PATH. "
                    f"Use the full path instead: {rewritten}"
                ),
            }
        }
        debug(f"DENY bare sandbox-run, suggesting: {rewritten[:100]}")
        sys.stdout.write(json.dumps(result) + "\n")
        sys.stdout.flush()
        return

    debug(f"not a sandbox-run command")


try:
    main()
finally:
    sys.exit(0)
