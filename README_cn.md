# FlagGemsTerminalDevContainer

[English](README.md)

为 [FlagGems](https://github.com/FlagOpen/FlagGems) 开发者提供的终端容器环境，支持 NVIDIA 和 Hygon 两种硬件平台。容器内预装 zsh、Neovim（LazyVim）、Claude Code 及完整的代码质量工具链。

## 目录结构

```
FlagGemsTerminalDevContainer/
├── Dockerfile            # 统一 dev 镜像（NVIDIA + Hygon，通过 ARG PLATFORM 区分）
├── build-infra/          # submodule: runtime 镜像 Dockerfile 来源
│   └── legacy/
│       ├── flaggems-nvidia-13.3   # NVIDIA CUDA 13.3 runtime Dockerfile
│       └── flaggems-hygon-26.04   # Hygon DTK 26.04 runtime Dockerfile
├── common/
│   ├── lib.sh            # 公共 shell 逻辑（参数解析、镜像构建、容器启动）
│   └── setup.sh          # 容器首次启动时运行，安装 zsh/nvim 插件
├── nvidia/
│   └── start.sh          # NVIDIA 启动脚本，source common/lib.sh
└── hygon/
    └── start.sh          # Hygon 启动脚本，source common/lib.sh
```

## 前置条件

- Docker（已安装并可访问）
- FlagGems 源码仓库，与本仓库同级（用于构建 runtime 镜像）：

  ```
  parent/
  ├── FlagGems/                    # FlagGems 源码（runtime 镜像 build context）
  └── FlagGemsTerminalDevContainer/  # 本仓库
  ```

  其他仓库（如 `FlagTree`）可通过 `--repo` 参数在运行时挂载，无需遵循特定目录结构。

- NVIDIA 平台：宿主机已安装 NVIDIA Container Toolkit
- Hygon 平台：宿主机已挂载 `/dev/kfd`、`/dev/dri` 等设备，`/opt/hyhal` 已就位

## 快速开始

### 克隆仓库

```bash
git clone --recurse-submodules https://github.com/your-org/FlagGemsTerminalDevContainer.git
```

如果已经克隆但未初始化 submodule：

```bash
git submodule update --init
```

### 启动容器（NVIDIA）

```bash
./nvidia/start.sh
```

### 启动容器（Hygon）

```bash
./hygon/start.sh
```

首次运行时，脚本会依次：

1. 用 `build-infra/legacy/flaggems-{platform}` 构建 `flaggems-{platform}:runtime` 镜像（以 `../FlagGems` 为 build context）
2. 用本目录的 `Dockerfile` 构建 `flaggems-{platform}:dev` 镜像
3. 创建容器，将仓库挂载到 `/workspace/` 下
4. 在容器内运行 `setup.sh`，安装 oh-my-zsh、zsh 插件和 LazyVim
5. 执行 `docker exec -it` 进入 zsh

后续再次运行时，镜像和容器已存在则直接进入，无需重复构建。

## start.sh 参数

两个平台的 `start.sh` 用法基本一致：

| 参数 | 说明 |
|------|------|
| `-n NAME` / `--name NAME` | 指定容器名称（默认：`flaggems-{platform}-dev-<用户名>`） |
| `-f` / `--force` | 强制删除并重建容器 |
| `--rebuild-runtime` | 强制重新构建 runtime 镜像 |
| `--rebuild-dev` | 强制重新构建 dev 镜像 |
| `--rebuild` | 强制重新构建 runtime + dev 两个镜像 |
| `--repo PATH` | 挂载仓库到 `/workspace/<name>`，可重复使用（默认：`../FlagGems`） |
| `-c CMD` / `--cmd CMD` | 进入容器时执行的命令（默认：`zsh`） |
| `--ssh-agent` | 使用 SSH agent 转发（仅 NVIDIA；默认挂载 `~/.ssh`） |

容器的工作目录为第一个 `--repo` 对应的容器路径（默认为 `/workspace/FlagGems`）。

示例：

```bash
# 重新构建所有镜像并进入容器
./nvidia/start.sh --rebuild

# 仅重建 dev 镜像（runtime 不变，速度更快）
./nvidia/start.sh --rebuild-dev

# 挂载 FlagTree 替代 FlagGems
./nvidia/start.sh --repo ../FlagTree

# 同时挂载多个仓库（工作目录为第一个）
./nvidia/start.sh --repo ../FlagTree --repo ../FlagGems

# 以特定命令进入容器（不启动 zsh）
./nvidia/start.sh -c "python train.py"

# 自定义容器名，方便多人共用同一台机器
./nvidia/start.sh -n my_flaggems_dev
```

## 容器内环境

| 内容 | 说明 |
|------|------|
| Shell | zsh + oh-my-zsh，启用 `zsh-autosuggestions`、`zsh-syntax-highlighting` |
| 编辑器 | Neovim ≥ 0.11（LazyVim，首次启动时自动同步插件） |
| Python | `/flagos` 虚拟环境，已安装 FlagGems 及依赖（由 runtime 镜像提供） |
| 代码质量 | `pre-commit`、`flake8`、`black`、`isort`、`clang-format`（NVIDIA 镜像） |
| AI 工具 | Claude Code CLI（`claude` 命令） |
| 其他 | `ripgrep`、`fd`、`gh`（GitHub CLI）、`sudo`（无密码） |

默认将 FlagGems 源码挂载到 `/workspace/FlagGems`。通过 `--repo` 可将任意仓库挂载到 `/workspace/<name>`，宿主机修改实时可见。

容器的 `$HOME` 目录映射到宿主机的 `~/<容器名>/`，`.claude` 配置、zsh 历史等均持久化保存。

## SSH 配置

`setup.sh` 需要通过 SSH 访问 GitHub 来克隆 LazyVim 和 zsh 插件。

- **默认模式（挂载 `~/.ssh`）**：宿主机的 `~/.ssh` 以只读方式挂载进容器，密钥作为文件存在。
- **Agent 模式（`--ssh-agent`，仅 NVIDIA）**：私钥不进入容器，只转发 `SSH_AUTH_SOCK`，需要宿主机已运行 `ssh-agent` 并通过 `ssh-add` 加载密钥。

如果没有 SSH 密钥，`setup.sh` 会跳过 nvim/zsh 插件安装并打印警告，其余环境正常可用。

## 常用容器管理命令

```bash
# 查看容器状态
docker ps -a | grep flaggems

# 再次进入已运行的容器
docker exec -it flaggems-nvidia-dev-$(id -un) zsh

# 停止容器
docker stop flaggems-nvidia-dev-$(id -un)

# 删除容器（镜像保留）
docker rm flaggems-nvidia-dev-$(id -un)
```

## 镜像构建说明

runtime 镜像的 Dockerfile 由 [build-infra](https://gitcode.com/flagos-ai/build-infra.git) submodule 提供（`legacy/` 目录下），以 FlagGems 源码目录为 build context 进行构建，产出包含 `/flagos` 虚拟环境的 runtime 镜像。

dev 镜像（根目录 `Dockerfile`）跨平台共用，通过 `--build-arg PLATFORM=nvidia|hygon` 区分平台特定内容。镜像在 runtime 基础上叠加：开发工具（zsh、nvim、gh 等）、非 root 用户（uid/gid 与宿主机一致）、Claude Code CLI，以及对 `/flagos` venv 的写权限修正。NVIDIA 平台额外安装 `python3-pip`、`clang-format` 和 pre-commit 工具链（`pre-commit`、`flake8`、`black`、`isort`）。
