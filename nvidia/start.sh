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

# ── Load shared logic ─────────────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"

# Wrap _run_container to install Nsight Compute (ncu) once the container is up.
# Done here rather than at image build time: the build container (run→exec→
# commit, see _build_dev) has no network on hosts without a configured docker
# daemon proxy, while the dev container runs with --net=host and always does.
# See nvidia/install-nsight-compute.sh for the apt-vs-.run install logic and
# how to pin/upgrade the version (NSIGHT_COMPUTE_VERSION).
eval "_orig_run_container() $(declare -f _run_container | tail -n +2)"
_run_container() {
    _orig_run_container "$@"
    if container_running; then
        "${SCRIPT_DIR}/install-nsight-compute.sh" "${CONTAINER_NAME}" "${NSIGHT_COMPUTE_VERSION:-}" || true
    fi
}

lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
