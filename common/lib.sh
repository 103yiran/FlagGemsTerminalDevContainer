#!/usr/bin/env bash
# common/lib.sh — shared logic for nvidia/start.sh, hygon/start.sh, cambricon/start.sh, metax/start.sh
#
# Callers must set before sourcing:
#   PLATFORM          nvidia | hygon | cambricon | metax
#
# Callers may override defaults:
#   DEV_IMAGE         (default: flaggems-${PLATFORM}:dev)
#   CONTAINER_NAME    (default: flaggems-${PLATFORM}-dev-$(id -un))
#   BASE_IMAGE_TAG    (default: 2.1.2)
#   TOOLKIT_VERSION   (optional: override toolkit version, passed as TOOLKIT build-arg)
#
# After sourcing, callers must define:
#   platform_hardware_args   function — echoes platform-specific docker run flags
#
# Then call:  lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────
DEV_IMAGE="${DEV_IMAGE:-flaggems-${PLATFORM}:dev}"
CONTAINER_NAME="${CONTAINER_NAME:-flaggems-${PLATFORM}-dev-$(id -un)}"

# nvidia uses a dedicated vllm base image under a different registry path
if [[ "${PLATFORM}" == "nvidia" ]]; then
    BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-2.1.2-0.2.1_g825c1cd}"
    BASE_IMAGE_REGISTRY="${BASE_IMAGE_REGISTRY:-harbor.baai.ac.cn/flagos-app}"
    BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-harbor.baai.ac.cn/flagos-app/vllm0.20.2-nvidia-cuda13.3}"
else
    BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-2.1.2}"
    BASE_IMAGE_REGISTRY="${BASE_IMAGE_REGISTRY:-harbor.baai.ac.cn/flagos-runtime}"
fi

# ── Runtime state ─────────────────────────────────────────────────
FORCE_RECREATE=false
FORCE_REBUILD_DEV=false
EXEC_COMMAND=(zsh)
SSH_MODE="mount"   # "mount" | "agent"
REPO_MOUNTS=()

# ── Colors ────────────────────────────────────────────────────────
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m' CYAN='\033[0;36m' NC='\033[0m'

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# ── Docker helpers ────────────────────────────────────────────────
image_exists()     { docker image inspect "$1" > /dev/null 2>&1; }
container_exists() { docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; }
container_running(){ docker ps    --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; }

# ── Help ──────────────────────────────────────────────────────────
show_help() {
    cat << EOF
用法: start.sh [选项] [container_name]

选项:
    -h, --help              显示帮助信息
    -n, --name NAME         指定容器名称 (默认: flaggems-${PLATFORM}-dev-<username>)
    -f, --force             强制重建容器
        --rebuild-dev       强制重新构建 dev 镜像
        --rebuild           强制重新构建 dev 镜像（与 --rebuild-dev 等价）
        --ssh-agent         使用 SSH agent 转发（默认: 挂载 ~/.ssh）
    -c, --cmd COMMAND       exec 进容器时执行的命令（默认: zsh）
        --repo PATH         挂载仓库到 /workspace/<name>，可重复使用
                            （默认: FlagGems → /workspace/FlagGems）
        --base-tag VERSION  指定 FlagOS base 镜像版本（默认: 2.1.2）

SSH 说明:
    默认将宿主机 ~/.ssh 以只读方式挂载到容器内，密钥作为文件存在。
    --ssh-agent 模式下私钥不进入容器，仅转发 SSH_AUTH_SOCK socket，
    需要宿主机已运行 ssh-agent 并通过 ssh-add 加载密钥。

示例:
    start.sh                                # 默认容器名，挂载 FlagGems
    start.sh --repo ../FlagTree             # 挂载 FlagTree 替代 FlagGems
    start.sh --repo ../FlagTree \\
             --repo ../FlagGems             # 同时挂载多个仓库
    start.sh my_dev                         # 自定义容器名
    start.sh -f                             # 强制删除并重建容器
    start.sh --rebuild                      # 重新构建 dev 镜像
    start.sh --ssh-agent                    # 使用 SSH agent 转发
    start.sh -c "python train.py"           # exec 执行特定命令
    start.sh --base-tag 2.2.0               # 使用 2.2.0 版本的基础镜像
EOF
    exit 0
}

# ── Argument parsing ──────────────────────────────────────────────
_parse_args() {
    local _default_name="flaggems-${PLATFORM}-dev-$(id -un)"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)         show_help ;;
            -f|--force)        FORCE_RECREATE=true;        shift ;;
            --rebuild-dev)     FORCE_REBUILD_DEV=true;     shift ;;
            --rebuild)         FORCE_REBUILD_DEV=true;     shift ;;
            --ssh-agent)       SSH_MODE="agent";           shift ;;
            --base-tag)        BASE_IMAGE_TAG="$2";        shift 2 ;;
            --repo)
                local _rhost
                _rhost="$(cd "$2" && pwd)"
                REPO_MOUNTS+=("${_rhost}:/workspace/$(basename "${_rhost}")")
                shift 2 ;;
            -c|--cmd)          EXEC_COMMAND=($2);          shift 2 ;;
            -n|--name)         CONTAINER_NAME="$2";        shift 2 ;;
            -*)                print_error "未知选项: $1"; show_help ;;
            *)
                if [[ "$CONTAINER_NAME" == "$_default_name" ]]; then
                    CONTAINER_NAME="$1"
                else
                    print_error "多余的参数: $1"; show_help
                fi
                shift ;;
        esac
    done

    if [[ ${#REPO_MOUNTS[@]} -eq 0 ]]; then
        REPO_MOUNTS+=("${FLAGGEMS_ROOT}:/workspace/FlagGems")
    fi

    REPO_MOUNT_ARGS=()
    for _pair in "${REPO_MOUNTS[@]}"; do
        REPO_MOUNT_ARGS+=(-v "$_pair")
    done
    WORKSPACE_DIR="${REPO_MOUNTS[0]#*:}"
}

# ── SSH agent ─────────────────────────────────────────────────────
_ensure_ssh_agent() {
    if [[ -z "${SSH_AUTH_SOCK:-}" ]] || ! ssh-add -l &>/dev/null; then
        print_step "启动 ssh-agent 并加载密钥..."
        eval "$(ssh-agent -s)" > /dev/null

        local added=0
        for key in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ecdsa"; do
            if [[ -f "$key" ]]; then
                ssh-add "$key" 2>/dev/null && {
                    print_success "已加载密钥: $key"
                    added=$((added + 1))
                }
            fi
        done

        if [[ $added -eq 0 ]]; then
            print_warn "未找到标准私钥（id_ed25519 / id_rsa / id_ecdsa）"
            print_warn "如密钥路径不同，请手动运行: ssh-add <私钥路径>"
            print_warn "setup.sh 需要 SSH 访问 GitHub，密钥缺失时 nvim/zsh 插件安装将跳过"
        fi
    else
        print_info "ssh-agent 已运行，已加载密钥: $(ssh-add -l | wc -l) 个"
    fi
}

# ── SSH mount/agent args ──────────────────────────────────────────
_build_ssh_args() {
    SSH_ARGS=()
    if [[ "$SSH_MODE" == "agent" ]]; then
        if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
            print_warn "SSH_AUTH_SOCK 未设置，agent 转发不可用，回退到 ~/.ssh 挂载"
            SSH_MODE="mount"
        else
            print_info "SSH 模式: agent 转发 (${SSH_AUTH_SOCK})"
            SSH_ARGS+=(
                -v "${SSH_AUTH_SOCK}":/tmp/ssh_auth.sock:ro
                -e SSH_AUTH_SOCK=/tmp/ssh_auth.sock
            )
        fi
    fi
    if [[ "$SSH_MODE" == "mount" ]]; then
        if [[ -d "$HOME/.ssh" ]]; then
            print_info "SSH 模式: 挂载 ~/.ssh（只读）"
            SSH_ARGS+=(-v "$HOME/.ssh":/home/"$(id -un)"/.ssh)
        else
            print_warn "~/.ssh 不存在，跳过 SSH 挂载"
        fi
    fi
}

# ── Build: dev image ──────────────────────────────────────────────
# This host's seccomp profile blocks container creation inside docker build,
# so we use the run→exec→commit pattern instead of docker build.
_build_dev() {
    local script_dir="$1"
    local repo_root="$2"
    if $FORCE_REBUILD_DEV || ! image_exists "$DEV_IMAGE"; then
        $FORCE_REBUILD_DEV \
            && print_step "强制重新构建 dev 镜像: $DEV_IMAGE" \
            || print_step "dev 镜像不存在，开始构建: $DEV_IMAGE"

        # BASE_IMAGE_NAME can be set by the caller to override the default image name
        # (without tag); the tag is always appended from BASE_IMAGE_TAG.
        local _base_name="${BASE_IMAGE_NAME:-${BASE_IMAGE_REGISTRY}/flagos-runtime-${PLATFORM}-${TOOLKIT_VERSION}}"
        local base_image="${_base_name}:${BASE_IMAGE_TAG}"
        local build_ctr="flaggems-build-$$"
        local _username _uid _gid _extra_groups
        _username="$(id -un)"
        _uid="$(id -u)"
        _gid="$(id -g)"

        # Platform-specific user groups (e.g., HwHiAiUser for Ascend)
        _extra_groups=""
        if declare -f platform_user_groups > /dev/null 2>&1; then
            _extra_groups="$(platform_user_groups)"
        fi

        # Collect any extra docker run args the platform wants for the build
        # container (e.g. Ascend mounts the host driver read-only so it can be
        # baked into the image with corrected permissions).
        local _platform_build_args=()
        if declare -f platform_build_args > /dev/null 2>&1; then
            while IFS= read -r _line; do
                [[ -n "$_line" ]] || continue
                # Split each line into words so "-v /path:/path:ro" becomes
                # two separate array elements ("-v" and "/path:/path:ro"),
                # which is what docker run expects.
                read -ra _words <<< "$_line"
                _platform_build_args+=("${_words[@]}")
            done < <(platform_build_args)
        fi

        # Ensure the build container is removed even if the build fails
        trap "docker rm -f '$build_ctr' 2>/dev/null || true" EXIT

        # Start a throw-away container with seccomp=unconfined so RUN commands work
        docker run -d \
            --name "$build_ctr" \
            --security-opt seccomp=unconfined \
            "${_platform_build_args[@]}" \
            "$base_image" \
            sleep infinity

        # Execute every layer from the Dockerfile in order
        docker exec "$build_ctr" bash -c "
set -e
# Layer 1: uv cache dir, /flagos ownership, uv symlink
mkdir -p /usr/local/share/uv /root/.local/bin /flagos
chown -R '${_uid}:${_gid}' /usr/local/share/uv
chown -R '${_uid}:${_gid}' /flagos
if [ -f /root/.local/bin/uv ]; then
    ln -sf /root/.local/bin/uv /usr/local/bin/uv
fi

# Layer 2: apt sources → Aliyun mirror
sed -i \
    -e 's|http://archive.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
    -e 's|http://security.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
    /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null \
|| sed -i \
    -e 's|http://archive.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
    -e 's|http://security.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
    /etc/apt/sources.list

# Layer 3: system packages + user creation
PLATFORM='${PLATFORM}'
apt-get update
apt-get install -y --no-install-recommends \
    sudo zsh git curl wget unzip ca-certificates ripgrep fd-find gh openssh-client \
    \$([ \"\$PLATFORM\" = 'nvidia' ] && echo 'python3-pip clang-format')
if [ \"\$PLATFORM\" = 'nvidia' ]; then
    /usr/bin/pip3 install --no-cache-dir --break-system-packages \
        --timeout 120 --retries 5 \
        --index-url https://mirrors.aliyun.com/pypi/simple/ \
        pre-commit==3.7.1 flake8==7.1.0 black==23.7.0 isort==5.12.0
fi

# Create platform-specific groups before user creation
EXTRA_GROUPS='${_extra_groups}'
if [ -n \"\$EXTRA_GROUPS\" ]; then
    for grp in \$EXTRA_GROUPS; do
        if ! getent group \"\$grp\" >/dev/null 2>&1; then
            groupadd \"\$grp\" 2>/dev/null || true
        fi
    done
fi

groupadd --gid '${_gid}' '${_username}'
if [ -n \"\$EXTRA_GROUPS\" ]; then
    # Create user with additional groups
    useradd --uid '${_uid}' --gid '${_gid}' -G \"\$EXTRA_GROUPS\" -m -s /usr/bin/zsh '${_username}'
else
    useradd --uid '${_uid}' --gid '${_gid}' -m -s /usr/bin/zsh '${_username}'
fi
echo '${_username} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/'${_username}'
chmod 0440 /etc/sudoers.d/'${_username}'
rm -rf /var/lib/apt/lists/*

# Layer 4: Neovim >= 0.11
# Skip if the base image already ships a satisfying version; otherwise download
# the tarball from NJU mirror (LatestRelease) with apt as fallback.
if nvim --version 2>/dev/null | head -1 | grep -qE 'NVIM v(0\.(1[1-9]|[2-9][0-9])|[1-9][0-9])'; then
    echo 'neovim already satisfies >= 0.11, skipping install'
    nvim --version | head -1
else
    _nvim_installed=false

    # NJU mirror tarball (LatestRelease, no FUSE required, architecture-aware)
    # Use -w to check HTTP status; avoid `file` command which may not be present.
    _nvim_darch=\$(uname -m | sed 's/aarch64/arm64/;s/x86_64/x86_64/')
    _nvim_filename=\"nvim-linux-\${_nvim_darch}.tar.gz\"
    _nvim_url=\"https://mirror.nju.edu.cn/github-release/neovim/neovim/LatestRelease/\${_nvim_filename}\"
    echo \"Trying: \${_nvim_url}\"
    rm -f /tmp/nvim.tar.gz
    _http_code=\$(curl -fsSL --retry 2 --connect-timeout 15 \
        -w '%{http_code}' \"\${_nvim_url}\" -o /tmp/nvim.tar.gz 2>/dev/null || true)
    if [ \"\${_http_code}\" = '200' ] && [ -s /tmp/nvim.tar.gz ]; then
        tar -xzf /tmp/nvim.tar.gz -C /usr/local --strip-components=1
        rm -f /tmp/nvim.tar.gz
        if nvim --version 2>/dev/null | head -1 | grep -qE 'NVIM v(0\.(1[1-9]|[2-9][0-9])|[1-9][0-9])'; then
            nvim --version | head -1
            _nvim_installed=true
        else
            echo 'WARNING: tarball extracted but nvim binary check failed'
        fi
    else
        rm -f /tmp/nvim.tar.gz
        echo \"NJU tarball download failed (HTTP \${_http_code})\"
    fi

    if [ \"\$_nvim_installed\" = false ]; then
        echo 'WARNING: neovim install failed from all sources'
    fi
fi

# Layer 5: Node.js + Claude Code CLI
# node release naming: arm64 stays arm64, x86_64 becomes x64.
_node_arch=\$(uname -m | sed 's/aarch64/arm64/;s/x86_64/x64/')
curl -fsSL --retry 3 \
    \"https://mirrors.aliyun.com/nodejs-release/v22.23.1/node-v22.23.1-linux-\${_node_arch}.tar.xz\" \
    -o /tmp/node.tar.xz
tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1
rm /tmp/node.tar.xz
npm install -g @anthropic-ai/claude-code \
    --registry https://registry.npmmirror.com
"
        # Platform post-build hook: runs inside the build container as root.
        # Used e.g. by Ascend to copy the host driver into the image and fix
        # permissions so non-root users can read the .so files.
        if declare -f platform_post_build_exec > /dev/null 2>&1; then
            print_step "运行平台 post-build 钩子..."
            platform_post_build_exec "$build_ctr"
            print_success "平台 post-build 钩子完成"
        fi

        # Commit the container as the dev image with metadata
        docker commit \
            --change "ENV UV_CACHE_DIR=/usr/local/share/uv" \
            --change "USER ${_username}" \
            --change "WORKDIR /workspace" \
            "$build_ctr" \
            "$DEV_IMAGE"

        docker rm -f "$build_ctr"
        trap - EXIT  # build succeeded, cancel the cleanup trap
        print_success "dev 镜像构建完成: $DEV_IMAGE"
        FORCE_RECREATE=true
    else
        print_info "dev 镜像已存在，跳过: $DEV_IMAGE"
    fi
}

# ── Print container summary ───────────────────────────────────────
_print_summary() {
    local base_image
    if [[ "$PLATFORM" == "nvidia" ]]; then
        local toolkit="${TOOLKIT_VERSION:-cuda13.3}"
        base_image="${BASE_IMAGE_NAME:-${BASE_IMAGE_REGISTRY}/vllm0.20.2-nvidia-${toolkit}}:${BASE_IMAGE_TAG}"
    elif [[ "$PLATFORM" == "hygon" ]]; then
        local toolkit="${TOOLKIT_VERSION:-dtk26.04}"
        base_image="${BASE_IMAGE_REGISTRY}/flagos-runtime-hygon-${toolkit}:${BASE_IMAGE_TAG}"
    elif [[ "$PLATFORM" == "cambricon" ]]; then
        local toolkit="${TOOLKIT_VERSION:-neuware4.7.2}"
        base_image="${BASE_IMAGE_REGISTRY}/flagos-runtime-cambricon-${toolkit}:${BASE_IMAGE_TAG}"
    elif [[ "$PLATFORM" == "ascend" ]]; then
        local toolkit="${TOOLKIT_VERSION:-cann9.0.0}"
        base_image="${BASE_IMAGE_REGISTRY}/flagos-runtime-ascend-${toolkit}:${BASE_IMAGE_TAG}"
    elif [[ "$PLATFORM" == "metax" ]]; then
        local toolkit="${TOOLKIT_VERSION:-maca3.8.1.3}"
        base_image="${BASE_IMAGE_REGISTRY}/flagos-runtime-metax-${toolkit}:${BASE_IMAGE_TAG}"
    else
        base_image="未知平台"
    fi

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}容器信息:${NC}"
    echo -e "${CYAN}  名称:         ${CONTAINER_NAME}${NC}"
    echo -e "${CYAN}  镜像:         ${DEV_IMAGE}${NC}"
    echo -e "${CYAN}  基础镜像:     ${base_image}${NC}"
    for _pair in "${REPO_MOUNTS[@]}"; do
        echo -e "${CYAN}  挂载:         ${_pair}${NC}"
    done
    echo -e "${CYAN}  工作目录:     ${WORKSPACE_DIR}${NC}"
    echo -e "${CYAN}  SSH 模式:     ${SSH_MODE}${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

# ── Create or start container ─────────────────────────────────────
# Callers must define: platform_hardware_args
#   — a function that outputs platform-specific docker run flags, one per line.
_run_container() {
    local script_dir="$1"
    local repo_root="$2"

    local container_home_host="$HOME/${CONTAINER_NAME}"
    if [[ ! -d "$container_home_host" ]]; then
        print_step "创建容器 home 目录: ${container_home_host}"
        mkdir -p "$container_home_host"
    fi
    # Ensure the directory is owned by the current user, not root
    # (in case it was created by a previous run with different permissions)
    if [[ -O "$container_home_host" ]]; then
        : # Already owned by current user
    else
        print_warn "容器 home 目录由 root 拥有，需要手动修复权限："
        print_warn "  sudo chown -R $(id -u):$(id -g) \"$container_home_host\""
        return 1
    fi

    local hw_args=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && hw_args+=($line)
    done < <(platform_hardware_args)

    if ! container_exists; then
        print_step "创建并后台启动容器: ${CONTAINER_NAME}"
        docker run -d \
            --name "${CONTAINER_NAME}" \
            "${hw_args[@]}" \
            --user=root \
            --net=host \
            --ipc=host \
            --cap-add=SYS_PTRACE \
            --security-opt seccomp=unconfined \
            --ulimit memlock=-1 \
            --ulimit stack=67108864 \
            "${REPO_MOUNT_ARGS[@]}" \
            -v "${container_home_host}":/home/"$(id -un)" \
            "${SSH_ARGS[@]}" \
            -e PIP_USER=0 \
            -w "${WORKSPACE_DIR}" \
            --entrypoint sleep \
            "${DEV_IMAGE}" infinity
        print_success "容器已创建并在后台运行"

        print_step "运行 setup.sh 初始化容器环境..."
        docker cp "${repo_root}/common/setup.sh" "${CONTAINER_NAME}:/tmp/setup.sh"
        docker exec --user "$(id -un)" "${CONTAINER_NAME}" zsh /tmp/setup.sh
        docker exec "${CONTAINER_NAME}" rm /tmp/setup.sh
        print_success "setup.sh 执行完毕"

    elif ! container_running; then
        print_info "容器已存在但已停止，重新启动..."
        docker start "${CONTAINER_NAME}" > /dev/null
        print_success "容器已启动"
    else
        print_info "发现已在运行的容器: ${CONTAINER_NAME}"
    fi
}

# ── Main entry point ──────────────────────────────────────────────
lib_main() {
    local script_dir="$1"; shift
    local repo_root="$1"; shift

    _parse_args "$@"

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
    # Use username (not uid:gid) so Docker resolves supplementary groups from
    # /etc/group inside the container.  This is required for Ascend NPU access:
    # the driver checks membership of group 'HwHiAiUser' which is a supplementary
    # group — uid:gid mode only sets the primary group and skips supplementary ones.
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
