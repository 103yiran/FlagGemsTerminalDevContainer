#!/usr/bin/env bash
# nvidia/start.sh — launch the FlagGems NVIDIA development container.
#
# Base image:  harbor.baai.ac.cn/flagos-app/vllm0.24.0-generic-13.3:2.2.0-0.3.0
#              (toolkit cuda13.3; dev image flaggems-nvidia:dev)
#
# Options, host requirements (an SSH key on the host with its public key
# registered on GitCode) and examples:  ./nvidia/start.sh --help
# Full documentation:  common/lib.sh, README.md
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="nvidia"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-cuda13.3}"

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
