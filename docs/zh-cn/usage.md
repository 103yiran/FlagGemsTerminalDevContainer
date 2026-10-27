# 使用说明

## 1. `start.sh` 参数

所有启动脚本共享同一套参数,由 `common/lib.sh` 的 `_parse_args` 解析：

| Flag | 说明 |
|------|------|
| `-h` / `--help` | 显示帮助信息,包括当前平台的默认容器名和 base 镜像。 |
| `-n NAME` / `--name NAME` | 容器名称（默认：`flaggems-<platform>-dev-<用户名>`）。 |
| `-f` / `--force` | 删除并重建容器（不会影响镜像）。 |
| `--rebuild-dev` / `--rebuild` | 强制重新构建 dev 镜像（两者等价）。 |
| `--repo PATH` | 挂载一个仓库到 `/workspace/<basename>`。可重复使用；工作目录会设为*第一个* `--repo` 路径。默认：`../FlagGems`（`ascend-vllm`/`ascend-vllm-910c`/`hygon-vllm`/`nvidia-vllm` 默认是 `../FlagGems-vllm`）。 |
| `-c CMD` / `--cmd CMD` | `docker exec` 进容器时执行的命令（默认：`zsh`）。会按空格分词,多词命令要加引号：`-c "python train.py"`。 |
| `--ssh-agent` | 使用 SSH agent 转发,而不是挂载 `~/.ssh` 进容器。 |
| `--base-tag VERSION` | 覆盖 FlagOS base 镜像的 tag。 |
| （位置参数）`container_name` | 等价于 `-n`/`--name`,以裸位置参数的形式给出——仅当没有同时传 `-n` 时才有效。 |

```bash
# 重新构建 dev 镜像并进入容器
./nvidia/start.sh --rebuild

# 挂载 FlagTree 替代 FlagGems
./nvidia/start.sh --repo ../FlagTree

# 同时挂载多个仓库（工作目录 = 第一个仓库）
./nvidia/start.sh --repo ../FlagTree --repo ../FlagGems

# exec 执行特定命令,而不是进入 zsh
./nvidia/start.sh -c "python train.py"

# 使用自定义容器名（共享机器上很有用）
./nvidia/start.sh -n my_flaggems_dev
```

## 2. 环境变量覆盖

除了 flag,还有几个启动脚本级别的变量可以在调用 `start.sh` 之前
export 或内联设置：

| 变量 | 适用平台 | 作用 |
|------|---------|------|
| `BASE_IMAGE_TAG` | 全部 | 与 `--base-tag` 相同,改为用环境变量设置。 |
| `TOOLKIT_VERSION` | 除 `ascend-vllm*`/`hygon-vllm`/`nvidia-vllm`/`thead` 之外的全部 | 覆盖默认 `flagos-runtime-<platform>-<toolkit>` 镜像名里的工具链版本。 |
| `BASE_IMAGE_NAME` / `BASE_IMAGE_REGISTRY` | `nvidia`、`nvidia-vllm`、`thead`、`ascend-910c`、`ascend-vllm`、`ascend-vllm-910c`、`hygon-vllm` | 对于 base 镜像不遵循 `flagos-runtime-<platform>-<toolkit>` 命名的平台,完全覆盖镜像引用。 |
| `NSIGHT_COMPUTE_VERSION` | `nvidia`、`nvidia-vllm` | 固定/升级容器启动后安装的 Nsight Compute apt 包版本——见 `nvidia/install-nsight-compute.sh`。 |
| `DEV_IMAGE` / `CONTAINER_NAME` | 全部 | 直接覆盖计算出的默认值,用于 `-n`/`--name` 表达不了的命名需求（少见）。 |

```bash
# 固定某个具体的 Nsight Compute 版本
NSIGHT_COMPUTE_VERSION=2026.4.0 ./nvidia/start.sh

# 使用不同的 vllm-ascend 发布 tag
BASE_IMAGE_TAG=v0.27.0rc1 ./ascend-vllm/start.sh

# 使用不同的 DCU vllm 镜像 tag
BASE_IMAGE_TAG=0.22.0-ubuntu22.04-dtk2604-py3.10 ./hygon-vllm/start.sh
```

## 3. 启动各个平台

```bash
./nvidia/start.sh
./hygon/start.sh
./cambricon/start.sh
./ascend/start.sh
./ascend-910c/start.sh
./ascend-vllm/start.sh
./ascend-vllm-910c/start.sh
./hygon-vllm/start.sh
./nvidia-vllm/start.sh
./metax/start.sh
./iluvatar/start.sh
./mthreads/start.sh
./kunlunxin/start.sh
./thead/start.sh
```

某个平台第一次运行时,脚本会：

1. 从 FlagOS base 镜像构建 `flaggems-<platform>:dev`（层列表见
   [架构 §2](architecture.md#2-六个构建层)）。
2. 创建一个后台容器,把仓库挂载到 `/workspace/` 下。
3. 在容器内运行 `common/setup.sh`,安装 oh-my-zsh、zsh 插件和 LazyVim。
4. 通过 `docker exec -it` 进入交互式 zsh 会话。

之后每次运行,已存在的镜像和容器会被直接复用——不会重新构建,也不会
重新跑 `setup.sh`。

## 4. 容器内环境

| 内容 | 说明 |
|------|------|
| Shell | zsh + oh-my-zsh,启用 `zsh-autosuggestions`、`zsh-syntax-highlighting` |
| 编辑器 | Neovim ≥ 0.11（LazyVim,首次启动时自动同步插件） |
| Python | `/flagos` 虚拟环境,已安装 FlagGems 及依赖（由 base 镜像提供） |
| 代码质量 | `pre-commit`、`flake8`、`black`、`isort`、`clang-format`（仅 NVIDIA 和平头哥） |
| AI 工具 | Claude Code CLI（`claude`）、Codex CLI（`codex`）、CodeBuddy Code CLI（`codebuddy`）；Ascend 额外安装了[cannbot 插件](ascend.md#5-cannbot-插件) |
| 其他 | `ripgrep`、`fd`、`gh`（GitHub CLI）、`sudo`（无密码） |
| 性能分析 | NVIDIA Nsight Compute（`ncu`），仅 NVIDIA |

FlagGems 源码树默认挂载在 `/workspace/FlagGems`。容器的 `$HOME` 映射到
宿主机的 `~/<容器名>/`,所以 `.claude` 配置、zsh 历史记录等用户数据会在
容器重启、`docker rm`/重新启动之间持久保留（只要那个 home 目录本身没被
删除）。

## 5. 网络、代理、SSH 配置

`common/setup.sh` 需要出网权限来 clone LazyVim、lazy.nvim 和插件集。
默认走 HTTPS——先走 [GitCode](https://gitcode.com/) 镜像,失败再直连
`github.com`——所以普通的互联网访问或者 HTTP(S) 代理就够用,不需要 SSH
key。

**宿主机在代理后面（不能直连 GitHub/GitCode）**：在运行 `start.sh` 之前
export `http_proxy`/`https_proxy`（比如写进 `~/.bashrc`）。
`common/lib.sh` 会检测到它们（`_collect_proxy_args`）,并自动把它们转发
进镜像构建过程和运行中的容器——不需要其他配置。

**可选的 SSH 兜底**：如果 GitCode 镜像和 GitHub 直连的 HTTPS 都失败,
`setup.sh` 会把 SSH 作为最后的兜底,前提是宿主机有一个公钥已经添加到
GitCode 账号的密钥。可以这样验证：

```bash
ssh -T git@gitcode.com
```

**SSH 转发模式**（作为兜底,两种都可行）：

- **默认（挂载 `~/.ssh`）**—— 宿主机的 `~/.ssh` 目录以只读方式挂载进
  容器。
- **Agent 转发（`--ssh-agent`）**—— 私钥永远不会进入容器,只转发
  `SSH_AUTH_SOCK`。需要宿主机已经运行 `ssh-agent` 并通过 `ssh-add`
  加载了密钥。

如果 HTTPS、代理、SSH 都走不通,`setup.sh` 会跳过 nvim/zsh 插件安装并打印
警告——其余环境仍然正常可用。

## 6. 容器管理

```bash
# 列出容器
docker ps -a | grep flaggems

# 重新进入运行中的容器
docker exec -it flaggems-nvidia-dev-$(id -un) zsh

# 停止容器
docker stop flaggems-nvidia-dev-$(id -un)

# 删除容器（镜像会保留）
docker rm flaggems-nvidia-dev-$(id -un)
```

删除容器不会删除 dev 镜像或宿主机侧的 home 目录
（`~/<容器名>/`）——重新运行 `start.sh` 会基于已有镜像重新创建容器,并
重新挂载同一个 home 目录,不会重新执行 Neovim/zsh 插件安装。
