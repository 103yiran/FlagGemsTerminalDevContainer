#!/usr/bin/env bash
# ascend/start.sh — launch the FlagGems Ascend development container.
#
# Step 1: build (or skip) flaggems-ascend:dev from root Dockerfile
#         using harbor.baai.ac.cn/flagos-runtime/flagos-runtime-ascend-cann9.0.0 as base
# Step 2: start container with -itd (detached), then exec into it
#
# SSH key forwarding (applied at container creation, pick one):
#   ~/.ssh dir mount  — default; keys available as files (read-only)
#   SSH agent forward — private key never leaves the host; requires
#                       ssh-agent running with keys loaded on the host
#
# Usage:
#   ./ascend/start.sh                         # default container name, mounts FlagGems
#   ./ascend/start.sh -n my_container         # custom container name
#   ./ascend/start.sh -f                      # force-recreate container
#   ./ascend/start.sh --rebuild-dev           # force-rebuild dev image
#   ./ascend/start.sh --rebuild               # force-rebuild dev image
#   ./ascend/start.sh --ssh-agent             # use SSH agent forwarding instead
#   ./ascend/start.sh -c "python a.py"        # exec command (default: zsh)
#   ./ascend/start.sh --repo ../FlagTree      # mount FlagTree instead of FlagGems
#   ./ascend/start.sh --repo ../A --repo ../B # mount multiple repos
#   ./ascend/start.sh --base-tag 2.1.2        # use FlagOS base image version 2.1.2
#
# See common/lib.sh for full option documentation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="ascend"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-cann9.0.0}"

# ── Platform hardware flags ───────────────────────────────────────
platform_hardware_args() {
    cat << 'EOF'
--device=/dev/davinci0
--device=/dev/davinci_manager
--device=/dev/devmm_svm
--device=/dev/hisi_hdc
EOF
}

# ── Platform extra mounts ─────────────────────────────────────────
# Ascend requires driver, dcmi and npu-smi from the host.
ASCEND_EXTRA_MOUNTS=(
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver
    -v /usr/local/dcmi:/usr/local/dcmi
    -v /usr/local/sbin/npu-smi:/usr/local/sbin/npu-smi
)

# Override _run_container to inject the extra mounts before calling the base.
# We patch REPO_MOUNT_ARGS after parsing so lib_main picks it up transparently.
_ascend_patch_mounts() {
    REPO_MOUNT_ARGS=("${ASCEND_EXTRA_MOUNTS[@]}" "${REPO_MOUNT_ARGS[@]}")
}

# ── Load shared logic ─────────────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"

# Wrap lib_main to inject the extra mounts after arg parsing.
# _parse_args populates REPO_MOUNT_ARGS; we extend it before _run_container.
_orig_run_container() { _run_container "$@"; }
_run_container() {
    _ascend_patch_mounts
    _orig_run_container "$@"
}

lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
