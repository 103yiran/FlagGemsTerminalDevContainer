#!/usr/bin/env bash
# thead/start.sh — launch the FlagGems T-Head development container.
#
# Step 1: build (or skip) flaggems-thead:dev from root Dockerfile
#         using pkg.flytiger-eco.com/docker_release/pytorch as base
# Step 2: start container with -itd (detached), then exec into it
#
# Usage:
#   ./thead/start.sh                         # default container name, mounts FlagGems
#   ./thead/start.sh -n my_container         # custom container name
#   ./thead/start.sh -f                      # force-recreate container
#   ./thead/start.sh --rebuild-dev           # force-rebuild dev image
#   ./thead/start.sh --rebuild               # force-rebuild dev image
#   ./thead/start.sh --ssh-agent             # use SSH agent forwarding instead
#   ./thead/start.sh -c "python a.py"        # exec command (default: zsh)
#   ./thead/start.sh --repo ../FlagTree      # mount FlagTree instead of FlagGems
#   ./thead/start.sh --repo ../A --repo ../B # mount multiple repos
#   ./thead/start.sh --base-tag v2.1.1-2.10.0-ubuntu24.04-cuda13.0-py312
#                                             # use a different base image tag
#
# See common/lib.sh for full option documentation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="thead"

# T-Head ships a plain PyTorch image (not a FlagOS runtime image), so —
# like nvidia — we override the base image name/registry directly instead
# of relying on lib.sh's flagos-runtime-${PLATFORM}-${TOOLKIT} naming.
BASE_IMAGE_REGISTRY="${BASE_IMAGE_REGISTRY:-pkg.flytiger-eco.com/docker_release}"
BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-${BASE_IMAGE_REGISTRY}/pytorch}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-v2.1.1-2.10.0-ubuntu24.04-cuda13.0-py312}"

# ── Platform hardware flags ───────────────────────────────────────
# Expose the alixpu control device plus 8 PPU devices
# (/dev/alixpu_ppu0 .. /dev/alixpu_ppu7). --privileged, --init, and
# --shm-size=8g mirror the reference `docker run` invocation for this image;
# --net=host, --ipc=host, and the memlock/stack ulimits are already applied
# by common/lib.sh's _run_container.
platform_hardware_args() {
    cat << 'EOF'
--privileged
--init
--shm-size=8g
--device=/dev/alixpu
--device=/dev/alixpu_ctl
EOF
    for i in $(seq 0 7); do
        echo "--device=/dev/alixpu_ppu${i}"
    done
}

# ── Load shared logic and run ─────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"
lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
