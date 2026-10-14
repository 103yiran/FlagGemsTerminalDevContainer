#!/usr/bin/env bash
# iluvatar/start.sh — launch the FlagGems Iluvatar development container.
#
# Base image:  harbor.baai.ac.cn/flagos-runtime/flagos-runtime-iluvatar-corex4.5.0:2.1.2
#              (toolkit corex4.5.0; dev image flaggems-iluvatar:dev)
#
# Options and examples:  ./iluvatar/start.sh --help
# Host requirements: export http_proxy/https_proxy if GitHub/GitCode are
# not directly reachable (common/lib.sh forwards them into the container);
# an SSH key registered on GitCode is an optional extra fallback.
# Full documentation:  common/lib.sh, README.md
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="iluvatar"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-corex4.5.0}"

# ── Platform hardware flags ───────────────────────────────────────
# Expose all 16 Iluvatar devices (/dev/iluvatar0 .. /dev/iluvatar15)
# plus the corex control device (/dev/itrctl), which the driver needs
# to initialize — without it cudaGetDeviceCount() fails with error 1001.
platform_hardware_args() {
    echo "--device=/dev/itrctl"
    for i in $(seq 0 15); do
        echo "--device=/dev/iluvatar${i}"
    done
}

# ── Platform extra mounts ─────────────────────────────────────────
# Iluvatar requires the corex runtime directory from the host.
ILUVATAR_EXTRA_MOUNTS=(-v /usr/local/corex:/usr/local/corex:ro)

# Override _run_container to inject the extra mount before calling the base.
# We patch REPO_MOUNT_ARGS after parsing so lib_main picks it up transparently.
_iluvatar_patch_mounts() {
    REPO_MOUNT_ARGS=("${ILUVATAR_EXTRA_MOUNTS[@]}" "${REPO_MOUNT_ARGS[@]}")
}

# ── Load shared logic ─────────────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"

# Wrap lib_main to inject the extra mount after arg parsing.
# _parse_args populates REPO_MOUNT_ARGS; we extend it before _run_container.
# We use a wrapper that calls the original lib_main flow but intercepts
# at the right point to inject our platform-specific mounts.
_iluvatar_lib_main() {
    local script_dir="$1"; shift
    local repo_root="$1"; shift

    _parse_args "$@"

    # Inject Iluvatar-specific mounts after _parse_args but before container creation
    _iluvatar_patch_mounts

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

_iluvatar_lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
