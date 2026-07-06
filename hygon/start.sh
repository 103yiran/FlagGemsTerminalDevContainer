#!/usr/bin/env bash
# start.sh — ensure the Hygon runtime image exists, then build the dev
#             image on top of it and launch an interactive container.
#
# Step 1: build (or skip) flaggems-hygon:runtime from
#         container/flaggems-hygon-26.04  (--target runtime)
# Step 2: build (or skip) flaggems-hygon:dev from dev/hygon/Dockerfile
#
# Usage:
#   ./dev/hygon/start.sh                    # default container name
#   ./dev/hygon/start.sh -n my_container    # custom container name
#   ./dev/hygon/start.sh -f                 # force-recreate container
#   ./dev/hygon/start.sh --rebuild-runtime  # force-rebuild runtime image
#   ./dev/hygon/start.sh --rebuild-dev      # force-rebuild dev image
#   ./dev/hygon/start.sh --rebuild          # force-rebuild both images
#   ./dev/hygon/start.sh -c "python a.py"   # custom entry command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RUNTIME_IMAGE="flaggems-hygon:runtime"
DEV_IMAGE="flaggems-hygon:dev"
CONTAINER_NAME="flaggems-hygon-dev-$(id -un)"

FORCE_RECREATE=false
FORCE_REBUILD_RUNTIME=false
FORCE_REBUILD_DEV=false
CUSTOM_COMMAND="zsh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

show_help() {
    cat << EOF
用法: $0 [选项] [container_name]

选项:
    -h, --help              显示帮助信息
    -n, --name NAME         指定容器名称 (默认: flaggems-hygon-dev-<username>)
    -f, --force             强制重建容器
        --rebuild-runtime   强制重新构建 runtime 镜像
        --rebuild-dev       强制重新构建 dev 镜像
        --rebuild           强制重新构建 runtime + dev 两个镜像
    -c, --cmd COMMAND       容器内执行的命令（默认: zsh）

示例:
    $0                              # 默认容器名，按需自动构建
    $0 my_dev                       # 自定义容器名
    $0 -f                           # 强制删除并重建容器
    $0 --rebuild                    # 重新构建 runtime 和 dev 镜像
    $0 --rebuild-dev                # 仅重新构建 dev 镜像（runtime 不变）
    $0 -c "python train.py"         # 执行特定命令
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
        -c|--cmd)          CUSTOM_COMMAND="$2";        shift 2 ;;
        -n|--name)         CONTAINER_NAME="$2";        shift 2 ;;
        -*)                print_error "未知选项: $1"; show_help ;;
        *)
            if [[ "$CONTAINER_NAME" == "flaggems-hygon-dev-$(id -un)" ]]; then
                CONTAINER_NAME="$1"
            else
                print_error "多余的参数: $1"; show_help
            fi
            shift ;;
    esac
done

# ── Step 1: runtime image ─────────────────────────────────────────
if $FORCE_REBUILD_RUNTIME || ! image_exists "$RUNTIME_IMAGE"; then
    $FORCE_REBUILD_RUNTIME \
        && print_step "强制重新构建 runtime 镜像: $RUNTIME_IMAGE" \
        || print_step "runtime 镜像不存在，开始构建: $RUNTIME_IMAGE"
    docker build \
        --target runtime \
        -t "$RUNTIME_IMAGE" \
        -f "$REPO_ROOT/container/flaggems-hygon-26.04" \
        "$REPO_ROOT"
    print_success "runtime 镜像构建完成: $RUNTIME_IMAGE"
else
    print_info "runtime 镜像已存在，跳过: $RUNTIME_IMAGE"
fi

# ── Step 2: ensure ssh-agent is running with keys loaded ─────────
ensure_ssh_agent() {
    # 如果 agent 未运行，启动一个并导出环境变量
    if [[ -z "${SSH_AUTH_SOCK:-}" ]] || ! ssh-add -l &>/dev/null; then
        print_step "启动 ssh-agent 并加载密钥..."
        eval "$(ssh-agent -s)" > /dev/null

        # 找宿主机上所有标准私钥并尝试添加
        local added=0
        for key in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ecdsa"; do
            if [[ -f "$key" ]]; then
                if ssh-add "$key" 2>/dev/null; then
                    print_success "已加载密钥: $key"
                    added=$((added + 1))
                fi
            fi
        done

        if [[ $added -eq 0 ]]; then
            print_warn "未找到可用的 SSH 私钥（~/.ssh/id_ed25519 / id_rsa / id_ecdsa）"
            print_warn "请先运行: ssh-keygen -t ed25519 -C \"your_email\""
            print_warn "并将公钥添加到 GitHub: cat ~/.ssh/id_ed25519.pub"
        fi
    else
        print_info "ssh-agent 已运行，已加载密钥: $(ssh-add -l | wc -l) 个"
    fi
}

# ── Step 3: ensure docker buildx is available ─────────────────────
ensure_buildx() {
    if docker buildx version &>/dev/null; then
        print_info "docker buildx 已就绪: $(docker buildx version 2>&1 | head -1)"
        return 0
    fi
    print_step "docker buildx 未找到，下载用户级插件到 ~/.docker/cli-plugins/ ..."
    local plugin_dir="$HOME/.docker/cli-plugins"
    mkdir -p "$plugin_dir"
    # 获取最新版本号
    local version
    version=$(curl -fsSL https://api.github.com/repos/docker/buildx/releases/latest \
              | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
    if [[ -z "$version" ]]; then
        print_error "无法获取 buildx 版本信息，请检查网络或手动安装："
        print_error "  https://docs.docker.com/go/buildx/"
        exit 1
    fi
    local arch
    arch=$(uname -m); [[ "$arch" == "x86_64" ]] && arch="amd64"
    local url="https://github.com/docker/buildx/releases/download/v${version}/buildx-v${version}.linux-${arch}"
    print_info "下载 buildx v${version} (${arch})..."
    if curl -fsSL "$url" -o "$plugin_dir/docker-buildx" \
       && chmod +x "$plugin_dir/docker-buildx"; then
        print_success "buildx 安装完成: $plugin_dir/docker-buildx"
    else
        print_error "下载失败，请手动安装 buildx："
        print_error "  https://docs.docker.com/go/buildx/"
        exit 1
    fi
}

ensure_ssh_agent
ensure_buildx

# ── Step 4: dev image ─────────────────────────────────────────────
if $FORCE_REBUILD_DEV || ! image_exists "$DEV_IMAGE"; then
    $FORCE_REBUILD_DEV \
        && print_step "强制重新构建 dev 镜像: $DEV_IMAGE" \
        || print_step "dev 镜像不存在，开始构建: $DEV_IMAGE"
    docker buildx build \
        --ssh default \
        --load \
        --build-arg RUNTIME_IMAGE="$RUNTIME_IMAGE" \
        --build-arg USERNAME="$(id -un)" \
        --build-arg USER_UID="$(id -u)" \
        --build-arg USER_GID="$(id -g)" \
        -t "$DEV_IMAGE" \
        -f "$SCRIPT_DIR/Dockerfile" \
        "$SCRIPT_DIR"
    print_success "dev 镜像构建完成: $DEV_IMAGE"
else
    print_info "dev 镜像已存在，跳过: $DEV_IMAGE"
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}容器信息:${NC}"
echo -e "${CYAN}  名称:         ${CONTAINER_NAME}${NC}"
echo -e "${CYAN}  镜像:         ${DEV_IMAGE}${NC}"
echo -e "${CYAN}  runtime 基础: ${RUNTIME_IMAGE}${NC}"
echo -e "${CYAN}  仓库:         ${REPO_ROOT}${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# ── Step 4: force-recreate ────────────────────────────────────────
if $FORCE_RECREATE && container_exists; then
    print_warn "强制重建：删除已有容器 ${CONTAINER_NAME}"
    container_running && docker stop "${CONTAINER_NAME}" > /dev/null
    docker rm "${CONTAINER_NAME}" > /dev/null
    print_info "已删除旧容器"
fi

# ── Step 5: create or enter ───────────────────────────────────────
if container_exists; then
    print_info "发现已有容器: ${CONTAINER_NAME}"
    if container_running; then
        print_info "容器正在运行，直接进入..."
        docker exec -it "${CONTAINER_NAME}" ${CUSTOM_COMMAND}
    else
        print_info "容器已停止，重新启动并进入..."
        docker start -ai "${CONTAINER_NAME}"
    fi
else
    print_step "创建新容器: ${CONTAINER_NAME}"
    docker run -it \
        --name "${CONTAINER_NAME}" \
        \
        `# HYGON devices` \
        --device=/dev/kfd \
        --device=/dev/mkfd \
        --device=/dev/dri \
        --group-add video \
        \
        `# network / IPC` \
        --net=host \
        --ipc=host \
        --privileged \
        \
        `# security` \
        --cap-add=SYS_PTRACE \
        --security-opt seccomp=unconfined \
        \
        `# ulimits` \
        --ulimit memlock=-1 \
        --ulimit stack=67108864 \
        \
        `# mounts` \
        -v "${REPO_ROOT}":/workspace/FlagGems \
        -v /opt/hyhal:/opt/hyhal \
        -v "$HOME":/home/host \
        -v claude-code-data:/home/"$(id -un)"/.claude \
        \
        `# env` \
        -e PIP_USER=0 \
        \
        `# workdir` \
        -w /workspace/FlagGems \
        \
        "${DEV_IMAGE}" \
        ${CUSTOM_COMMAND}
fi

echo ""
print_step "操作完成"
echo ""
echo -e "${CYAN}常用管理命令:${NC}"
echo "  查看状态: docker ps -a | grep ${CONTAINER_NAME}"
echo "  停止容器: docker stop ${CONTAINER_NAME}"
echo "  进入容器: docker exec -it ${CONTAINER_NAME} zsh"
echo "  删除容器: docker rm ${CONTAINER_NAME}"
echo ""
