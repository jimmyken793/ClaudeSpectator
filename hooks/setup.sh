#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINK_DIR="${HOME}/.local/bin"
LINK_TARGET="${LINK_DIR}/sandbox-run"

# Ensure ~/.local/bin exists
mkdir -p "$LINK_DIR"

# Symlink sandbox-run into PATH
ln -sf "${PLUGIN_ROOT}/bin/sandbox-run" "$LINK_TARGET"
echo "claude-spectator: linked ${LINK_TARGET} -> ${PLUGIN_ROOT}/bin/sandbox-run"

# Platform-specific checks
case "$(uname -s)" in
  Darwin)
    if ! command -v sandbox-exec &>/dev/null; then
      echo "Warning: sandbox-exec not found. Expected on macOS." >&2
    fi
    ;;
  Linux)
    if ! command -v bwrap &>/dev/null; then
      echo "Warning: bwrap (bubblewrap) not installed." >&2
      echo "Install with: sudo apt install bubblewrap" >&2
    fi
    ;;
esac

# Check if ~/.local/bin is on PATH
if [[ ":$PATH:" != *":${LINK_DIR}:"* ]]; then
  echo "Note: ${LINK_DIR} is not on your PATH."
  echo "Add to your shell profile: export PATH=\"\${HOME}/.local/bin:\${PATH}\""
fi

echo "claude-spectator: setup complete"
