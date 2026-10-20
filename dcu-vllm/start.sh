#!/usr/bin/env bash
# dcu-vllm/start.sh — launch the FlagGems DCU dev container on the
# Hygon DCU vllm base image.
#
# Base image:  harbor.sourcefind.cn:5443/hcu/admin/base/vllm:0.21.0-ubuntu22.04-dtk2604-py3.10
#              (upstream Hygon DCU image — DTK + vllm preinstalled;
#              dev image flaggems-vllm-dcu:dev)
#
# Default repo mount: ../FlagGems-vllm (sibling checkout), not plain FlagGems —
# override with --repo to mount something else.
#
# Shares every bit of DCU platform logic with hygon/start.sh (device flags,
# /opt/hyhal mount) — PLATFORM stays "hygon" so this reuses the Dockerfile's
# ARG PLATFORM branch and common/lib.sh's group/env logic unchanged. The only
# difference from hygon/start.sh is the base image, which is this upstream
# vllm image rather than FlagOS's flagos-runtime naming. Keep the two hygon*
# start.sh files in sync when shared platform logic changes.
#
# Options and examples:  ./dcu-vllm/start.sh --help
# Host requirements: export http_proxy/https_proxy if GitHub/GitCode are
# not directly reachable (common/lib.sh forwards them into the container);
# an SSH key registered on GitCode is an optional extra fallback.
# Full documentation:  common/lib.sh, README.md
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Default repo mount is the FlagGems-vllm sibling checkout, not plain
# FlagGems — this launcher targets the vllm-on-DCU workflow specifically.
# Still lands at /workspace/FlagGems inside the container (common/lib.sh's
# fallback mount target), so paths referenced from docs/CLAUDE.md stay the
# same regardless of which host checkout is mounted. Use --repo to override.
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems-vllm" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
# PLATFORM stays "hygon" so this reuses the Dockerfile's ARG PLATFORM branch
# and lib.sh's device-mount logic unchanged. DEV_IMAGE/CONTAINER_NAME get a
# -vllm suffix below so this never collides with hygon/start.sh containers
# on the same host.
PLATFORM="hygon"

# The vllm DCU image's own naming has no TOOLKIT_VERSION axis (the DTK
# version is baked into the image tag itself), so this is left unset —
# base_image_ref() falls back to BASE_IMAGE_NAME below regardless.

# The vllm DCU image is identified by registry+repo+tag directly rather than
# the flagos-runtime-<platform>-<toolkit> naming scheme, so override all
# three pieces — same pattern nvidia, thead, and the ascend-vllm launchers
# use for their own non-standard base images.
BASE_IMAGE_REGISTRY="${BASE_IMAGE_REGISTRY:-harbor.sourcefind.cn:5443}"
BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-${BASE_IMAGE_REGISTRY}/hcu/admin/base/vllm}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-0.21.0-ubuntu22.04-dtk2604-py3.10}"

# Distinct dev image / default container name so a vllm-dcu container never
# collides with hygon/start.sh on the same host. Named vllm-dcu (vllm prefix)
# rather than dcu-vllm to match the FlagGems-vllm repo checkout this launcher
# mounts by default.
DEV_IMAGE="${DEV_IMAGE:-flaggems-vllm-dcu:dev}"
CONTAINER_NAME="${CONTAINER_NAME:-flaggems-vllm-dcu-dev-$(id -un)}"

# ── Platform hardware flags ───────────────────────────────────────
# Identical to hygon/start.sh — this is the same DCU hardware, just a
# different base image.
platform_hardware_args() {
    cat << 'EOF'
--device=/dev/kfd
--device=/dev/mkfd
--device=/dev/dri
--group-add video
--group-add 39
--privileged
EOF
}

# ── Platform extra mounts ─────────────────────────────────────────
# DCU requires the hyhal driver directory from the host, same as hygon/start.sh.
DCU_EXTRA_MOUNTS=(-v /opt/hyhal:/opt/hyhal)

# Override _run_container to inject the extra mount before calling the base.
# We patch REPO_MOUNT_ARGS after parsing so lib_main picks it up transparently.
_dcu_patch_mounts() {
    REPO_MOUNT_ARGS=("${DCU_EXTRA_MOUNTS[@]}" "${REPO_MOUNT_ARGS[@]}")
}

# ── Load shared logic ─────────────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"

# Wrap lib_main to inject the extra mount after arg parsing.
# _parse_args populates REPO_MOUNT_ARGS; we extend it before _run_container.
# We use a wrapper that calls the original lib_main flow but intercepts
# at the right point to inject our platform-specific mounts.
_dcu_lib_main() {
    local script_dir="$1"; shift
    local repo_root="$1"; shift

    _parse_args "$@"

    # Inject DCU-specific mounts after _parse_args but before container creation
    _dcu_patch_mounts

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

_dcu_lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
