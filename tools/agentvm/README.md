# agentvm

`agentvm` wraps Lima to run coding agents (`claude`, `codex`, `opencode`) inside persistent per-project VMs with host file visibility.

## What it does

- Lazy-creates a per-project VM on first run, then reuses it.
- Builds project VMs by cloning a provisioned base VM.
- Mounts your project directory for normal VS Code editing on the host.
- Mounts your agent config dirs and links them into guest home:
  - `~/.claude`
  - `~/.codex`
  - `~/.config/opencode`
- Mounts GitHub auth/config for git + `gh` workflows:
  - `~/.config/gh` (default on)
  - `~/.gitconfig` (synced into VM on each run, default on if present)
  - `~/.git-credentials` (synced into VM on each run, default on if present)
  - `~/.ssh` (optional, opt-in)
- Runs the chosen agent inside the VM (optional yolo flags via `AGENTVM_YOLO=1`).
- Leaves Lima port forwarding defaults intact so localhost dev servers are reachable from host.

## Prerequisites

- macOS or Linux with Lima installed (`limactl` on your `PATH`).
- Internet access inside VM for first-time package installs.

### Install Lima

Official docs: https://lima-vm.io/docs/installation/

macOS (Homebrew):

```bash
brew install lima
```

Linux (Homebrew on Linux):

```bash
brew install lima
```

Linux/macOS (manual binary install from latest release):

```bash
VERSION=$(curl -fsSL https://api.github.com/repos/lima-vm/lima/releases/latest | jq -r .tag_name)
curl -fsSL "https://github.com/lima-vm/lima/releases/download/${VERSION}/lima-${VERSION:1}-$(uname -s)-$(uname -m).tar.gz" | sudo tar Cxzvm /usr/local
curl -fsSL "https://github.com/lima-vm/lima/releases/download/${VERSION}/lima-additional-guestagents-${VERSION:1}-$(uname -s)-$(uname -m).tar.gz" | sudo tar Cxzvm /usr/local
```

Verify:

```bash
limactl --version
```

## Install

Use directly:

```bash
tools/agentvm/bin/agentvm codex
```

Or prepend shims in your shell startup so `claude`/`codex`/`opencode` run in VM automatically:

```bash
export PATH="/Users/alex/code/devtools/tools/agentvm/shims:$PATH"
```

## Quickstart

1. Initialize the base VM image:

```bash
agentvm base init
```

2. Authenticate GitHub once on host (shared into VM):

```bash
gh auth login
```

3. In any project directory, run your agent:

```bash
agentvm codex
```

4. Verify GitHub access from inside the project VM:

```bash
agentvm gh auth status
```

5. Optional: edit the base image and save it:

```bash
vim tools/agentvm/manifests/base/apt-packages.txt
agentvm base apply
agentvm base snapshot
```

## Command Reference

Core commands:

- `agentvm claude [args...]`
- `agentvm codex [args...]`
- `agentvm opencode [args...]`
- `agentvm run <claude|codex|opencode> [args...]`
- `agentvm gh [args...]`
- `agentvm status`
- `agentvm list`
- `agentvm rm [instance]`
- `agentvm prune`
- `agentvm doctor`
- `agentvm install-shims [dir]`

Base image commands:

- `agentvm base init`
- `agentvm base apply`
- `agentvm base shell`
- `agentvm base snapshot`
- `agentvm base reset`

## Usage Examples

Run an agent in the current directory VM:

```bash
agentvm claude
agentvm codex
agentvm opencode
agentvm gh auth status
```

or with shimmed commands:

```bash
codex
claude
opencode
```

Extra args are passed through:

```bash
agentvm codex --help
```

Show VM mapping for current project:

```bash
agentvm status
```

List all agentvm VMs:

```bash
agentvm list
```

Delete current project VM:

```bash
agentvm rm
```

Prune stopped project VMs:

```bash
agentvm prune
```

Run health checks:

```bash
agentvm doctor
```

## Behavior notes

- First run is slower (base provisioning + project VM clone + optional agent install).
- Base image provisioning is manifest-driven; edit files under `tools/agentvm/manifests/base`.
- If an agent CLI is missing in the VM, `agentvm` auto-installs with npm by default.
- Dangerous bypass flags are opt-in only (`AGENTVM_YOLO=1`).
- If mount policy toggles change (`AGENTVM_MOUNT_GH_CONFIG`, `AGENTVM_MOUNT_SSH`), existing project VMs are recreated automatically to apply the new mount set.
- `~/.gitconfig` and `~/.git-credentials` are synced when enabled and cleaned up from guest when disabled/missing.
- To disable auto install, set `AGENTVM_SKIP_AUTO_INSTALL=1`.
- To override install command for a given CLI:
  - `AGENTVM_CLAUDE_INSTALL_CMD`
  - `AGENTVM_CODEX_INSTALL_CMD`
  - `AGENTVM_OPENCODE_INSTALL_CMD`
- To override `gh` install command:
  - `AGENTVM_GH_INSTALL_CMD`

## Base Manifest

Default manifest path:

- `tools/agentvm/manifests/base/apt-packages.txt`
- `tools/agentvm/manifests/base/scripts/*.sh` (run in lexical order as root)

Workflow:

1. Edit package/script manifest files.
2. Run `agentvm base apply`.
3. Run `agentvm base snapshot` to persist the updated baseline.

Use a custom manifest location with:

- `AGENTVM_BASE_MANIFEST_DIR=/path/to/manifest`

## GitHub access

Recommended (token-based via `gh`):

1. Authenticate once on host:

```bash
gh auth login
```

2. Verify inside project VM:

```bash
agentvm gh auth status
```

Because `~/.config/gh` is mounted into the VM by default, `gh` auth state is shared.

Optional SSH key passthrough:

```bash
export AGENTVM_MOUNT_SSH=1
```

This mounts `~/.ssh` into the VM. Use only if you want SSH-key git auth inside the guest and are comfortable exposing host keys to the VM.

Mount/sync toggles:

- `AGENTVM_MOUNT_GH_CONFIG` (default `1`)
- `AGENTVM_MOUNT_GITCONFIG` (default `1`)
- `AGENTVM_MOUNT_GIT_CREDENTIALS` (default `1`)
- `AGENTVM_MOUNT_SSH` (default `0`)
- `AGENTVM_YOLO` (default `0`)

## Network / dev servers

With Lima default port forwarding, services bound in VM are typically reachable from host on `127.0.0.1:<port>`. If a tool binds to VM-only interfaces, bind explicitly to `0.0.0.0` or `127.0.0.1` inside the guest.

## Testing

Unit-style tests (fake `limactl`):

```bash
just agentvm-test
```

Real Lima integration smoke test (opt-in):

```bash
AGENTVM_RUN_INTEGRATION_SMOKE=1 just agentvm-integration-smoke
```

The integration smoke test uses isolated `agentvm` instance names and cleans them up automatically.
