#!/usr/bin/env bash
set -euo pipefail

PATCH_BOOTSTRAP_URL="https://raw.githubusercontent.com/David8lang/hermes-agent-zh/main/patches/main.sh"

curl -fsSL "$PATCH_BOOTSTRAP_URL" | bash -s -- "$@"
