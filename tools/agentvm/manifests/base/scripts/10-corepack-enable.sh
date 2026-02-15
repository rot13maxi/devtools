#!/usr/bin/env bash
set -euo pipefail

# Enable corepack when available so package managers like pnpm/yarn work out of the box.
if command -v corepack >/dev/null 2>&1; then
  corepack enable || true
fi
