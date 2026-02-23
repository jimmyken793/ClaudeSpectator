# claude-spectator

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin that provides OS-level read-only sandboxing for safe, auto-approved command execution.

## Problem

Claude Code requires user approval for most Bash commands. Maintaining a large allowlist of individual read-only commands is brittle and hard to scale. A single missed pattern can block legitimate workflows or permit dangerous operations.

## Solution

Instead of allowlists, claudecage wraps commands in an **OS-level read-only sandbox** enforced by the kernel. Any command prefixed with `sandbox-run` is guaranteed to:

- **Read project files** — filesystem visibility for inspection
- **Block credential access** — sensitive paths (`~/.ssh`, `~/.aws`, etc.) denied at kernel level
- **Write nothing** — all writes blocked at the syscall level (EPERM)
- **Access no network** — all network operations blocked

This allows Claude Code to safely auto-approve sandboxed commands without user intervention.

## How It Works

```
Claude Code ─── sandbox-run <cmd> ───▶ OS Sandbox ───▶ Command
                                         │
                                    Kernel enforces:
                                    ✓ file reads
                                    ✗ credential reads
                                    ✗ file writes
                                    ✗ network access
```

**macOS**: Uses `sandbox-exec` with a custom [Sandbox Profile Language](profiles/readonly.sb) (Seatbelt, kernel-enforced).

**Linux**: Uses [`bubblewrap`](https://github.com/containers/bubblewrap) with namespace isolation (read-only bind mounts, no network namespace).

## Installation

Inside a Claude Code session, first add the marketplace:

```
/plugin marketplace add jimmyken793/claude-spectator
```

Then install the plugin:

```
/plugin install claude-spectator@jimmyken793
```

Or install from a local clone:

```
/plugin marketplace add /path/to/claude-spectator
/plugin install claude-spectator@jimmyken793
```

The permission hook automatically rewrites `sandbox-run` commands to use the plugin's own binary, so no PATH setup is required.

The setup hook validates platform dependencies (`sandbox-exec` on macOS, `bwrap` on Linux) and optionally symlinks `sandbox-run` into `~/.local/bin/` for direct shell use.

## Usage

Prefix any read-only command with `sandbox-run`:

```bash
# Git inspection
sandbox-run git status
sandbox-run git log --oneline -20
sandbox-run git diff HEAD~3

# File exploration
sandbox-run find . -name '*.py' -type f
sandbox-run du -sh node_modules/
sandbox-run wc -l src/**/*.ts

# Code analysis
sandbox-run python3 -c "import ast; print(ast.dump(ast.parse(open('main.py').read())))"
sandbox-run grep -r 'TODO' src/
```

Commands that attempt writes or network access will fail:

```bash
sandbox-run touch /tmp/file          # EPERM - write blocked
sandbox-run git commit -m "test"     # EPERM - can't write .git/
sandbox-run curl https://example.com # Network denied
sandbox-run npm install              # EPERM - can't write node_modules/
```

## Auto-Approval

The [permission hook](hooks/permission-check.sh) intercepts all Bash permission requests:

- Commands starting with `sandbox-run ` are **auto-approved** (the sandbox guarantees safety)
- All other commands follow the normal permission flow

## Credential Protection

Sandboxed commands are blocked from reading known credential paths, preventing accidental exposure of secrets through command output.

**Default blocked paths:**

| Path | Contents |
|------|----------|
| `~/.ssh/` | SSH keys, known_hosts |
| `~/.aws/` | AWS credentials, config |
| `~/.gnupg/` | GPG private keys |
| `~/.config/gcloud/` | Google Cloud credentials |
| `~/.azure/` | Azure credentials |
| `~/.kube/` | Kubernetes configs with tokens |
| `~/.docker/` | Docker auth config |
| `~/.netrc` | Plaintext credentials |
| `~/.npmrc` | npm auth tokens |
| `~/.git-credentials` | Git credential store |
| `~/.config/gh/` | GitHub CLI tokens |
| `~/.local/share/keyrings/` | GNOME keyring |

**Adding custom paths:**

Set `SPECTATOR_EXTRA_DENY` with colon-separated paths (relative to `$HOME` or absolute):

```bash
export SPECTATOR_EXTRA_DENY=".config/stripe:.vault-token:/etc/shadow"
```

**Disabling credential blocking:**

Set `SPECTATOR_NO_CRED_BLOCK=1` to disable the default credential path blocking entirely:

```bash
export SPECTATOR_NO_CRED_BLOCK=1
```

## Project Structure

```
claude-spectator/
├── .claude-plugin/
│   └── plugin.json            # Plugin manifest
├── bin/
│   └── sandbox-run            # Cross-platform sandbox wrapper
├── profiles/
│   └── readonly.sb            # macOS sandbox profile
├── hooks/
│   ├── hooks.json             # Hook configuration
│   ├── setup.sh               # Installation setup hook
│   └── permission-check.sh    # Permission auto-approval hook
├── skills/
│   └── sandboxed-execution/
│       └── SKILL.md           # Usage guide for Claude
├── docs/
│   ├── design/
│   │   └── architecture.md    # Architecture & security model
│   └── plans/
│       └── implementation-plan.md
└── test.sh                    # Automated test suite
```

## Testing

Run the test suite:

```bash
./test.sh
```

Tests validate:
- Read-only operations succeed in the sandbox
- Write operations are blocked
- Network operations are blocked
- Credential paths are blocked
- `SPECTATOR_EXTRA_DENY` custom paths are blocked
- Permission hook auto-approves `sandbox-run` commands
- Permission hook rejects non-sandboxed commands

## Platform Support

| Platform | Sandbox Backend | Status |
|----------|----------------|--------|
| macOS | `sandbox-exec` (Seatbelt) | Supported |
| Linux | `bubblewrap` (bwrap) | Supported |

## Support

If you find this useful, buy me a snack:

[![Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/jomican)

## License

[MIT](LICENSE)
