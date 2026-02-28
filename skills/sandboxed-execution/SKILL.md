---
name: sandboxed-execution
description: ALWAYS use for ANY read-only Bash command that is not intended to modify state — ls, cat, find, git log, git status, du, wc, tree, head, tail, file, stat, etc. Prefix with sandbox-run to auto-approve without human intervention.
---

# Sandboxed Command Execution

## When to Use

**ALWAYS** prefix read-only commands with `sandbox-run`. This is the DEFAULT for any Bash command that does not modify state:

```bash
sandbox-run <command> [args...]
```

The permission hook automatically rewrites this to use the plugin's own binary, so `sandbox-run` does not need to be on PATH.

## What the Sandbox Enforces (OS-level)

- **File reads**: allowed (except credential paths)
- **Credential reads**: blocked (`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.kube`, `~/.docker`, etc.)
- **File writes**: blocked (EPERM — kernel-enforced)
- **Network access**: blocked

## Examples

```bash
# Exploration and inspection
sandbox-run git status
sandbox-run git log --oneline -20
sandbox-run python3 -c "import os; print(os.getcwd())"
sandbox-run find . -name '*.py' -type f
sandbox-run wc -l src/**/*.ts
sandbox-run du -sh node_modules/

# These will fail inside the sandbox (as expected)
sandbox-run git commit -m "test"     # EPERM — can't write .git/
sandbox-run npm install              # EPERM — can't write node_modules/
sandbox-run curl https://example.com # network denied
```

## When NOT to Use

Do **not** sandbox commands that need to write files or access the network:

- `git add`, `git commit`, `git push`
- `npm install`, `pip install`, `brew install`
- `make`, `npm run build` (if writing output files)
- `curl`, `wget`, `npm publish`

These should go through the normal permission flow.

## Key Detail

`sandbox-run` is auto-approved — no permission prompt will appear. This is safe because the OS kernel enforces the read-only and no-network constraints regardless of what command is run inside.
