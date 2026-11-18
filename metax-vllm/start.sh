#!/usr/bin/env bash
# metax-vllm/start.sh — launch the FlagGems Metax dev container on the
# upstream Metax vllm base image.
#
# Base image:  harbor.baai.ac.cn/flaggems-vllm/vllm-metax:0.29.0-maca.ai3.9.0.9-torch2.10-py312-ubuntu24.04-amd64
#              (upstream Metax image — MACA + torch + vllm preinstalled;
#              dev image flaggems-vllm-metax:dev)
#
# Default repo mount: ../FlagGems-vllm (sibling checkout), not plain FlagGems —
# override with --repo to mount something else.
#
# Shares every bit of Metax platform logic with metax/start.sh (device
# flags, groups) — PLATFORM stays "metax" so this reuses the Dockerfile's
# ARG PLATFORM branch and common/lib.sh's group/env logic unchanged. The
# only difference from metax/start.sh is the base image, which is this
# upstream vllm image rather than FlagOS's flagos-runtime naming. Keep the
# two metax* start.sh files in sync when shared platform logic changes.
#
# Options and examples:  ./metax-vllm/start.sh --help
# Host requirements: export http_proxy/https_proxy if GitHub/GitCode are
# not directly reachable (common/lib.sh forwards them into the container);
# an SSH key registered on GitCode is an optional extra fallback.
# Full documentation:  common/lib.sh, README.md
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Default repo mount is the FlagGems-vllm sibling checkout, not plain
# FlagGems — this launcher targets the vllm-on-Metax workflow specifically.
# Still lands at /workspace/FlagGems inside the container (common/lib.sh's
# fallback mount target), so paths referenced from docs/CLAUDE.md stay the
# same regardless of which host checkout is mounted. Use --repo to override.
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems-vllm" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
# PLATFORM stays "metax" so this reuses the Dockerfile's ARG PLATFORM branch
# and lib.sh's device-mount logic unchanged. DEV_IMAGE/CONTAINER_NAME get a
# -vllm naming below so this never collides with metax/start.sh containers
# on the same host.
PLATFORM="metax"

# The vllm Metax image's own naming has no TOOLKIT_VERSION axis (the MACA
# version is baked into the image tag itself), so this is left unset —
# base_image_ref() falls back to BASE_IMAGE_NAME below regardless.

# The vllm Metax image is hosted on harbor.baai.ac.cn rather than the
# flagos-runtime-<platform>-<toolkit> naming scheme, so override all three
# pieces — same pattern hygon-vllm, nvidia-vllm, and mthreads-vllm use for
# their own non-standard base images.
BASE_IMAGE_REGISTRY="${BASE_IMAGE_REGISTRY:-harbor.baai.ac.cn}"
BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-${BASE_IMAGE_REGISTRY}/flaggems-vllm/vllm-metax}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-0.29.0-maca.ai3.9.0.9-torch2.10-py312-ubuntu24.04-amd64}"

# Distinct dev image / default container name so a vllm-metax container
# never collides with metax/start.sh on the same host. Named vllm-metax
# (vllm prefix) rather than metax-vllm to match the FlagGems-vllm repo
# checkout this launcher mounts by default.
DEV_IMAGE="${DEV_IMAGE:-flaggems-vllm-metax:dev}"
CONTAINER_NAME="${CONTAINER_NAME:-flaggems-vllm-metax-dev-$(id -un)}"

# ── Platform hardware flags ───────────────────────────────────────
# Identical to metax/start.sh — this is the same Metax hardware, just a
# different base image.
platform_hardware_args() {
    cat << 'EOF'
--device=/dev/mxcd
--device=/dev/dri
--group-add=video
EOF
}

# ── Load shared logic and run ─────────────────────────────────────
# metax has no extra host mounts or build/start hooks, so this launcher
# calls lib_main directly — no wrapper needed, unlike hygon-vllm/
# mthreads-vllm which patch in an extra -v mount first.
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"
lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
