#!/usr/bin/env bash
# nvidia/install-nsight-compute.sh — install NVIDIA Nsight Compute (ncu) into a
# running FlagGems NVIDIA dev container.
#
# Normally invoked by nvidia/start.sh through the platform_post_create hook.
# Safe to run by hand at any time (idempotent):
#
#     ./nvidia/install-nsight-compute.sh [container] [version]
#
# `version` is the apt package suffix: 2026.3.1 installs nsight-compute-2026.3.1,
# which is the same build NVIDIA publishes as the .run file 2026.3.1.2
# (apt reports it as 2026.3.1.2-1; ncu --version prints 2026.3.1.0).
# Default: $NSIGHT_COMPUTE_VERSION, else 2026.3.1.
#
# WHY apt instead of the vendor .run:
#   The FlagOS base image already configures NVIDIA's CUDA apt repo, which
#   publishes one package per release.  That sidesteps the .run's license prompt
#   (its makeself payload asks "Please type y to accept") and its 403 on direct
#   download, and it turns an upgrade into a one-token change:
#
#       NSIGHT_COMPUTE_VERSION=2026.4.0 ./nvidia/start.sh
#
#   For a release apt does not carry, set NSIGHT_COMPUTE_RUN_URL to the .run and
#   it is used instead.  Prefer the developer.nvidia.com/downloads/... form:
#   the developer.download.nvidia.com/assets/... form 403s when fetched directly.
#
# Result: tree at /opt/nvidia/nsight-compute/<version>/, plus a
# /usr/local/bin/ncu symlink so ncu is on PATH for every user.
set -uo pipefail

info()  { echo "==> $*"; }
warn()  { echo "[WARN] $*" >&2; }
error() { echo "[ERROR] $*" >&2; }

DEFAULT_VERSION="${NSIGHT_COMPUTE_VERSION:-2026.3.1}"

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

for _a in "$@"; do [[ "$_a" == "-h" || "$_a" == "--help" ]] && usage; done

_ctr="${1:-flaggems-nvidia-dev-$(id -un)}"
_ver="${2:-$DEFAULT_VERSION}"
[[ -z "$_ver" ]] && _ver="$DEFAULT_VERSION"

# The container's home directory is a host bind mount (see _run_container in
# common/lib.sh), so a cache kept under it survives container recreation.
_home="/home/$(id -un)"

# ── Preconditions ─────────────────────────────────────────────────
if ! docker ps --format '{{.Names}}' | grep -qx "$_ctr"; then
    error "容器未运行: ${_ctr}"
    error "先执行 ./nvidia/start.sh 创建容器"
    exit 1
fi

_arch="$(docker exec "$_ctr" uname -m 2>/dev/null || true)"
if [[ "$_arch" != "x86_64" ]]; then
    # NVIDIA ships Nsight Compute for x86_64 only — the arm64 CUDA repo has no
    # nsight-compute package at all (the sbsa repo stops at 2025.3.1).
    warn "nsight-compute 仅支持 x86_64（当前容器: ${_arch:-unknown}），跳过"
    exit 0
fi

if docker exec -u root "$_ctr" bash -c "dpkg -s 'nsight-compute-${_ver}' >/dev/null 2>&1"; then
    _current="$(docker exec "$_ctr" /opt/nvidia/nsight-compute/"${_ver}"/ncu --version 2>/dev/null | awk '/^Version/{print $2}')"
    info "nsight-compute-${_ver} 已安装${_current:+ (ncu ${_current})}，跳过"
    exit 0
fi

info "在容器 ${_ctr} 中安装 nsight-compute-${_ver} ..."

# ── Container-side apt script ─────────────────────────────────────
# Executed inside the container as root.  Written to a temp file on the host and
# copied in, because `docker exec` does not connect the host's stdin to the
# container process (same technique as ascend/start.sh).
_container_script() {
cat <<'SCRIPT'
#!/bin/bash
set -uo pipefail
ver="$1"
home_dir="$2"
pkg="nsight-compute-${ver}"

# apt lists are stripped from the image at build time, which also removes the
# lists/partial dir apt requires; recreate it before any apt-get call.
mkdir -p /var/lib/apt/lists/partial

# Cache the ~390 MB .deb under the container home (a persistent host bind
# mount) so re-creating the container does not re-download it.
cache="${home_dir}/.cache/nsight-compute"
mkdir -p "$cache"

apt-get update -qq || { echo "APT_UPDATE_FAILED"; exit 2; }

# apt-cache policy prints nothing (exit 0) for a package absent from every
# source, and "Candidate: (none)" for one that is known but unavailable (e.g.
# wrong architecture) — treat both as "no candidate" so the .run fallback runs.
_policy="$(apt-cache policy "$pkg" 2>/dev/null)"
if [[ -z "$_policy" ]] || echo "$_policy" | grep -q 'Candidate: (none)'; then
    echo "NO_CANDIDATE"
    exit 3
fi

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    -o Dir::Cache::archives="$cache" "$pkg" \
    || { echo "APT_INSTALL_FAILED"; exit 4; }

ln -sf "/opt/nvidia/nsight-compute/${ver}/ncu" /usr/local/bin/ncu
echo "OK"
SCRIPT
}

# ── Fallback: vendor .run self-extracting installer ───────────────
# Used only when the CUDA repo has no package for the requested version.
# Extracted with --noexec so the bundled install-linux.pl never runs — that is
# what would otherwise stop on the interactive license prompt.
_run_fallback() {
    local url="$1"
    [[ -n "$url" ]] || return 1

    warn "apt 无可用包，改用 .run 安装器: ${url}"
    local tmp
    tmp="$(mktemp /tmp/install-nsight-compute-run.XXXXXX.sh)"
    cat > "$tmp" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
url="$1"
dest="/opt/nvidia/nsight-compute-manual"
cd /tmp
rm -f ncu.run
curl -fL --retry 3 --connect-timeout 20 -o ncu.run "$url"
chmod +x ncu.run
rm -rf "$dest"
mkdir -p "$dest"
./ncu.run --noexec --nox11 --target "$dest" >/dev/null
rm -f ncu.run
# The extracted layout is not contractually fixed, so locate the CLI wrapper.
bin="$(find "$dest" -maxdepth 4 -name ncu -type f -perm -u+x | head -1)"
[[ -n "$bin" ]] || { echo "NCU_NOT_FOUND"; exit 5; }
ln -sf "$bin" /usr/local/bin/ncu
echo "OK"
SCRIPT
    docker cp "$tmp" "$_ctr:/tmp/install-nsight-compute-run.sh" >/dev/null
    docker exec -u root "$_ctr" bash /tmp/install-nsight-compute-run.sh "$url"
    local rc=$?
    docker exec -u root "$_ctr" rm -f /tmp/install-nsight-compute-run.sh 2>/dev/null
    rm -f "$tmp"
    return $rc
}

# ── Run ───────────────────────────────────────────────────────────
_tmp="$(mktemp /tmp/install-nsight-compute.XXXXXX.sh)"
_container_script > "$_tmp"
docker cp "$_tmp" "$_ctr:/tmp/install-nsight-compute.sh" >/dev/null
_out="$(docker exec -u root "$_ctr" bash /tmp/install-nsight-compute.sh "$_ver" "$_home" 2>&1)"
_rc=$?
docker exec -u root "$_ctr" rm -f /tmp/install-nsight-compute.sh 2>/dev/null
rm -f "$_tmp"

case "$_rc" in
    0)  : ;;
    3)  if ! _run_fallback "${NSIGHT_COMPUTE_RUN_URL:-}"; then
            error "nsight-compute-${_ver} 不在 CUDA apt 源中，且未提供可用的 NSIGHT_COMPUTE_RUN_URL"
            error "可执行 'apt-cache search --names-only ^nsight-compute-' 查看可用版本"
            exit 1
        fi ;;
    *)  error "安装失败（退出码 ${_rc}）"
        echo "$_out" | tail -20 >&2
        error "容器其余功能不受影响；可在容器内重试: sudo apt-get install nsight-compute-${_ver}"
        exit 1 ;;
esac

# ── Verify ────────────────────────────────────────────────────────
_version_out="$(docker exec "$_ctr" /usr/local/bin/ncu --version 2>/dev/null | awk '/^Version/{print $2}')"
if [[ -n "$_version_out" ]]; then
    info "ncu ${_version_out} 已就绪（/usr/local/bin/ncu）"
else
    warn "ncu 已安装但 --version 未返回结果，请进入容器手动确认"
fi
