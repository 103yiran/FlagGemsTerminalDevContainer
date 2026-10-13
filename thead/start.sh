#!/usr/bin/env bash
# thead/start.sh — launch the FlagGems T-Head development container.
#
# Base image:  pkg.flytiger-eco.com/docker_release/pytorch:v2.1.1-2.10.0-ubuntu24.04-cuda13.0-py312
#              (dev image flaggems-thead:dev)
#
# Options, host requirements (an SSH key on the host with its public key
# registered on GitCode) and examples:  ./thead/start.sh --help
# Full documentation:  common/lib.sh, README.md
#

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
