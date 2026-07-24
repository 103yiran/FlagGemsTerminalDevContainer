#!/usr/bin/env bash
# nvidia/start.sh — launch the FlagGems NVIDIA development container.
#
# Step 1: build (or skip) flaggems-nvidia:runtime from
#         build-infra legacy/flaggems-nvidia-13.3  (--target runtime)
# Step 2: build (or skip) flaggems-nvidia:dev from root Dockerfile
# Step 3: start container with -itd (detached), then exec into it
#
# SSH key forwarding (applied at container creation, pick one):
#   ~/.ssh dir mount  — default; keys available as files (read-only)
#   SSH agent forward — private key never leaves the host; requires
#                       ssh-agent running with keys loaded on the host
#
# Usage:
#   ./nvidia/start.sh                         # default container name, mounts FlagGems
#   ./nvidia/start.sh -n my_container         # custom container name
#   ./nvidia/start.sh -f                      # force-recreate container
#   ./nvidia/start.sh --rebuild-runtime       # force-rebuild runtime image
#   ./nvidia/start.sh --rebuild-dev           # force-rebuild dev image
#   ./nvidia/start.sh --rebuild               # force-rebuild both images
#   ./nvidia/start.sh --ssh-agent             # use SSH agent forwarding instead
#   ./nvidia/start.sh -c "python a.py"        # exec command (default: zsh)
#   ./nvidia/start.sh --repo ../FlagTree      # mount FlagTree instead of FlagGems
#   ./nvidia/start.sh --repo ../A --repo ../B # mount multiple repos
#
# See common/lib.sh for full option documentation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="nvidia"
RUNTIME_DOCKERFILE="legacy/flaggems-nvidia-13.3"

# ── Platform hardware flags ───────────────────────────────────────
platform_hardware_args() {
    cat << 'EOF'
--gpus all
--ulimit nofile=1048576:1048576
EOF
}

# ── Load shared logic and run ─────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"
lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
