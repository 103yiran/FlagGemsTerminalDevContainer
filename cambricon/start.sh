#!/usr/bin/env bash
# cambricon/start.sh — launch the FlagGems Cambricon development container.
#
# Step 1: build (or skip) flaggems-cambricon:dev from root Dockerfile
#         using harbor.baai.ac.cn/flagos-base/flagos-base-cambricon-neuware4.7.2 as base
# Step 2: start container with -itd (detached), then exec into it
#
# SSH key forwarding (applied at container creation, pick one):
#   ~/.ssh dir mount  — default; keys available as files (read-only)
#   SSH agent forward — private key never leaves the host; requires
#                       ssh-agent running with keys loaded on the host
#
# Usage:
#   ./cambricon/start.sh                         # default container name, mounts FlagGems
#   ./cambricon/start.sh -n my_container         # custom container name
#   ./cambricon/start.sh -f                      # force-recreate container
#   ./cambricon/start.sh --rebuild-dev           # force-rebuild dev image
#   ./cambricon/start.sh --rebuild               # force-rebuild dev image
#   ./cambricon/start.sh --ssh-agent             # use SSH agent forwarding instead
#   ./cambricon/start.sh -c "python a.py"        # exec command (default: zsh)
#   ./cambricon/start.sh --repo ../FlagTree      # mount FlagTree instead of FlagGems
#   ./cambricon/start.sh --repo ../A --repo ../B # mount multiple repos
#   ./cambricon/start.sh --base-tag 2.2.0        # use FlagOS base image version 2.2.0
#
# See common/lib.sh for full option documentation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="cambricon"
# Optional: override default toolkit version (neuware4.7.2)
# TOOLKIT_VERSION="neuware5.0.0"

# ── Platform hardware flags ───────────────────────────────────────
platform_hardware_args() {
    cat << 'EOF'
--device=/dev/cambricon_dev0
--device=/dev/cambricon_dev1
--device=/dev/cambricon_dev2
--device=/dev/cambricon_dev3
--device=/dev/cambricon_dev4
--device=/dev/cambricon_dev5
--device=/dev/cambricon_dev6
--device=/dev/cambricon_dev7
--device=/dev/cambricon_ctl
EOF
}

# ── Load shared logic and run ─────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"
lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
