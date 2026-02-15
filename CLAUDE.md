# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A collection of developer tools. The primary tool is **agentvm** — a Lima-based VM wrapper that provides isolated Linux environments for running AI coding agents (Claude, Codex, OpenCode) on macOS/Linux hosts.

## Commands

```bash
# Run unit tests (uses fake limactl mock)
just agentvm-test

# Run integration smoke tests (requires real Lima installation)
AGENTVM_RUN_INTEGRATION_SMOKE=1 just agentvm-integration-smoke
```

There is no build step — the codebase is entirely bash scripts.

## Architecture

### agentvm (`tools/agentvm/`)

The core is a single bash script (`bin/agentvm`, ~800 lines) that manages Lima VMs in a two-tier model:

1. **Base VM layer**: A single long-lived `agentvm-base` instance provisioned via a manifest system (`manifests/base/apt-packages.txt` + `manifests/base/scripts/*.sh`). A snapshot of this VM is cached and reused. Manifest changes are detected via sha256 hash comparison to avoid unnecessary re-provisioning.

2. **Project VM layer**: Per-project instances cloned from the base snapshot. Named `agentvm-{project-slug}-{hash10}` where the hash is derived from the project directory path. Created on-demand when an agent is first invoked.

**Mount/sync strategy**: Project VMs mount the project directory (read-write), agent config directories (`~/.claude`, `~/.codex`, etc.), and optionally GitHub config, git credentials, and SSH keys. Mount policy state is tracked inside the guest at `${HOME}/.agentvm/mount-policy` — if toggles drift from the recorded policy, the VM is automatically recreated.

**Shims** (`shims/claude`, `shims/codex`, `shims/opencode`): Lightweight wrappers that delegate to `agentvm run <agent>`. Can be symlinked into PATH for transparent VM execution.

**Concurrency**: Directory-based locks with configurable timeout prevent parallel operations from corrupting VM state. Transient limactl failures are retried automatically.

### Testing

Tests use a TAP-like bash format with `ok`/`not ok` output. Unit tests mock `limactl` via a fake implementation injected into PATH. Integration tests require a real Lima installation and are gated behind `AGENTVM_RUN_INTEGRATION_SMOKE=1`.

## Key Environment Variables

All optional. Most important for development:

- `AGENTVM_YOLO=1` — enable dangerous agent bypass flags (e.g., `--dangerously-skip-permissions`)
- `AGENTVM_MOUNT_SSH=0` (default) — toggle SSH key mounting
- `AGENTVM_MOUNT_GH_CONFIG=1` (default) — toggle GitHub CLI config mounting
- `AGENTVM_SKIP_AUTO_INSTALL=1` — skip auto-installing missing agent CLIs via npm
