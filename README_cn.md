# FlagGemsTerminalDevContainer

[English](README.md)

为 [FlagGems](https://github.com/FlagOpen/FlagGems) 开发者提供的终端容器环境,支持 NVIDIA、Hygon、Cambricon、Ascend、Metax 五种硬件平台。容器内预装 zsh、Neovim（LazyVim）、Claude Code 及完整的代码质量工具链。

## 目录结构

```
FlagGemsTerminalDevContainer/
├── Dockerfile            # 统一 dev 镜像（NVIDIA + Hygon + Cambricon + Ascend + Metax，通过 ARG PLATFORM 区分）
├── common/
│   ├── lib.sh            # 公共 shell 逻辑（参数解析、镜像构建、容器启动）
│   └── setup.sh          # 容器首次启动时运行，安装 zsh/nvim 插件
├── nvidia/
│   └── start.sh          # NVIDIA 启动脚本，source common/lib.sh
├── hygon/
│   └── start.sh          # Hygon 启动脚本，source common/lib.sh
├── cambricon/
│   └── start.sh          # Cambricon 启动脚本，source common/lib.sh
├── ascend/
│   └── start.sh          # Ascend 启动脚本，source common/lib.sh
└── metax/
    └── start.sh          # Metax 启动脚本，source common/lib.sh
```

## 前置条件

- Docker（已安装并可访问）
- FlagGems 源码仓库，与本仓库同级：

  ```
  parent/
  ├── FlagGems/                    # FlagGems 源码
  └── FlagGemsTerminalDevContainer/  # 本仓库
  ```

  其他仓库（如 `FlagTree`）可通过 `--repo` 参数在运行时挂载。

- NVIDIA 平台：宿主机已安装 NVIDIA Container Toolkit
- Hygon 平台：宿主机已挂载 `/dev/kfd`、`/dev/dri` 等设备，`/opt/hyhal` 已就位
- Cambricon 平台：宿主机已挂载 `/dev/cambricon_dev*` 及 `/dev/cambricon_ctl` 设备
- Ascend 平台：宿主机已挂载 `/dev/davinci0`、`/dev/davinci_manager`、`/dev/devmm_svm`、`/dev/hisi_hdc` 设备，且 `/usr/local/Ascend/driver`、`/usr/local/dcmi`、`/usr/local/sbin/npu-smi` 已就位
- Metax 平台：宿主机已挂载 `/dev/mxcd` 和 `/dev/dri` 设备，用户需在 `video` 组中

## 快速开始

```bash
git clone https://github.com/your-org/FlagGemsTerminalDevContainer.git
```

### 启动容器（NVIDIA）

```bash
./nvidia/start.sh
```

### 启动容器（Hygon）

```bash
./hygon/start.sh
```

### 启动容器（Cambricon）

```bash
./cambricon/start.sh
```

### 启动容器（Ascend）

```bash
./ascend/start.sh
```

### 启动容器（Metax）

```bash
./metax/start.sh
```

首次运行时，脚本会依次：

1. 用本目录的 `Dockerfile` 从 Harbor 拉取 FlagOS base 镜像，构建 `flaggems-{platform}:dev`
2. 创建容器，将仓库挂载到 `/workspace/` 下
3. 在容器内运行 `setup.sh`，安装 oh-my-zsh、zsh 插件和 LazyVim
4. 执行 `docker exec -it` 进入 zsh

后续再次运行时，镜像和容器已存在则直接进入，无需重复构建。

## start.sh 参数

三个平台的 `start.sh` 用法一致：

| 参数 | 说明 |
|------|------|
| `-n NAME` / `--name NAME` | 指定容器名称（默认：`flaggems-{platform}-dev-<用户名>`） |
| `-f` / `--force` | 强制删除并重建容器 |
| `--rebuild-dev` / `--rebuild` | 强制重新构建 dev 镜像 |
| `--repo PATH` | 挂载仓库到 `/workspace/<name>`，可重复使用（默认：`../FlagGems`） |
| `-c CMD` / `--cmd CMD` | 进入容器时执行的命令（默认：`zsh`） |
| `--ssh-agent` | 使用 SSH agent 转发（默认挂载 `~/.ssh`） |
| `--base-tag VERSION` | 指定 FlagOS base 镜像版本（默认：`2.1.2`） |

容器的工作目录为第一个 `--repo` 对应的容器路径（默认为 `/workspace/FlagGems`）。

示例：

```bash
# 重新构建 dev 镜像并进入容器
./nvidia/start.sh --rebuild

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
| Python | `/flagos` 虚拟环境，已安装 FlagGems 及依赖（由 base 镜像提供） |
| 代码质量 | `pre-commit`、`flake8`、`black`、`isort`、`clang-format`（仅 NVIDIA） |
| AI 工具 | Claude Code CLI（`claude` 命令） |
| 其他 | `ripgrep`、`fd`、`gh`（GitHub CLI）、`sudo`（无密码） |

FlagGems 源码默认挂载到 `/workspace/FlagGems`。容器的 `$HOME` 目录映射到宿主机的 `~/<容器名>/`，`.claude` 配置、zsh 历史等均持久化保存。

## SSH 配置

`setup.sh` 需要通过 SSH 访问 GitHub 来克隆 LazyVim 和 zsh 插件。

- **默认模式（挂载 `~/.ssh`）**：宿主机的 `~/.ssh` 以只读方式挂载进容器，密钥作为文件存在。
- **Agent 模式（`--ssh-agent`）**：私钥不进入容器，只转发 `SSH_AUTH_SOCK`，需要宿主机已运行 `ssh-agent` 并通过 `ssh-add` 加载密钥。

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
