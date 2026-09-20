#!/usr/bin/env bash
# mthreads/start.sh — launch the FlagGems Moore Threads development container.
#
# Step 1: build (or skip) flaggems-mthreads:dev from root Dockerfile
#         using harbor.baai.ac.cn/flagos-runtime/flagos-runtime-mthreads-musa5.2.0 as base
# Step 2: start container with -itd (detached), then exec into it
#
# Usage:
#   ./mthreads/start.sh                         # default container name, mounts FlagGems
#   ./mthreads/start.sh -n my_container         # custom container name
#   ./mthreads/start.sh -f                      # force-recreate container
#   ./mthreads/start.sh --rebuild-dev           # force-rebuild dev image
#   ./mthreads/start.sh --rebuild               # force-rebuild dev image
#   ./mthreads/start.sh --ssh-agent             # use SSH agent forwarding instead
#   ./mthreads/start.sh -c "python a.py"        # exec command (default: zsh)
#   ./mthreads/start.sh --repo ../FlagTree      # mount FlagTree instead of FlagGems
#   ./mthreads/start.sh --repo ../A --repo ../B # mount multiple repos
#   ./mthreads/start.sh --base-tag 2.2.0        # use FlagOS base image version 2.2.0
#
# See common/lib.sh for full option documentation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="mthreads"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-musa5.2.0}"

# ── Platform hardware flags ───────────────────────────────────────
# Expose 8 Moore Threads GPU devices (/dev/mtgpu.0 .. /dev/mtgpu.7) plus
# /dev/dri, and add the container user to the render/video groups the
# driver needs for device access.
platform_hardware_args() {
    for i in $(seq 0 7); do
        echo "--device=/dev/mtgpu.${i}"
    done
    cat << 'EOF'
--device=/dev/dri
--group-add render
--group-add video
EOF
}

# ── Platform extra mounts ─────────────────────────────────────────
# mthreads requires the mthreads-gmi CLI tool from the host.
MTHREADS_EXTRA_MOUNTS=(-v /usr/bin/mthreads-gmi:/usr/bin/mthreads-gmi:ro)

# Override _run_container to inject the extra mount before calling the base.
# We patch REPO_MOUNT_ARGS after parsing so lib_main picks it up transparently.
_mthreads_patch_mounts() {
    REPO_MOUNT_ARGS=("${MTHREADS_EXTRA_MOUNTS[@]}" "${REPO_MOUNT_ARGS[@]}")
}

# ── Load shared logic ─────────────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"

# Wrap lib_main to inject the extra mount after arg parsing.
# _parse_args populates REPO_MOUNT_ARGS; we extend it before _run_container.
# We use a wrapper that calls the original lib_main flow but intercepts
# at the right point to inject our platform-specific mounts.
_mthreads_lib_main() {
    local script_dir="$1"; shift
    local repo_root="$1"; shift

    _parse_args "$@"

    # Inject mthreads-specific mounts after _parse_args but before container creation
    _mthreads_patch_mounts

    if [[ "$SSH_MODE" == "agent" ]]; then
        _ensure_ssh_agent
    fi

    _build_dev      "$script_dir" "$repo_root"
    _print_summary

    if $FORCE_RECREATE && container_exists; then
        print_warn "强制重建：删除已有容器 ${CONTAINER_NAME}"
        container_running && docker stop "${CONTAINER_NAME}" > /dev/null
        docker rm "${CONTAINER_NAME}" > /dev/null
        print_info "已删除旧容器"
    fi

    _build_ssh_args
    _run_container "$script_dir" "$repo_root"

    print_step "进入容器: ${CONTAINER_NAME} — exec: ${EXEC_COMMAND[*]}"
    docker exec -it -u "$(id -un)" -w "${WORKSPACE_DIR}" "${CONTAINER_NAME}" "${EXEC_COMMAND[@]}"

    echo ""
    print_step "已退出容器（容器仍在后台运行）"
    echo ""
    echo -e "${CYAN}常用管理命令:${NC}"
    echo "  查看状态: docker ps -a | grep ${CONTAINER_NAME}"
    echo "  再次进入: docker exec -it ${CONTAINER_NAME} zsh"
    echo "  停止容器: docker stop ${CONTAINER_NAME}"
    echo "  删除容器: docker rm ${CONTAINER_NAME}"
    echo ""
}

_mthreads_lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
