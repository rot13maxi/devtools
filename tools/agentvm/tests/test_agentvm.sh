#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTVM_BIN="$(cd "$SCRIPT_DIR/.." && pwd)/bin/agentvm"

PASS_COUNT=0
FAIL_COUNT=0

log_pass() {
  printf 'ok - %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

log_fail() {
  printf 'not ok - %s\n' "$1" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

hash10() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print substr($1,1,10)}'
    return
  fi
  printf '%s' "$1" | sha256sum | awk '{print substr($1,1,10)}'
}

new_test_tmp() {
  mktemp -d "${TMPDIR:-/tmp}/agentvm-test.XXXXXX"
}

write_fake_limactl() {
  local target="$1"
  cat > "$target" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="${FAKE_LIMACTL_LOG:?}"
printf '%s\n' "$*" >>"$log_file"

cmd="${1:-}"
case "$cmd" in
  list)
    if [ "${2:-}" = "--format" ] && [ -n "${FAKE_LIST_OUTPUT:-}" ]; then
      printf '%b\n' "$FAKE_LIST_OUTPUT"
    fi
    ;;
  start|stop|create|clone|delete)
    ;;
  shell)
    shift
    if [ "${1:-}" = "--workdir" ]; then
      shift 2
    fi
    instance="${1:-}"
    shift || true

    if [ "${1:-}" = "command" ] && [ "${2:-}" = "-v" ]; then
      case "${3:-}" in
        codex|claude|opencode|gh) exit 0 ;;
        *) exit 1 ;;
      esac
    fi

    if [ "${1:-}" = "test" ] && [ "${2:-}" = "-f" ]; then
      [ "${FAKE_STAMP_EXISTS:-0}" = "1" ] && exit 0 || exit 1
    fi

    if [ "${1:-}" = "env" ]; then
      while [ "$#" -gt 0 ]; do
        if [ "${1:-}" = "bash" ] && [ "${2:-}" = "-lc" ]; then
          printf 'ENV_BASHLC:%s\n' "${3:-}" >>"$log_file"
          break
        fi
        shift
      done
      exit 0
    fi

    if [ "${1:-}" = "bash" ] && [ "${2:-}" = "-lc" ]; then
      command_str="${3:-}"
      printf 'BASHLC:%s\n' "$command_str" >>"$log_file"

      if [[ "$command_str" == *"/proc/mounts"* ]]; then
        path="$(printf '%s' "$command_str" | sed -n "s/.*grep -Fq -- ' \(.*\) ' \/proc\/mounts.*/\1/p")"
        case "$path" in
          "${FAKE_ROOT_PATH:-}")
            [ "${FAKE_ROOT_MOUNTED:-1}" = "1" ] && exit 0 || exit 1
            ;;
          "${FAKE_HOME_PATH:-}/.config/gh")
            [ "${FAKE_GH_MOUNTED:-0}" = "1" ] && exit 0 || exit 1
            ;;
          "${FAKE_HOME_PATH:-}/.ssh")
            [ "${FAKE_SSH_MOUNTED:-0}" = "1" ] && exit 0 || exit 1
            ;;
          *)
            exit 1
            ;;
        esac
      fi

      if [[ "$command_str" == *"cat '"*".agentvm/mount-policy'"* ]]; then
        printf '%s\n' "${FAKE_EXISTING_POLICY:-}"
        exit 0
      fi

      if [[ "$command_str" == *"cat '/var/lib/agentvm/manifest.sha256'"* ]]; then
        printf '%s\n' "${FAKE_MANIFEST_HASH:-}"
        exit 0
      fi

      exit 0
    fi
    ;;
  *)
    ;;
esac
EOF
  chmod +x "$target"
}

run_test_sha256sum_fallback() {
  local t
  t="$(new_test_tmp)"
  mkdir -p "$t/bin"

  write_fake_limactl "$t/bin/limactl"
  cat > "$t/bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$t/bin/sha256sum"

  ln -s /usr/bin/dirname "$t/bin/dirname"
  : > "$t/limactl.log"

  if PATH="$t/bin:/bin" FAKE_LIMACTL_LOG="$t/limactl.log" "$AGENTVM_BIN" --help >/dev/null 2>&1; then
    log_pass "works when only sha256sum is available"
  else
    log_fail "works when only sha256sum is available"
  fi

  rm -rf "$t"
}

run_test_recreate_on_mount_toggle_drift() {
  local t root instance
  t="$(new_test_tmp)"
  mkdir -p "$t/bin"
  write_fake_limactl "$t/bin/limactl"
  : > "$t/limactl.log"

  root="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  instance="agentvm-devtools-$(hash10 "$root")"

  if PATH="$t/bin:/usr/bin:/bin" \
    HOME="$HOME" \
    FAKE_LIMACTL_LOG="$t/limactl.log" \
    FAKE_LIST_OUTPUT="$instance"$'\n'"agentvm-base" \
    FAKE_ROOT_PATH="$root" \
    FAKE_HOME_PATH="$HOME" \
    FAKE_ROOT_MOUNTED=1 \
    FAKE_GH_MOUNTED=1 \
    FAKE_SSH_MOUNTED=0 \
    AGENTVM_SKIP_AUTO_INSTALL=1 \
    AGENTVM_MOUNT_GH_CONFIG=0 \
    AGENTVM_MOUNT_SSH=0 \
    "$AGENTVM_BIN" codex --help >/dev/null 2>&1; then
    if grep -Fq "delete $instance" "$t/limactl.log"; then
      log_pass "recreates VM when gh mount toggle drifts from existing instance"
    else
      log_fail "recreates VM when gh mount toggle drifts from existing instance"
    fi
  else
    log_fail "recreates VM when gh mount toggle drifts from existing instance"
  fi

  rm -rf "$t"
}

run_test_symlink_cleanup_script_present() {
  local t root instance
  t="$(new_test_tmp)"
  mkdir -p "$t/bin"
  write_fake_limactl "$t/bin/limactl"
  : > "$t/limactl.log"

  root="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  instance="agentvm-devtools-$(hash10 "$root")"

  if PATH="$t/bin:/usr/bin:/bin" \
    HOME="$HOME" \
    FAKE_LIMACTL_LOG="$t/limactl.log" \
    FAKE_LIST_OUTPUT="$instance" \
    FAKE_ROOT_PATH="$root" \
    FAKE_HOME_PATH="$HOME" \
    FAKE_ROOT_MOUNTED=1 \
    FAKE_GH_MOUNTED=0 \
    FAKE_SSH_MOUNTED=0 \
    AGENTVM_SKIP_AUTO_INSTALL=1 \
    AGENTVM_MOUNT_GH_CONFIG=0 \
    AGENTVM_MOUNT_SSH=0 \
    "$AGENTVM_BIN" codex --help >/dev/null 2>&1; then
    if grep -Fq 'rm -f "$HOME/.config/gh"' "$t/limactl.log" && grep -Fq 'rm -f "$HOME/.ssh"' "$t/limactl.log"; then
      log_pass "guest bootstrap script removes stale gh/ssh symlinks when mounts are disabled"
    else
      log_fail "guest bootstrap script removes stale gh/ssh symlinks when mounts are disabled"
    fi
  else
    log_fail "guest bootstrap script removes stale gh/ssh symlinks when mounts are disabled"
  fi

  rm -rf "$t"
}

run_test_mount_policy_uses_guest_home_path() {
  local t root instance
  t="$(new_test_tmp)"
  mkdir -p "$t/bin"
  write_fake_limactl "$t/bin/limactl"
  : > "$t/limactl.log"

  root="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  instance="agentvm-devtools-$(hash10 "$root")"

  if PATH="$t/bin:/usr/bin:/bin" \
    HOME="$HOME" \
    FAKE_LIMACTL_LOG="$t/limactl.log" \
    FAKE_LIST_OUTPUT="$instance" \
    FAKE_ROOT_PATH="$root" \
    FAKE_HOME_PATH="$HOME" \
    FAKE_ROOT_MOUNTED=1 \
    FAKE_GH_MOUNTED=0 \
    FAKE_SSH_MOUNTED=0 \
    AGENTVM_SKIP_AUTO_INSTALL=1 \
    AGENTVM_MOUNT_GH_CONFIG=0 \
    AGENTVM_MOUNT_SSH=0 \
    "$AGENTVM_BIN" codex --help >/dev/null 2>&1; then
    if grep -Fq '${HOME}/.agentvm/mount-policy' "$t/limactl.log"; then
      log_pass "stores mount policy at guest-home-relative path"
    else
      log_fail "stores mount policy at guest-home-relative path"
    fi
  else
    log_fail "stores mount policy at guest-home-relative path"
  fi

  rm -rf "$t"
}

run_test_stale_git_files_are_cleaned_up() {
  local t root instance
  t="$(new_test_tmp)"
  mkdir -p "$t/bin"
  write_fake_limactl "$t/bin/limactl"
  : > "$t/limactl.log"

  root="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  instance="agentvm-devtools-$(hash10 "$root")"

  if PATH="$t/bin:/usr/bin:/bin" \
    HOME="$HOME" \
    FAKE_LIMACTL_LOG="$t/limactl.log" \
    FAKE_LIST_OUTPUT="$instance" \
    FAKE_ROOT_PATH="$root" \
    FAKE_HOME_PATH="$HOME" \
    FAKE_ROOT_MOUNTED=1 \
    FAKE_GH_MOUNTED=1 \
    FAKE_SSH_MOUNTED=0 \
    AGENTVM_SKIP_AUTO_INSTALL=1 \
    AGENTVM_MOUNT_GITCONFIG=0 \
    AGENTVM_MOUNT_GIT_CREDENTIALS=0 \
    "$AGENTVM_BIN" codex --help >/dev/null 2>&1; then
    if grep -Fq 'rm -f "$HOME/.gitconfig"' "$t/limactl.log" && grep -Fq 'rm -f "$HOME/.git-credentials"' "$t/limactl.log"; then
      log_pass "removes stale gitconfig and git-credentials when host files are absent"
    else
      log_fail "removes stale gitconfig and git-credentials when host files are absent"
    fi
  else
    log_fail "removes stale gitconfig and git-credentials when host files are absent"
  fi

  rm -rf "$t"
}

run_test_yolo_flag_is_opt_in() {
  local t root instance
  t="$(new_test_tmp)"
  mkdir -p "$t/bin"
  write_fake_limactl "$t/bin/limactl"
  : > "$t/limactl.log"

  root="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  instance="agentvm-devtools-$(hash10 "$root")"

  if PATH="$t/bin:/usr/bin:/bin" \
    HOME="$HOME" \
    FAKE_LIMACTL_LOG="$t/limactl.log" \
    FAKE_LIST_OUTPUT="$instance" \
    FAKE_ROOT_PATH="$root" \
    FAKE_HOME_PATH="$HOME" \
    FAKE_ROOT_MOUNTED=1 \
    FAKE_GH_MOUNTED=1 \
    FAKE_SSH_MOUNTED=0 \
    AGENTVM_SKIP_AUTO_INSTALL=1 \
    "$AGENTVM_BIN" codex --help >/dev/null 2>&1; then
    if ! grep -Fq -- '--dangerously-bypass-approvals-and-sandbox' "$t/limactl.log"; then
      log_pass "does not add dangerous yolo flag by default"
    else
      log_fail "does not add dangerous yolo flag by default"
    fi
  else
    log_fail "does not add dangerous yolo flag by default"
  fi

  : > "$t/limactl.log"
  if PATH="$t/bin:/usr/bin:/bin" \
    HOME="$HOME" \
    FAKE_LIMACTL_LOG="$t/limactl.log" \
    FAKE_LIST_OUTPUT="$instance" \
    FAKE_ROOT_PATH="$root" \
    FAKE_HOME_PATH="$HOME" \
    FAKE_ROOT_MOUNTED=1 \
    FAKE_GH_MOUNTED=1 \
    FAKE_SSH_MOUNTED=0 \
    AGENTVM_SKIP_AUTO_INSTALL=1 \
    AGENTVM_YOLO=1 \
    "$AGENTVM_BIN" codex --help >/dev/null 2>&1; then
    if grep -Fq -- '--dangerously-bypass-approvals-and-sandbox' "$t/limactl.log"; then
      log_pass "adds dangerous yolo flag only when AGENTVM_YOLO=1"
    else
      log_fail "adds dangerous yolo flag only when AGENTVM_YOLO=1"
    fi
  else
    log_fail "adds dangerous yolo flag only when AGENTVM_YOLO=1"
  fi

  rm -rf "$t"
}

main() {
  run_test_sha256sum_fallback
  run_test_recreate_on_mount_toggle_drift
  run_test_symlink_cleanup_script_present
  run_test_mount_policy_uses_guest_home_path
  run_test_stale_git_files_are_cleaned_up
  run_test_yolo_flag_is_opt_in

  if [ "$FAIL_COUNT" -ne 0 ]; then
    printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT" >&2
    exit 1
  fi

  printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
}

main "$@"
