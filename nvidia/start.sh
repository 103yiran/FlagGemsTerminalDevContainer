#!/usr/bin/env bash
# start.sh — ensure the NVIDIA runtime image exists, then build the dev
#             image on top of it and launch a detached container, then
#             attach to it via docker exec.
#
# Step 1: build (or skip) flaggems-nvidia:runtime from
#         build-infra (https://gitcode.com/flagos-ai/build-infra.git)
#         legacy/flaggems-nvidia-13.3  (--target runtime)
# Step 2: build (or skip) flaggems-nvidia:dev from nvidia/Dockerfile
# Step 3: start container with -itd (detached), then exec into it
#
# SSH key forwarding (applied at container creation, pick one):
#   ~/.ssh dir mount  — default; keys available as files (read-only)
#   SSH agent forward — private key never leaves the host; requires
#                       ssh-agent running with keys loaded on the host
#
# Usage:
#   ./nvidia/start.sh                         # default container name, mounts FlagGems
#   ./nvidia/start.sh -n my_container         # custom container name
#   ./nvidia/start.sh -f                      # force-recreate container
#   ./nvidia/start.sh --rebuild-runtime       # force-rebuild runtime image
#   ./nvidia/start.sh --rebuild-dev           # force-rebuild dev image
#   ./nvidia/start.sh --rebuild               # force-rebuild both images
#   ./nvidia/start.sh --ssh-agent             # use SSH agent forwarding instead
#   ./nvidia/start.sh -c "python a.py"        # exec command (default: zsh)
#   ./nvidia/start.sh --repo ../FlagTree      # mount FlagTree instead of FlagGems
#   ./nvidia/start.sh --repo ../A --repo ../B # mount multiple repos

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

readonly RUNTIME_IMAGE="flaggems-nvidia:runtime"
readonly DEV_IMAGE="flaggems-nvidia:dev"
CONTAINER_NAME="flaggems-nvidia-dev-$(id -un)"

FORCE_RECREATE=false
FORCE_REBUILD_RUNTIME=false
FORCE_REBUILD_DEV=false
EXEC_COMMAND=(zsh)
SSH_MODE="agent"   # "mount" | "agent"
REPO_MOUNTS=()     # entries: "host_abs_path:container_path"; default: FlagGems

readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m' CYAN='\033[0;36m' NC='\033[0m'

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

show_help() {
    cat << 'EOF'
用法: start.sh [选项] [container_name]

选项:
    -h, --help              显示帮助信息
    -n, --name NAME         指定容器名称 (默认: flaggems-nvidia-dev-<username>)
    -f, --force             强制重建容器
        --rebuild-runtime   强制重新构建 runtime 镜像
        --rebuild-dev       强制重新构建 dev 镜像
        --rebuild           强制重新构建 runtime + dev 两个镜像
        --ssh-agent         使用 SSH agent 转发（默认: 挂载 ~/.ssh）
    -c, --cmd COMMAND       exec 进容器时执行的命令（默认: zsh）
        --repo PATH         挂载仓库到 /workspace/<name>，可重复使用
                            （默认: ../FlagGems → /workspace/FlagGems）

SSH 说明:
    默认将宿主机 ~/.ssh 以只读方式挂载到容器内，密钥作为文件存在。
    --ssh-agent 模式下私钥不进入容器，仅转发 SSH_AUTH_SOCK socket，
    需要宿主机已运行 ssh-agent 并通过 ssh-add 加载密钥。

示例:
    start.sh                                # 默认容器名，挂载 FlagGems
    start.sh --repo ../FlagTree             # 挂载 FlagTree 替代 FlagGems
    start.sh --repo ../FlagTree \
             --repo ../FlagGems             # 同时挂载多个仓库
    start.sh my_dev                         # 自定义容器名
    start.sh -f                             # 强制删除并重建容器
    start.sh --rebuild                      # 重新构建 runtime 和 dev 镜像
    start.sh --rebuild-dev                  # 仅重新构建 dev 镜像（runtime 不变）
    start.sh --ssh-agent                    # 使用 SSH agent 转发
    start.sh -c "python train.py"           # exec 执行特定命令
EOF
    exit 0
}

image_exists()     { docker image inspect "$1" > /dev/null 2>&1; }
container_exists() { docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; }
container_running(){ docker ps    --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; }

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)         show_help ;;
        -f|--force)        FORCE_RECREATE=true;        shift ;;
        --rebuild-runtime) FORCE_REBUILD_RUNTIME=true; shift ;;
        --rebuild-dev)     FORCE_REBUILD_DEV=true;     shift ;;
        --rebuild)         FORCE_REBUILD_RUNTIME=true; FORCE_REBUILD_DEV=true; shift ;;
        --ssh-agent)       SSH_MODE="agent";           shift ;;
        --repo)
            _rhost="$(cd "$2" && pwd)"
            REPO_MOUNTS+=("${_rhost}:/workspace/$(basename "${_rhost}")")
            shift 2 ;;
        -c|--cmd)          EXEC_COMMAND=($2);          shift 2 ;;
        -n|--name)         CONTAINER_NAME="$2";        shift 2 ;;
        -*)                print_error "未知选项: $1"; show_help ;;
        *)
            if [[ "$CONTAINER_NAME" == "flaggems-nvidia-dev-$(id -un)" ]]; then
                CONTAINER_NAME="$1"
            else
                print_error "多余的参数: $1"; show_help
            fi
            shift ;;
    esac
done

# Default workspace repo when none specified via --repo
if [[ ${#REPO_MOUNTS[@]} -eq 0 ]]; then
    REPO_MOUNTS+=("${FLAGGEMS_ROOT}:/workspace/FlagGems")
fi

# Build -v args and derive container workdir from the first repo
REPO_MOUNT_ARGS=()
for _pair in "${REPO_MOUNTS[@]}"; do
    REPO_MOUNT_ARGS+=(-v "$_pair")
done
WORKSPACE_DIR="${REPO_MOUNTS[0]#*:}"   # container path of the first repo

# ── Step 1: runtime image ────────────────────────────────────────
# Dockerfile comes from the build-infra submodule.
readonly BUILD_INFRA_DIR="${REPO_ROOT}/build-infra"

if $FORCE_REBUILD_RUNTIME || ! image_exists "$RUNTIME_IMAGE"; then
    $FORCE_REBUILD_RUNTIME \
        && print_step "强制重新构建 runtime 镜像: $RUNTIME_IMAGE" \
        || print_step "runtime 镜像不存在，开始构建: $RUNTIME_IMAGE"
    docker build \
        --target runtime \
        -t "$RUNTIME_IMAGE" \
        -f "${BUILD_INFRA_DIR}/legacy/flaggems-nvidia-13.3" \
        "$FLAGGEMS_ROOT"
    print_success "runtime 镜像构建完成: $RUNTIME_IMAGE"
    # runtime 重建意味着 dev 镜像和容器都需要重建
    FORCE_REBUILD_DEV=true
    FORCE_RECREATE=true
else
    print_info "runtime 镜像已存在，跳过: $RUNTIME_IMAGE"
fi

# ── Step 2: ensure ssh-agent is running with keys loaded ─────────
# The agent socket is forwarded into the container so setup.sh can
# run git clone over SSH (LazyVim, oh-my-zsh, zsh plugins).
ensure_ssh_agent() {
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

ensure_ssh_agent

# ── Step 3: dev image ─────────────────────────────────────────────
if $FORCE_REBUILD_DEV || ! image_exists "$DEV_IMAGE"; then
    $FORCE_REBUILD_DEV \
        && print_step "强制重新构建 dev 镜像: $DEV_IMAGE" \
        || print_step "dev 镜像不存在，开始构建: $DEV_IMAGE"
    docker build \
        --build-arg RUNTIME_IMAGE="$RUNTIME_IMAGE" \
        --build-arg USERNAME="$(id -un)" \
        --build-arg USER_UID="$(id -u)" \
        --build-arg USER_GID="$(id -g)" \
        -t "$DEV_IMAGE" \
        -f "$SCRIPT_DIR/Dockerfile" \
        "$SCRIPT_DIR"
    print_success "dev 镜像构建完成: $DEV_IMAGE"
    # 镜像重建后必须重建容器，否则容器继续使用旧镜像
    FORCE_RECREATE=true
else
    print_info "dev 镜像已存在，跳过: $DEV_IMAGE"
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}容器信息:${NC}"
echo -e "${CYAN}  名称:         ${CONTAINER_NAME}${NC}"
echo -e "${CYAN}  镜像:         ${DEV_IMAGE}${NC}"
echo -e "${CYAN}  runtime 基础: ${RUNTIME_IMAGE}${NC}"
for _pair in "${REPO_MOUNTS[@]}"; do
    echo -e "${CYAN}  挂载:         ${_pair}${NC}"
done
echo -e "${CYAN}  工作目录:     ${WORKSPACE_DIR}${NC}"
echo -e "${CYAN}  SSH 模式:     ${SSH_MODE}${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# ── Step 4: force-recreate ────────────────────────────────────────
if $FORCE_RECREATE && container_exists; then
    print_warn "强制重建：删除已有容器 ${CONTAINER_NAME}"
    container_running && docker stop "${CONTAINER_NAME}" > /dev/null
    docker rm "${CONTAINER_NAME}" > /dev/null
    print_info "已删除旧容器"
fi

# ── Step 5: build SSH mount/agent args ───────────────────────────
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

# ── Step 6: create or start (detached) ───────────────────────────
# Container home dir lives at $HOME/<container_name> on the host.
# This covers ~/.claude automatically, no named volume needed.
CONTAINER_HOME_HOST="$HOME/${CONTAINER_NAME}"
if [[ ! -d "$CONTAINER_HOME_HOST" ]]; then
    print_step "创建容器 home 目录: ${CONTAINER_HOME_HOST}"
    mkdir -p "$CONTAINER_HOME_HOST"
fi

if ! container_exists; then
    print_step "创建并后台启动容器: ${CONTAINER_NAME}"
    docker run -d \
        --name "${CONTAINER_NAME}" \
        \
        `# NVIDIA GPU` \
        --gpus all \
        \
        `# network / IPC` \
        --net=host \
        --ipc=host \
        \
        `# security` \
        --cap-add=SYS_PTRACE \
        --security-opt seccomp=unconfined \
        \
        `# ulimits` \
        --ulimit memlock=-1 \
        --ulimit stack=67108864 \
        --ulimit nofile=1048576:1048576 \
        \
        `# mounts` \
        "${REPO_MOUNT_ARGS[@]}" \
        -v "${CONTAINER_HOME_HOST}":/home/"$(id -un)" \
        "${SSH_ARGS[@]}" \
        \
        `# env` \
        -e PIP_USER=0 \
        \
        `# workdir` \
        -w "${WORKSPACE_DIR}" \
        \
        --entrypoint sleep \
        "${DEV_IMAGE}" infinity
    print_success "容器已创建并在后台运行"

    # ── Run setup.sh inside the new container ─────────────────────
    print_step "运行 setup.sh 初始化容器环境..."
    docker cp "${SCRIPT_DIR}/setup.sh" "${CONTAINER_NAME}:/tmp/setup.sh"
    docker exec "${CONTAINER_NAME}" zsh /tmp/setup.sh
    docker exec "${CONTAINER_NAME}" rm /tmp/setup.sh
    print_success "setup.sh 执行完毕"

elif ! container_running; then
    print_info "容器已存在但已停止，重新启动..."
    docker start "${CONTAINER_NAME}" > /dev/null
    print_success "容器已启动"
else
    print_info "发现已在运行的容器: ${CONTAINER_NAME}"
fi

# ── Step 7: exec into the running container ───────────────────────
print_step "进入容器: ${CONTAINER_NAME} — exec: ${EXEC_COMMAND[*]}"
docker exec -it "${CONTAINER_NAME}" "${EXEC_COMMAND[@]}"

echo ""
print_step "已退出容器（容器仍在后台运行）"
echo ""
echo -e "${CYAN}常用管理命令:${NC}"
echo "  查看状态: docker ps -a | grep ${CONTAINER_NAME}"
echo "  再次进入: docker exec -it ${CONTAINER_NAME} zsh"
echo "  停止容器: docker stop ${CONTAINER_NAME}"
echo "  删除容器: docker rm ${CONTAINER_NAME}"
echo ""
