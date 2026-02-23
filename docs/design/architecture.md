# claude-spectator Architecture

## Problem

Claude Code requires user approval for most Bash commands. Maintaining a large allowlist of individual read-only commands is brittle and hard to scale. We need a way for Claude to run *any* command safely without user intervention.

## Solution

Wrap commands in an OS-level read-only sandbox. The kernel enforces:
- **No file writes** (EPERM at syscall level)
- **No network access** (denied at syscall level)
- **Credential reads blocked** (SSH keys, AWS creds, GPG keys, etc.)
- **All other file reads allowed** (needed for inspection tools)

Since the sandbox is enforced by the OS kernel, it's safe to auto-approve any command prefixed with `sandbox-run`.

## Platform Implementations

### macOS: sandbox-exec

Uses Apple's Sandbox Profile Language (SBPL) via `sandbox-exec -f profile.sb`:

```scheme
(version 1)
(deny default)          ; deny-all baseline
(import "system.sb")    ; allow basic OS operations (dyld, mach ports)
(deny file-read* ...)   ; deny credential paths (first-match wins)
(allow file-read*)      ; allow all other reads
(deny file-write*)      ; deny all writes
(deny network*)         ; deny all network
```

HOME is passed via `sandbox-exec -D HOME=$HOME` so the profile can construct credential paths dynamically.

- **Status**: `sandbox-exec` is marked deprecated but remains functional through macOS Sequoia (15.x)
- **Enforcement**: Kernel-level via Seatbelt sandbox
- **Overhead**: Negligible — same sandbox used by all macOS apps

### Linux: bubblewrap (bwrap)

Uses Linux namespaces via `bwrap`:

```bash
bwrap \
  --ro-bind / /       # Mount entire filesystem read-only
  --dev /dev          # Provide /dev
  --proc /proc        # Provide /proc
  --tmpfs /tmp        # Writable /tmp (isolated)
  --tmpfs ~/.ssh      # Hide credential dirs with empty tmpfs
  --tmpfs ~/.aws      # (repeated for each credential path)
  --unshare-net       # No network namespace
  --die-with-parent   # Clean up if parent dies
  -- "$@"
```

- **Status**: Actively maintained, used by Flatpak
- **Enforcement**: Kernel-level via Linux namespaces
- **Dependency**: Requires `bubblewrap` package (`sudo apt install bubblewrap`)

## Plugin Integration

### Hook: PermissionRequest

The plugin registers a `PermissionRequest` hook that intercepts all permission checks:

```
Claude wants to run "sandbox-run git status"
  → Hook reads JSON from stdin
  → Checks if command starts with "sandbox-run "
  → Rewrites command to "${CLAUDE_PLUGIN_ROOT}/bin/sandbox-run git status"
  → Returns {"behavior": "allow"} with updatedInput — auto-approved
  → Claude proceeds without user prompt
```

For commands already using the full plugin path, the hook approves without rewriting. For non-sandbox commands, the hook returns `{"behavior": "ask"}` to fall through to normal permission flow.

### Hook: Setup

On plugin install, validates platform dependencies and optionally symlinks `sandbox-run` into `~/.local/bin/` for direct shell use. The symlink is not required — the permission hook rewrites bare `sandbox-run` commands to use the plugin's own binary at `${CLAUDE_PLUGIN_ROOT}/bin/sandbox-run`.

### Skill: sandboxed-execution

A model-invoked skill that teaches Claude:
- When to use `sandbox-run` (exploratory/inspection commands)
- When NOT to use it (builds, commits, installs)
- What the sandbox blocks (writes, network)

## Security Model

```
┌─────────────────────────────────────┐
│ Claude Code                         │
│  ┌───────────────────────────────┐  │
│  │ sandbox-run <command>         │  │
│  │  ┌─────────────────────────┐  │  │
│  │  │ OS Sandbox (kernel)     │  │  │
│  │  │  - file-write: EPERM    │  │  │
│  │  │  - network: denied      │  │  │
│  │  │  - cred-read: denied     │  │  │
│  │  │  - file-read: allowed   │  │  │
│  │  │  - process-exec: allowed│  │  │
│  │  └─────────────────────────┘  │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

The sandbox is the **only** enforcement layer. Even if Claude constructs a malicious command, the kernel prevents any damage. This is fundamentally different from pattern-matching allowlists which can be bypassed.

## Credential Protection

Sandboxed commands cannot read known credential paths. Even though network is blocked (preventing direct exfiltration), command output flows back into Claude's conversation context. Blocking reads prevents accidental credential exposure.

**Default blocked paths**: `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.config/gcloud`, `~/.azure`, `~/.kube`, `~/.docker`, `~/.netrc`, `~/.npmrc`, `~/.git-credentials`, `~/.config/gh`, `~/.local/share/keyrings`

**Implementation**:
- **macOS**: SBPL `(deny file-read*)` rules placed before `(allow file-read*)` — first-match wins
- **Linux**: `--tmpfs` mounts over credential directories, hiding contents with empty filesystems

**Customization**: `SPECTATOR_EXTRA_DENY` env var (colon-separated paths, relative to HOME or absolute). On macOS, extra deny rules are inserted into a temporary copy of the profile before the allow-all rule.

## Git Considerations

`git status` may attempt to update the index (stat cache) for performance. Inside the sandbox, this write fails silently — git still works correctly, just without caching stat data for the next run.

Setting `GIT_OPTIONAL_LOCKS=0` prevents git from attempting optional lock files, avoiding noisy error messages.

## Future Extensions

Potential additional tiers (not implemented — keep simple until needed):

| Tier | Writes | Network | Use Case |
|------|--------|---------|----------|
| `sandbox-run` | No | No | Inspection, exploration |
| `sandbox-net` | No | Yes | API checks, downloads |
| `sandbox-build` | CWD only | No | Builds that write output |
