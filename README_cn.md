# FlagGemsTerminalDevContainer

[English](README.md)

更深入的架构说明、各平台差异,以及如何新增一个平台,见
[docs/zh-cn](docs/zh-cn/_index.md)。

为 [FlagGems](https://github.com/FlagOpen/FlagGems) 开发者提供的终端容器环境,支持 NVIDIA、Hygon、Cambricon、Ascend、Metax、Iluvatar、摩尔线程（Moore Threads）、昆仑芯（Kunlunxin）、平头哥（T-Head）九种硬件平台。容器内预装 zsh、Neovim（LazyVim）、Claude Code 及完整的代码质量工具链。

## 目录结构

```
FlagGemsTerminalDevContainer/
├── Dockerfile            # 统一 dev 镜像（NVIDIA + Hygon + Cambricon + Ascend + Metax + Iluvatar + 摩尔线程 + 平头哥，通过 ARG PLATFORM 区分）
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
│   └── start.sh          # Ascend（910B）启动脚本，source common/lib.sh
├── ascend-910c/
│   └── start.sh          # Ascend 910C 启动脚本，平台逻辑相同，base 镜像为 910C 专用版本
├── ascend-vllm/
│   └── start.sh          # Ascend 启动脚本，基于上游 vllm-ascend 镜像，平台逻辑相同
├── ascend-vllm-910c/
│   └── start.sh          # Ascend 启动脚本，基于上游 vllm-ascend 镜像的 Atlas A3（-a3）版本，平台逻辑相同，设备范围扩到 16 卡
├── metax/
│   └── start.sh          # Metax 启动脚本，source common/lib.sh
├── iluvatar/
│   └── start.sh          # Iluvatar 启动脚本，source common/lib.sh
├── mthreads/
│   └── start.sh          # 摩尔线程启动脚本，source common/lib.sh
├── kunlunxin/
│   └── start.sh          # 昆仑芯启动脚本，source common/lib.sh
└── thead/
    └── start.sh          # 平头哥启动脚本，source common/lib.sh
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

- **需要能访问 GitHub/GitCode**，用于安装编辑器和 shell 插件（LazyVim /
  lazy.nvim 及其依赖默认通过 HTTPS 克隆，优先走 `gitcode.com` 镜像，失败后
  回退到 `github.com`）。
  - 若宿主机可直连 GitHub/GitCode，无需额外配置。
  - 若宿主机只有 HTTP(S) 代理（例如在 `~/.bashrc` 中 export 了
    `http_proxy`/`https_proxy`），同样够用 —— `start.sh` 会自动将这些
    环境变量转发进容器。
  - 宿主机配置 SSH 密钥并将公钥添加到 [GitCode](https://gitcode.com/)
    是可选的额外兜底，仅在两次 HTTPS 尝试都失败时才会用到。如需依赖它，
    可先验证: `ssh -T git@gitcode.com`
  - 以上途径都不通时，插件安装会被跳过，容器内只有一个裸 nvim 和普通 zsh。

- NVIDIA 平台：宿主机已安装 NVIDIA Container Toolkit
- Hygon 平台：宿主机已挂载 `/dev/kfd`、`/dev/dri` 等设备，`/opt/hyhal` 已就位
- Cambricon 平台：宿主机已挂载 `/dev/cambricon_dev*` 及 `/dev/cambricon_ctl` 设备
- Ascend 平台（`ascend/`、`ascend-910c/`、`ascend-vllm/`、`ascend-vllm-910c/` 均适用）：宿主机已挂载 `/dev/davinci0`、`/dev/davinci_manager`、`/dev/devmm_svm`、`/dev/hisi_hdc` 设备（`ascend-vllm-910c/` 对应 Atlas A3 节点，预期最多 16 张卡，`/dev/davinci0`–`/dev/davinci15`），且 `/usr/local/Ascend/driver`、`/usr/local/dcmi`、`/usr/local/sbin/npu-smi` 已就位
- Metax 平台：宿主机已挂载 `/dev/mxcd` 和 `/dev/dri` 设备，用户需在 `video` 组中
- Iluvatar 平台：宿主机已挂载 `/dev/iluvatar0` 至 `/dev/iluvatar15` 设备，且 `/usr/local/corex` 已就位
- 摩尔线程（Moore Threads）平台：宿主机已挂载 `/dev/mtgpu.0` 至 `/dev/mtgpu.7` 及 `/dev/dri` 设备，`/usr/bin/mthreads-gmi` 已就位，用户需在 `render` 和 `video` 组中
- 昆仑芯（Kunlunxin）平台：宿主机已挂载 `/dev/xpu0` 至 `/dev/xpu7` 及 `/dev/xpuctrl` 设备
- 平头哥（T-Head）平台：宿主机已挂载 `/dev/alixpu`、`/dev/alixpu_ctl` 及 `/dev/alixpu_ppu0` 至 `/dev/alixpu_ppu7` 设备

## 快速开始

```bash
git clone https://github.com/your-org/FlagGemsTerminalDevContainer.git
```

### 启动容器（NVIDIA）

```bash
./nvidia/start.sh
```

`start.sh` 会在容器启动后自动安装 NVIDIA Nsight Compute（`ncu`），已安装则自动跳过。指定或升级版本：

```bash
NSIGHT_COMPUTE_VERSION=2026.4.0 ./nvidia/start.sh
```

详见 `nvidia/install-nsight-compute.sh`（包含 apt 源中还没有的版本时，回退到 `.run` 安装器的逻辑）。

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

### 启动容器（Ascend 910C）

```bash
./ascend-910c/start.sh
```

平台配置（设备挂载、驱动烘焙、CANN 环境变量注入）与 `ascend/start.sh` 完全一致，
区别仅在于使用 910C 专用的 base 镜像（`flagos-base-ascend-cann9.0.0-910c`），
而非 `ascend/start.sh` 使用的 `flagos-runtime-ascend-cann9.0.0`。dev 镜像和
容器名也各自独立（`flaggems-ascend-910c:dev`、
`flaggems-ascend-910c-dev-<用户名>`），不会与普通 Ascend 容器冲突。

### 启动容器（Ascend，vllm-ascend base 镜像）

```bash
./ascend-vllm/start.sh
```

平台配置（设备挂载、驱动烘焙、HwHiAiUser 用户组、CANN 环境变量注入）与
`ascend/start.sh` 完全一致，区别在于 base 镜像换成了上游
[vllm-ascend](https://github.com/vllm-project/vllm-ascend) 社区镜像
（`m.daocloud.io/quay.io/ascend/vllm-ascend:v0.26.0rc1`），而不是 FlagOS 的
`flagos-runtime`/`flagos-base` 系列。该镜像已经把 vLLM、torch_npu、
vllm-ascend 装进系统 Python（没有 `/flagos` venv），默认以 root 运行，也没有
`HwHiAiUser` 组——本脚本在它上面补上了与 `ascend-910c/start.sh` 相同的非 root
NPU 访问配置。dev 镜像和容器名也各自独立
（`flaggems-vllm-ascend:dev`、`flaggems-vllm-ascend-dev-<用户名>`），不会与
其他 Ascend 容器冲突。默认挂载的是兄弟目录 `../FlagGems-vllm`（容器内路径
仍是 `/workspace/FlagGems`），而非普通的 FlagGems——用 `--repo` 可挂载其他仓库。
可通过 `BASE_IMAGE_TAG` 覆盖固定其他 vllm-ascend 版本。

### 启动容器（Ascend，vllm-ascend base 镜像，Atlas A3）

```bash
./ascend-vllm-910c/start.sh
```

与上面的 `ascend-vllm/start.sh` 完全一致（同一套 base 镜像体系、同一套非 root
NPU 访问配置、同样默认挂载 `../FlagGems-vllm`），区别仅在于固定使用
`v0.26.0rc1-a3` 这个 tag——即 vllm-ascend 自己的
[Dockerfile.a3](https://github.com/vllm-project/vllm-ascend/blob/v0.26.0rc1/Dockerfile.a3)
构建产物，面向 Atlas A3（910_93）硬件而非 910B。另一处差异是设备范围：本脚本
挂载 `/dev/davinci0` 到 `/dev/davinci15`（16 张卡），匹配典型的 Atlas A3
节点规格，而不是其他三个 Ascend 启动脚本使用的 8 卡范围
（`/dev/davinci0`–`/dev/davinci7`）。dev 镜像和容器名也各自独立
（`flaggems-vllm-ascend-910c:dev`、`flaggems-vllm-ascend-910c-dev-<用户名>`），
不会与其他 Ascend 容器冲突。

### Ascend cannbot 插件

四个 Ascend 启动脚本（`ascend`、`ascend-910c`、`ascend-vllm`、
`ascend-vllm-910c`）在构建 dev 镜像时，会在 `common/lib.sh` 已安装的
Claude Code 和 Codex CLI 基础上，额外安装一组
[cannbot](https://www.npmjs.com/package/@cannbot-plugin/cannbot) 插件。这个
过程是自动完成的，不需要额外参数，执行的命令是：

```bash
npx -y @cannbot-plugin/cannbot@latest install <plugin> --tool claude
npx -y @cannbot-plugin/cannbot@latest install <plugin> --tool codex
```

针对以下每个 plugin 都会执行一次：

- `triton-op-generator`
- `hccl-op-generator`
- `model-infer-optimize`
- `ops-registry-invoke`
- `ops-direct-invoke`

这些插件为 `claude` 和 `codex` 提供了 Ascend 专属的上下文，用于生成
Triton/HCCL 算子，以及在模型推理场景中注册/调用算子。单个 plugin 安装失败
（例如 npm registry 偶发抓取失败）只会打印警告，不会导致整个镜像构建失败——
如果某个 plugin 没装上，重新执行一次 `start.sh` 即可重试。

### 启动容器（Metax）

```bash
./metax/start.sh
```

### 启动容器（Iluvatar）

```bash
./iluvatar/start.sh
```

### 启动容器（摩尔线程 / Moore Threads）

```bash
./mthreads/start.sh
```

### 启动容器（昆仑芯 / Kunlunxin）

```bash
./kunlunxin/start.sh
```

### 启动容器（平头哥 / T-Head）

```bash
./thead/start.sh
```

首次运行时，脚本会依次：

1. 用本目录的 `Dockerfile` 从 Harbor 拉取 FlagOS base 镜像，构建 `flaggems-{platform}:dev`
2. 创建容器，将仓库挂载到 `/workspace/` 下
3. 在容器内运行 `setup.sh`，安装 oh-my-zsh、zsh 插件和 LazyVim
4. 执行 `docker exec -it` 进入 zsh

后续再次运行时，镜像和容器已存在则直接进入，无需重复构建。

## start.sh 参数

各平台的 `start.sh` 用法一致：

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
| 代码质量 | `pre-commit`、`flake8`、`black`、`isort`、`clang-format`（仅 NVIDIA 和平头哥） |
| AI 工具 | Claude Code CLI（`claude` 命令）、Codex CLI（`codex` 命令） |
| 其他 | `ripgrep`、`fd`、`gh`（GitHub CLI）、`sudo`（无密码） |
| 性能分析 | NVIDIA Nsight Compute（`ncu`），仅 NVIDIA —— 由 `nvidia/start.sh` 安装，详见 `nvidia/install-nsight-compute.sh` |

FlagGems 源码默认挂载到 `/workspace/FlagGems`。容器的 `$HOME` 目录映射到宿主机的 `~/<容器名>/`，`.claude` 配置、zsh 历史等均持久化保存。

## 网络配置

`setup.sh` 需要出网访问来克隆 LazyVim、lazy.nvim 及插件集。默认通过 HTTPS
克隆 —— 优先 [GitCode](https://gitcode.com/) 镜像，失败后回退到
`github.com` 直连 —— 因此只要能直连互联网，或者有 HTTP(S) 代理即可，
**不要求配置 SSH 密钥**。

**宿主机在代理后面（无法直连 GitHub/GitCode）：** 在运行 `start.sh` 之前
export `http_proxy`/`https_proxy`（例如写入 `~/.bashrc`）。`common/lib.sh`
会自动检测并将其转发进镜像构建过程和运行中的容器，无需其他配置。

**可选的 SSH 兜底：** 如果两次 HTTPS 尝试（GitCode 镜像和 GitHub 直连）都
失败，`setup.sh` 会尝试 SSH 作为最后手段，前提是宿主机已配置 SSH 密钥且
公钥已添加到 GitCode 账号。可用以下命令验证：

```bash
ssh -T git@gitcode.com
```
## 已知限制（Ascend）

在共享的 Ascend 宿主机上，容器内的 NPU 通常**只有 root 能用**。跑任务时加 `-u root`：

```bash
docker exec -u root -w /workspace/FlagGems flaggems-ascend-dev-$(id -un) \
    bash -lc 'pytest tests/test_abs.py -vs'
```

以普通用户身份运行时，`/dev/davinci*` 打开失败并返回 `EBUSY`（errno 16，Device or resource busy），`npu-smi info` 会报 `dcmi model initialized failed ... ret is -8020`。如果是在 PyTorch 里失败，通常表现为 `aclInit` 错误码 `507899` / `Resource_Busy(EL0005)`。

**这不是文件权限问题。** `start.sh` 已经按设备节点的 GID 创建了 `HwHiAiUser` 组并把用户加进去。可以自行确认组这一侧是对的：

```bash
docker exec -u $(id -un) <容器名> id          # 应包含 groups=...,1000(HwHiAiUser)
docker exec -u root <容器名> stat -c '%n %u:%g %a' /dev/davinci0   # 应为 1000:1000 660
```

`EBUSY` 说明内核已经放行了这次 open，是驱动随后主动拒绝的。Ascend 驱动按命名空间独占显卡，同一时刻一张卡只认一个 ns（宿主机 `dmesg` 里的 `uda_occupy_dev_by_ns`，日志为 `Conflict open udevid`）。当某张卡被别的 ns 持有时，驱动只放行**同时满足"真 root"和"持有完整 capability"**的进程——所以把用户加进 `HwHiAiUser` 没有用，给非 root 用户补 capability 也没有用。

对日常使用的影响：

- 凡是要碰 NPU 的操作，用 `docker exec -u root`。纯 CPU 的工作（改代码、跑 lint、CPU 上的 `pytest`）不受影响。
- **不要**为了让非 root 可用而去掉 `ascend/start.sh` 里的 `--privileged`。特权模式恰恰是 root 能绕过 ns 检查的原因，去掉之后 root 也会失去 NPU 访问。
- 非 root 可用的前提是分给你的卡没有被其他 ns 占用。这需要全机统一约定——所有容器都改用 `--runtime=ascend -e ASCEND_VISIBLE_DEVICES=<卡号>` 启动，而不是 `--privileged` 加一串 `--device`——因此无法只靠本仓库解决。
- 清理陈旧的 ns 占用需要重载 Ascend 内核模块或重启宿主机，会影响机器上所有容器，请与宿主机管理员协调。

## SSH 配置

该兜底支持两种转发方式：

- **默认模式（挂载 `~/.ssh`）**：宿主机的 `~/.ssh` 以只读方式挂载进容器，密钥作为文件存在。
- **Agent 模式（`--ssh-agent`）**：私钥不进入容器，只转发 `SSH_AUTH_SOCK`，需要宿主机已运行 `ssh-agent` 并通过 `ssh-add` 加载密钥。

如果 HTTPS、代理、SSH 都不通，`setup.sh` 会跳过 nvim/zsh 插件安装并打印警告，其余环境正常可用。

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
