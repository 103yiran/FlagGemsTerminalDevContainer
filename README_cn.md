# FlagGemsTerminalDevContainer

[English](README.md)

为 [FlagGems](https://github.com/FlagOpen/FlagGems) 开发者提供的终端容器环境，支持 NVIDIA、Hygon、Cambricon、Ascend、Metax、Iluvatar、摩尔线程（Moore Threads）、昆仑芯（Kunlunxin）、平头哥（T-Head）九种硬件平台。容器内预装 zsh、Neovim（LazyVim）、Claude Code 及完整的代码质量工具链。

本 README 只覆盖快速上手。仓库结构、各平台前置条件、`start.sh` 参数/环境变量、容器内环境、网络与 SSH 配置、Ascend 已知限制，以及如何新增平台，详见
**[docs/zh-cn](docs/zh-cn/_index.md)**。

## 前置条件

- Docker（已安装并可访问）。
- FlagGems 源码仓库，与本仓库同级（其他仓库如 `FlagTree` 可通过 `--repo` 参数在运行时挂载）：

  ```
  parent/
  ├── FlagGems/                      # FlagGems 源码
  └── FlagGemsTerminalDevContainer/  # 本仓库
  ```

- 需要能访问 GitHub/GitCode（直连或通过 HTTP(S) 代理），用于首次启动时安装编辑器/shell 插件。回退链路及代理/SSH 配置详见
  [docs/zh-cn/usage.md 第 5 节](docs/zh-cn/usage.md#5-网络代理ssh-配置) ——不要求配置 SSH 密钥。
- 各平台在宿主机上需要的设备文件、内核模块与用户组，完整的平台参考见
  [docs/zh-cn/platforms.md 第 1–2 节](docs/zh-cn/platforms.md)。

## 快速开始

```bash
git clone https://github.com/your-org/FlagGemsTerminalDevContainer.git

./nvidia/start.sh      # NVIDIA
./hygon/start.sh        # Hygon
./cambricon/start.sh    # Cambricon
./ascend/start.sh       # Ascend（910B）
./ascend-910c/start.sh  # Ascend 910C
./ascend-vllm/start.sh      # Ascend，vllm-ascend base 镜像
./ascend-vllm-910c/start.sh # Ascend，vllm-ascend base 镜像，Atlas A3
./dcu-vllm/start.sh     # 海光 DCU，vllm base 镜像
./metax/start.sh        # Metax
./iluvatar/start.sh     # Iluvatar
./mthreads/start.sh     # 摩尔线程（Moore Threads）
./kunlunxin/start.sh    # 昆仑芯（Kunlunxin）
./thead/start.sh        # 平头哥（T-Head）
```

首次运行时，脚本会构建 dev 镜像、创建容器并把仓库挂载到 `/workspace/` 下、在容器内安装 oh-my-zsh/LazyVim，然后进入 zsh。后续再次运行会直接复用已有的镜像和容器。完整的 `start.sh` 参数/环境变量说明和示例见
[docs/zh-cn/usage.md](docs/zh-cn/usage.md)，四个 Ascend 启动脚本的专属细节（驱动烘焙、root-only NPU 访问限制、CANN 环境注入、cannbot 插件）见
[docs/zh-cn/ascend.md](docs/zh-cn/ascend.md)。

## 延伸阅读

- [docs/zh-cn/overview.md](docs/zh-cn/overview.md) —— 本仓库是什么，容器是如何被创建出来的。
- [docs/zh-cn/architecture.md](docs/zh-cn/architecture.md) —— 构建流程与 `platform_*` 钩子约定。
- [docs/zh-cn/platforms.md](docs/zh-cn/platforms.md) —— 各平台前置条件、base 镜像与硬件访问配置。
- [docs/zh-cn/ascend.md](docs/zh-cn/ascend.md) —— 四个 Ascend 启动脚本的深入说明。
- [docs/zh-cn/usage.md](docs/zh-cn/usage.md) —— 参数、环境变量、容器内环境、网络/SSH、容器管理。
- [docs/zh-cn/contribution.md](docs/zh-cn/contribution.md) —— 如何新增一个硬件平台。
