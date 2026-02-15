#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AGENTVM_BIN="$REPO_ROOT/tools/agentvm/bin/agentvm"
MANIFEST_DIR="$SCRIPT_DIR/fixtures/minimal-manifest"

if ! command -v limactl >/dev/null 2>&1; then
  echo "skip - limactl not found"
  exit 0
fi

if [ "${AGENTVM_RUN_INTEGRATION_SMOKE:-0}" != "1" ]; then
  echo "skip - set AGENTVM_RUN_INTEGRATION_SMOKE=1 to run real Lima smoke tests"
  exit 0
fi

run_id="smoke-$(date +%s)-$$"
base_instance="agentvm-base-$run_id"
base_snapshot="base"
project_dir="$(mktemp -d "${TMPDIR:-/tmp}/agentvm-smoke-project.XXXXXX")"
shim_dir="$(mktemp -d "${TMPDIR:-/tmp}/agentvm-smoke-shims.XXXXXX")"

cleanup() {
  limactl stop "$base_instance" >/dev/null 2>&1 || true
  limactl delete "$base_instance" >/dev/null 2>&1 || limactl delete -f "$base_instance" >/dev/null 2>&1 || true

  if [ -n "${project_instance:-}" ]; then
    limactl stop "$project_instance" >/dev/null 2>&1 || true
    limactl delete "$project_instance" >/dev/null 2>&1 || limactl delete -f "$project_instance" >/dev/null 2>&1 || true
  fi

  rm -rf "$project_dir" "$shim_dir"
}
trap cleanup EXIT

project_instance="$(AGENTVM_BASE_INSTANCE="$base_instance" "$AGENTVM_BIN" status 2>/dev/null | awk -F= '/^instance=/{print $2}')"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    echo "ok - $msg"
  else
    echo "not ok - $msg" >&2
    echo "  expected to find: $needle" >&2
    exit 1
  fi
}

assert_file_linked() {
  local path="$1"
  local msg="$2"
  if [ -L "$path" ]; then
    echo "ok - $msg"
  else
    echo "not ok - $msg" >&2
    exit 1
  fi
}

echo "# agentvm integration smoke"

env \
  AGENTVM_BASE_INSTANCE="$base_instance" \
  AGENTVM_BASE_SNAPSHOT="$base_snapshot" \
  AGENTVM_BASE_MANIFEST_DIR="$MANIFEST_DIR" \
  "$AGENTVM_BIN" base init >/tmp/agentvm-smoke-base-init.log 2>&1

echo "ok - base init with isolated base instance"

pushd "$project_dir" >/dev/null

set +e
run_output="$(env \
  AGENTVM_BASE_INSTANCE="$base_instance" \
  AGENTVM_BASE_SNAPSHOT="$base_snapshot" \
  AGENTVM_BASE_MANIFEST_DIR="$MANIFEST_DIR" \
  AGENTVM_SKIP_AUTO_INSTALL=1 \
  "$AGENTVM_BIN" codex --help 2>&1)"
run_code=$?
set -e

if [ "$run_code" -eq 0 ]; then
  echo "ok - codex present in VM"
else
  assert_contains "$run_output" "'codex' not found in VM" "codex failure is explicit when AGENTVM_SKIP_AUTO_INSTALL=1"
fi

status_output="$(env \
  AGENTVM_BASE_INSTANCE="$base_instance" \
  AGENTVM_BASE_SNAPSHOT="$base_snapshot" \
  AGENTVM_BASE_MANIFEST_DIR="$MANIFEST_DIR" \
  "$AGENTVM_BIN" status 2>&1)"

assert_contains "$status_output" "instance=agentvm-" "status reports project instance"
assert_contains "$status_output" "mount_policy=version=v1;" "status includes mount policy"

doctor_output="$(env \
  AGENTVM_BASE_INSTANCE="$base_instance" \
  AGENTVM_BASE_SNAPSHOT="$base_snapshot" \
  AGENTVM_BASE_MANIFEST_DIR="$MANIFEST_DIR" \
  "$AGENTVM_BIN" doctor 2>&1)"
assert_contains "$doctor_output" "project_exists=yes" "doctor sees created project VM"

env \
  AGENTVM_BASE_INSTANCE="$base_instance" \
  AGENTVM_BASE_SNAPSHOT="$base_snapshot" \
  AGENTVM_BASE_MANIFEST_DIR="$MANIFEST_DIR" \
  "$AGENTVM_BIN" install-shims "$shim_dir" >/tmp/agentvm-smoke-install-shims.log 2>&1

assert_file_linked "$shim_dir/codex" "install-shims links codex"
assert_file_linked "$shim_dir/claude" "install-shims links claude"
assert_file_linked "$shim_dir/opencode" "install-shims links opencode"

env \
  AGENTVM_BASE_INSTANCE="$base_instance" \
  AGENTVM_BASE_SNAPSHOT="$base_snapshot" \
  AGENTVM_BASE_MANIFEST_DIR="$MANIFEST_DIR" \
  "$AGENTVM_BIN" rm >/tmp/agentvm-smoke-rm.log 2>&1

after_rm_status="$(env \
  AGENTVM_BASE_INSTANCE="$base_instance" \
  AGENTVM_BASE_SNAPSHOT="$base_snapshot" \
  AGENTVM_BASE_MANIFEST_DIR="$MANIFEST_DIR" \
  "$AGENTVM_BIN" status 2>&1)"
assert_contains "$after_rm_status" "instance_status=missing" "rm deletes current project VM"

popd >/dev/null

echo "integration smoke passed"
