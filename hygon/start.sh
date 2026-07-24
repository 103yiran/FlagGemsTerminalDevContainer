#!/usr/bin/env bash
# hygon/start.sh — launch the FlagGems Hygon development container.
#
# Step 1: build (or skip) flaggems-hygon:runtime from
#         build-infra legacy/flaggems-hygon-26.04  (--target runtime)
# Step 2: build (or skip) flaggems-hygon:dev from root Dockerfile
# Step 3: start container with -itd (detached), then exec into it
#
# Usage:
#   ./hygon/start.sh                         # default container name, mounts FlagGems
#   ./hygon/start.sh -n my_container         # custom container name
#   ./hygon/start.sh -f                      # force-recreate container
#   ./hygon/start.sh --rebuild-runtime       # force-rebuild runtime image
#   ./hygon/start.sh --rebuild-dev           # force-rebuild dev image
#   ./hygon/start.sh --rebuild               # force-rebuild both images
#   ./hygon/start.sh --ssh-agent             # use SSH agent forwarding instead
#   ./hygon/start.sh -c "python a.py"        # exec command (default: zsh)
#   ./hygon/start.sh --repo ../FlagTree      # mount FlagTree instead of FlagGems
#   ./hygon/start.sh --repo ../A --repo ../B # mount multiple repos
#
# See common/lib.sh for full option documentation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="hygon"
RUNTIME_DOCKERFILE="legacy/flaggems-hygon-26.04"

# ── Platform hardware flags ───────────────────────────────────────
platform_hardware_args() {
    cat << 'EOF'
--device=/dev/kfd
--device=/dev/mkfd
--device=/dev/dri
--group-add video
--privileged
EOF
}

# ── Platform extra mounts ─────────────────────────────────────────
# Hygon requires the hyhal driver directory from the host.
HYGON_EXTRA_MOUNTS=(-v /opt/hyhal:/opt/hyhal)

# Override _run_container to inject the extra mount before calling the base.
# We patch REPO_MOUNT_ARGS after parsing so lib_main picks it up transparently.
_hygon_patch_mounts() {
    REPO_MOUNT_ARGS=("${HYGON_EXTRA_MOUNTS[@]}" "${REPO_MOUNT_ARGS[@]}")
}

# ── Load shared logic ─────────────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"

# Wrap lib_main to inject the extra mount after arg parsing.
# _parse_args populates REPO_MOUNT_ARGS; we extend it before _run_container.
_orig_run_container() { _run_container "$@"; }
_run_container() {
    _hygon_patch_mounts
    _orig_run_container "$@"
}

lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
