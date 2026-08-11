#!/usr/bin/env bash
# metax/start.sh — launch the FlagGems Metax development container.
#
# Step 1: build (or skip) flaggems-metax:dev from root Dockerfile
#         using harbor.baai.ac.cn/flagos-runtime/flagos-runtime-metax-maca3.8.1.3 as base
# Step 2: start container with -itd (detached), then exec into it
#
# SSH key forwarding (applied at container creation, pick one):
#   ~/.ssh dir mount  — default; keys available as files (read-only)
#   SSH agent forward — private key never leaves the host; requires
#                       ssh-agent running with keys loaded on the host
#
# Usage:
#   ./metax/start.sh                         # default container name, mounts FlagGems
#   ./metax/start.sh -n my_container         # custom container name
#   ./metax/start.sh -f                      # force-recreate container
#   ./metax/start.sh --rebuild-dev           # force-rebuild dev image
#   ./metax/start.sh --rebuild               # force-rebuild dev image
#   ./metax/start.sh --ssh-agent             # use SSH agent forwarding instead
#   ./metax/start.sh -c "python a.py"        # exec command (default: zsh)
#   ./metax/start.sh --repo ../FlagTree      # mount FlagTree instead of FlagGems
#   ./metax/start.sh --repo ../A --repo ../B # mount multiple repos
#   ./metax/start.sh --base-tag 2.1.2        # use FlagOS base image version 2.1.2
#
# See common/lib.sh for full option documentation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="metax"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-maca3.8.1.3}"

# ── Platform hardware flags ───────────────────────────────────────
platform_hardware_args() {
    cat << 'EOF'
--device=/dev/mxcd
--device=/dev/dri
--group-add=video
EOF
}

# ── Load shared logic and run ─────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"
lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
