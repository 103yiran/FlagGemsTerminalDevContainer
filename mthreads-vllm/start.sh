#!/usr/bin/env bash
# mthreads-vllm/start.sh — launch the FlagGems Moore Threads dev container on
# the upstream Moore Threads vllm base image.
#
# Base image:  registry.mthreads.com/mcconline/inference/vllm/vllm-openai:v0.32.0
#              (upstream Moore Threads image — MUSA + torch + vllm preinstalled;
#              dev image flaggems-vllm-mthreads:dev)
#
# Default repo mount: ../FlagGems-vllm (sibling checkout), not plain FlagGems —
# override with --repo to mount something else.
#
# Shares every bit of Moore Threads platform logic with mthreads/start.sh
# (device flags, groups, /usr/bin/mthreads-gmi mount) — PLATFORM stays
# "mthreads" so this reuses the Dockerfile's ARG PLATFORM branch and
# common/lib.sh's group/env logic unchanged. The only difference from
# mthreads/start.sh is the base image, which is this upstream vllm image
# rather than FlagOS's flagos-runtime naming. Keep the two mthreads*
# start.sh files in sync when shared platform logic changes.
#
# Options and examples:  ./mthreads-vllm/start.sh --help
# Host requirements: export http_proxy/https_proxy if GitHub/GitCode are
# not directly reachable (common/lib.sh forwards them into the container);
# an SSH key registered on GitCode is an optional extra fallback.
# Full documentation:  common/lib.sh, README.md
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Default repo mount is the FlagGems-vllm sibling checkout, not plain
# FlagGems — this launcher targets the vllm-on-Moore-Threads workflow
# specifically. Still lands at /workspace/FlagGems inside the container
# (common/lib.sh's fallback mount target), so paths referenced from
# docs/CLAUDE.md stay the same regardless of which host checkout is
# mounted. Use --repo to override.
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems-vllm" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
# PLATFORM stays "mthreads" so this reuses the Dockerfile's ARG PLATFORM
# branch and lib.sh's device-mount/group logic unchanged. DEV_IMAGE/
# CONTAINER_NAME get a -vllm naming below so this never collides with
# mthreads/start.sh containers on the same host.
PLATFORM="mthreads"

# The vllm Moore Threads image's own naming has no TOOLKIT_VERSION axis (the
# MUSA version is baked into the image tag itself), so this is left unset —
# base_image_ref() falls back to BASE_IMAGE_NAME below regardless.

# The vllm Moore Threads image is identified by registry+repo+tag directly
# rather than the flagos-runtime-<platform>-<toolkit> naming scheme, so
# override all three pieces — same pattern hygon-vllm, nvidia-vllm, and the
# ascend-vllm launchers use for their own non-standard base images.
BASE_IMAGE_REGISTRY="${BASE_IMAGE_REGISTRY:-registry.mthreads.com}"
BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-${BASE_IMAGE_REGISTRY}/mcconline/inference/vllm/vllm-openai}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-v0.32.0}"

# Distinct dev image / default container name so a vllm-mthreads container
# never collides with mthreads/start.sh on the same host. Named vllm-mthreads
# (vllm prefix) rather than mthreads-vllm to match the FlagGems-vllm repo
# checkout this launcher mounts by default.
DEV_IMAGE="${DEV_IMAGE:-flaggems-vllm-mthreads:dev}"
CONTAINER_NAME="${CONTAINER_NAME:-flaggems-vllm-mthreads-dev-$(id -un)}"

# ── Platform hardware flags ───────────────────────────────────────
# Identical to mthreads/start.sh — this is the same Moore Threads hardware,
# just a different base image.
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

# ── Platform user groups ──────────────────────────────────────────
# The base image has no "render" group, so --group-add render fails at
# `docker run` time unless the group exists inside the image first.
# lib.sh's _build_dev creates any group named here before useradd.
# The GID must match the host's "render" group (owner of /dev/dri/renderD*)
# or the container user won't actually have device access despite being
# nominally "in" a same-named group.
platform_user_groups() {
    local render_gid
    render_gid="$(getent group render 2>/dev/null | cut -d: -f3)"
    if [ -n "$render_gid" ]; then
        echo "render:${render_gid}"
    else
        echo "render"
    fi
}

# ── Platform extra mounts ─────────────────────────────────────────
# mthreads requires the mthreads-gmi CLI tool from the host, same as
# mthreads/start.sh.
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

_mthreads_lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
