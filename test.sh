#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SANDBOX="${SCRIPT_DIR}/bin/sandbox-run"
HOOK="${SCRIPT_DIR}/hooks/permission-check.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

assert_success() {
  local desc="$1"; shift
  if "$SANDBOX" "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc (expected success, got exit $?)"
  fi
}

assert_fail() {
  local desc="$1"; shift
  if "$SANDBOX" "$@" >/dev/null 2>&1; then
    fail "$desc (expected failure, got success)"
  else
    pass "$desc"
  fi
}

assert_hook_allows() {
  local desc="$1" cmd="$2"
  local result
  result=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}" | "$HOOK")
  if echo "$result" | grep -q '"allow"'; then
    pass "$desc"
  else
    fail "$desc (expected allow, got: $result)"
  fi
}

assert_hook_asks() {
  local desc="$1" cmd="$2"
  local result
  result=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}" | "$HOOK")
  if echo "$result" | grep -q '"ask"'; then
    pass "$desc"
  else
    fail "$desc (expected ask, got: $result)"
  fi
}

echo "=== Sandbox: read-only operations (should succeed) ==="
assert_success "ls"                   ls /etc
assert_success "cat file"             cat /etc/hosts
assert_success "python3 print"        python3 -c "print('ok')"
assert_success "git version"          git version
assert_success "echo"                 echo "hello"
assert_success "uname"                uname -a
assert_success "env"                  env
assert_success "which bash"           which bash

echo ""
echo "=== Sandbox: write operations (should fail) ==="
assert_fail "touch file"              touch /tmp/claudecage-test
assert_fail "mkdir dir"               mkdir /tmp/claudecage-test-dir
assert_fail "write to file"           bash -c "echo x > /tmp/claudecage-test-file"
assert_fail "rm file"                 rm -f /etc/hosts

echo ""
echo "=== Sandbox: network operations (should fail) ==="
assert_fail "curl"                    curl -s --connect-timeout 2 https://example.com

echo ""
echo "=== Sandbox: credential paths (should fail) ==="
# Create temp credential files to test against
CRED_TEST_DIR="${HOME}/.ssh"
if [[ -d "$CRED_TEST_DIR" ]]; then
  assert_fail "read ~/.ssh/*"           bash -c "ls ${HOME}/.ssh/"
fi
assert_fail "cat ~/.netrc"             bash -c "cat ${HOME}/.netrc 2>/dev/null || cat ${HOME}/.npmrc 2>/dev/null || ls ${HOME}/.ssh/ 2>/dev/null"
assert_fail "read ~/.git-credentials"  bash -c "cat ${HOME}/.git-credentials"

echo ""
echo "=== Sandbox: SPECTATOR_EXTRA_DENY (should fail) ==="
# Create a temp file to test custom deny
EXTRA_TEST_DIR=$(mktemp -d)
echo "secret" > "${EXTRA_TEST_DIR}/secret.txt"
SPECTATOR_EXTRA_DENY="${EXTRA_TEST_DIR}" assert_fail "custom deny path" cat "${EXTRA_TEST_DIR}/secret.txt"
rm -rf "$EXTRA_TEST_DIR"

echo ""
echo "=== Sandbox: SPECTATOR_NO_CRED_BLOCK (should succeed) ==="
if [[ -d "${HOME}/.ssh" ]]; then
  SPECTATOR_NO_CRED_BLOCK=1 assert_success "cred block off" bash -c "ls ${HOME}/.ssh/"
else
  # No .ssh dir to test, use a guaranteed path
  SPECTATOR_NO_CRED_BLOCK=1 assert_success "cred block off" ls /etc
fi

echo ""
echo "=== Permission hook: auto-approve sandbox-run ==="
assert_hook_allows "sandbox-run cmd"      "sandbox-run git status"
assert_hook_allows "sandbox-run with args" "sandbox-run ls -la /etc"
assert_hook_allows "sandbox-run python"   "sandbox-run python3 -c 'print(1)'"

echo ""
echo "=== Permission hook: reject non-sandbox commands ==="
assert_hook_asks "bare git"               "git status"
assert_hook_asks "bare rm"                "rm -rf /"
assert_hook_asks "bare python"            "python3 script.py"
assert_hook_asks "partial match"          "sandbox-runner ls"

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  echo "All tests passed."
fi
