#!/usr/bin/env bash
# kunlunxin/start.sh — launch the FlagGems Kunlunxin development container.
#
# Base image:  harbor.baai.ac.cn/flagos-runtime/flagos-runtime-kunlunxin-xre5.37.1:2.2.0
#              (toolkit xre5.37.1; dev image flaggems-kunlunxin:dev)
#
# Options and examples:  ./kunlunxin/start.sh --help
# Host requirements: export http_proxy/https_proxy if GitHub/GitCode are
# not directly reachable (common/lib.sh forwards them into the container);
# an SSH key registered on GitCode is an optional extra fallback.
# Full documentation:  common/lib.sh, README.md
#

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
