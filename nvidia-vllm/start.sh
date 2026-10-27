#!/usr/bin/env bash
# nvidia-vllm/start.sh — launch the FlagGems NVIDIA dev container on the
# upstream NVIDIA vllm base image.
#
# Base image:  nvcr.io/nvidia/vllm:26.10.pre1-py3
#              (upstream NVIDIA NGC image — CUDA + torch + vllm preinstalled;
#              dev image flaggems-vllm-nvidia:dev)
#
# Default repo mount: ../FlagGems-vllm (sibling checkout), not plain FlagGems —
# override with --repo to mount something else.
#
# Shares every bit of NVIDIA platform logic with nvidia/start.sh (--gpus all,
# apt/pip package branch in the Dockerfile and common/lib.sh) — PLATFORM stays
# "nvidia" so this reuses that branch unchanged. The only difference from
# nvidia/start.sh is the base image: this upstream vllm image rather than
# FlagOS's flagos-app/vllm0.24.0-generic-13.3 naming. That base image has no
# /flagos venv (it installs vllm/torch straight into the system Python),
# which common/lib.sh already accounts for — the /flagos/bin PATH-prepend on
# commit is gated on /flagos actually existing, not just PLATFORM == nvidia.
# Keep the two nvidia* start.sh files in sync when shared platform logic
# changes.
#
# Options and examples:  ./nvidia-vllm/start.sh --help
# Host requirements: export http_proxy/https_proxy if GitHub/GitCode are
# not directly reachable (common/lib.sh forwards them into the container);
# an SSH key registered on GitCode is an optional extra fallback.
# Full documentation:  common/lib.sh, README.md
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Default repo mount is the FlagGems-vllm sibling checkout, not plain
# FlagGems — this launcher targets the vllm-on-NVIDIA workflow specifically.
# Still lands at /workspace/FlagGems inside the container (common/lib.sh's
# fallback mount target), so paths referenced from docs/CLAUDE.md stay the
# same regardless of which host checkout is mounted. Use --repo to override.
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems-vllm" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
# PLATFORM stays "nvidia" so this reuses the Dockerfile's ARG PLATFORM branch
# (python3-pip/clang-format/openssh-client + pre-commit/flake8/black/isort)
# and lib.sh's --gpus all hardware-arg logic unchanged. DEV_IMAGE/CONTAINER_NAME
# get a -vllm naming below so this never collides with nvidia/start.sh
# containers on the same host.
PLATFORM="nvidia"

# vllm's own image naming has no TOOLKIT_VERSION axis (the CUDA version is
# baked into the vllm image tag itself), so this is left unset —
# base_image_ref() falls back to BASE_IMAGE_NAME below regardless.

# The vllm image is identified by registry+repo+tag directly rather than the
# flagos-app/flagos-runtime naming scheme, so override all three pieces —
# same pattern hygon-vllm, ascend-vllm, and thead use for their own
# non-standard base images.
BASE_IMAGE_REGISTRY="${BASE_IMAGE_REGISTRY:-nvcr.io}"
BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-${BASE_IMAGE_REGISTRY}/nvidia/vllm}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-26.10.pre1-py3}"

# Distinct dev image / default container name so a vllm-nvidia container
# never collides with nvidia/start.sh on the same host. Named vllm-nvidia
# (vllm prefix) rather than nvidia-vllm to match the FlagGems-vllm repo
# checkout this launcher mounts by default.
DEV_IMAGE="${DEV_IMAGE:-flaggems-vllm-nvidia:dev}"
CONTAINER_NAME="${CONTAINER_NAME:-flaggems-vllm-nvidia-dev-$(id -un)}"

# ── Platform hardware flags ───────────────────────────────────────
# Identical to nvidia/start.sh — this is the same GPU hardware, just a
# different base image.
platform_hardware_args() {
    cat << 'EOF'
--gpus all
--ulimit nofile=1048576:1048576
EOF
}

# ── Load shared logic ─────────────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"

# Wrap _run_container to install Nsight Compute (ncu) once the container is up,
# same as nvidia/start.sh — see nvidia/install-nsight-compute.sh for the
# apt-vs-.run install logic and how to pin/upgrade the version
# (NSIGHT_COMPUTE_VERSION). Best-effort: a failure here does not fail the launch.
eval "_orig_run_container() $(declare -f _run_container | tail -n +2)"
_run_container() {
    _orig_run_container "$@"
    if container_running; then
        "${REPO_ROOT}/nvidia/install-nsight-compute.sh" "${CONTAINER_NAME}" "${NSIGHT_COMPUTE_VERSION:-}" || true
    fi
}

lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
