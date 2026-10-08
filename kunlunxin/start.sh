#!/usr/bin/env bash
# kunlunxin/start.sh — launch the FlagGems Kunlunxin development container.
#
# Step 1: build (or skip) flaggems-kunlunxin:dev from root Dockerfile
#         using harbor.baai.ac.cn/flagos-runtime/flagos-runtime-kunlunxin-xre5.37.1 as base
# Step 2: start container with -itd (detached), then exec into it
#
# Usage:
#   ./kunlunxin/start.sh                         # default container name, mounts FlagGems
#   ./kunlunxin/start.sh -n my_container         # custom container name
#   ./kunlunxin/start.sh -f                      # force-recreate container
#   ./kunlunxin/start.sh --rebuild-dev           # force-rebuild dev image
#   ./kunlunxin/start.sh --rebuild               # force-rebuild dev image
#   ./kunlunxin/start.sh --ssh-agent             # use SSH agent forwarding instead
#   ./kunlunxin/start.sh -c "python a.py"        # exec command (default: zsh)
#   ./kunlunxin/start.sh --repo ../FlagTree      # mount FlagTree instead of FlagGems
#   ./kunlunxin/start.sh --repo ../A --repo ../B # mount multiple repos
#   ./kunlunxin/start.sh --base-tag 2.2.0        # use FlagOS base image version 2.2.0
#
# See common/lib.sh for full option documentation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="kunlunxin"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-xre5.37.1}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-2.2.0}"

# ── Platform hardware flags ───────────────────────────────────────
# Expose all 8 Kunlunxin XPU devices (/dev/xpu0 .. /dev/xpu7) plus the
# xpuctrl control device, which the driver needs to manage the devices.
platform_hardware_args() {
    for i in $(seq 0 7); do
        echo "--device=/dev/xpu${i}"
    done
    echo "--device=/dev/xpuctrl"
}

# ── Load shared logic ─────────────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"

lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
