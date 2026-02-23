# Plan: claude-spectator — Claude Code Plugin for Sandboxed Command Execution

## Context

Claude Code needs a way to run arbitrary commands safely without user prompts. Instead of maintaining a brittle allowlist of individual commands, we wrap commands in an OS-level read-only sandbox. The sandbox guarantees no file writes or network access at the kernel level.

Packaging this as a **Claude Code plugin** makes it installable on any machine with a single command, portable across macOS and Linux, and cleanly integrated via hooks — no manual settings.json editing required.

## Plugin Structure

```
claude-spectator/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── hooks/
│   ├── hooks.json               # Hook configuration
│   ├── setup.sh                 # Setup hook: symlink sandbox-run into PATH
│   └── permission-check.sh      # PermissionRequest hook: auto-approve sandbox-run
├── skills/
│   └── sandboxed-execution/
│       └── SKILL.md             # Tells Claude when/how to use sandbox-run
├── bin/
│   └── sandbox-run              # Cross-platform wrapper (macOS + Linux)
├── profiles/
│   └── readonly.sb              # macOS sandbox-exec profile
├── docs/
│   ├── design/                  # Architecture and design docs
│   └── plans/                   # Implementation plans
├── test.sh                      # Automated test suite
└── README.md
```

## Implementation Order

1. Create project directory and `git init`
2. Write `.claude-plugin/plugin.json`
3. Write `profiles/readonly.sb`
4. Write `bin/sandbox-run`, make executable
5. Write `hooks/hooks.json`
6. Write `hooks/setup.sh`, make executable
7. Write `hooks/permission-check.sh`, make executable
8. Write `skills/sandboxed-execution/SKILL.md`
9. Write `test.sh`, run verification tests
10. Add credential path blocking to sandbox profile and sandbox-run
11. Add `SPECTATOR_EXTRA_DENY` env var support for custom deny paths
12. Add credential blocking tests
13. Write `README.md` and `LICENSE`
14. Commit and push

## Status

All steps completed. 24/24 tests passing.
