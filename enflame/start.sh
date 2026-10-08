#!/usr/bin/env bash
# enflame/start.sh — launch the FlagGems Enflame development container.
#
# Step 1: build (or skip) flaggems-enflame:dev from root Dockerfile
#         using harbor.baai.ac.cn/flagos-runtime/flagos-runtime-enflame-tops1.10.6 as base
# Step 2: start container with -itd (detached), then exec into it
#
# Usage:
#   ./enflame/start.sh                         # default container name, mounts FlagGems
#   ./enflame/start.sh -n my_container         # custom container name
#   ./enflame/start.sh -f                      # force-recreate container
#   ./enflame/start.sh --rebuild-dev           # force-rebuild dev image
#   ./enflame/start.sh --rebuild               # force-rebuild dev image
#   ./enflame/start.sh --ssh-agent             # use SSH agent forwarding instead
#   ./enflame/start.sh -c "python a.py"        # exec command (default: zsh)
#   ./enflame/start.sh --repo ../FlagTree      # mount FlagTree instead of FlagGems
#   ./enflame/start.sh --repo ../A --repo ../B # mount multiple repos
#   ./enflame/start.sh --base-tag 2.2.0        # use FlagOS base image version 2.2.0
#
# See common/lib.sh for full option documentation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="enflame"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-tops1.10.6}"

# ── Platform hardware flags ───────────────────────────────────────
# Enflame GCUs are accessed through the full host /dev tree, which requires
# --privileged (matches the vendor-documented launch command).
platform_hardware_args() {
    echo "--privileged"
}

# ── Platform extra mounts ─────────────────────────────────────────
# Enflame requires the full host /dev tree (not individual --device entries)
# for its driver/runtime to enumerate GCUs.
ENFLAME_EXTRA_MOUNTS=(-v /dev:/dev)

# Override _run_container to inject the extra mount before calling the base.
# We patch REPO_MOUNT_ARGS after parsing so lib_main picks it up transparently.
_enflame_patch_mounts() {
    REPO_MOUNT_ARGS=("${ENFLAME_EXTRA_MOUNTS[@]}" "${REPO_MOUNT_ARGS[@]}")
}

# ── Load shared logic ─────────────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"

# Wrap lib_main to inject the extra mount after arg parsing.
# _parse_args populates REPO_MOUNT_ARGS; we extend it before _run_container.
# We use a wrapper that calls the original lib_main flow but intercepts
# at the right point to inject our platform-specific mounts.
_enflame_lib_main() {
    local script_dir="$1"; shift
    local repo_root="$1"; shift

    _parse_args "$@"

    # Inject Enflame-specific mounts after _parse_args but before container creation
    _enflame_patch_mounts

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
    docker exec -it -u "$(id -un)" -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 -w "${WORKSPACE_DIR}" "${CONTAINER_NAME}" "${EXEC_COMMAND[@]}"

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

_enflame_lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
