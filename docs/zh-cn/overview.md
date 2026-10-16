# 概览

## 1. 这个仓库是什么

FlagGemsTerminalDevContainer 是一组启动脚本,为
[FlagGems](https://github.com/FlagOpen/FlagGems) 贡献者按硬件平台拉起终端
开发容器：NVIDIA、Hygon、Cambricon、Ascend（4 个变体）、Metax、Iluvatar、
摩尔线程、昆仑芯、平头哥。每个平台的容器形态是一致的——zsh + oh-my-zsh、
Neovim（LazyVim）、Claude Code CLI、Codex CLI,以及一个预装好 FlagGems 的
Python 环境——差异只体现在各自需要接入哪些设备文件、内核驱动和工具链。

本仓库在运行时并不直接调用 `docker build` 构建自己的镜像图。`Dockerfile`
只是作为参考文档记录了各个层,实际构建是在一个运行中的容器里重放等价的
步骤完成的（原因见[架构](architecture.md)）。

## 2. 目录结构

```
FlagGemsTerminalDevContainer/
├── Dockerfile            # 层列表参考（ARG PLATFORM 分支）；运行时不会被直接 docker build
├── common/
│   ├── lib.sh            # 共享 shell 逻辑：参数解析、镜像构建、容器运行
│   └── setup.sh          # 容器创建后运行一次：oh-my-zsh、Neovim/LazyVim
├── nvidia/
│   ├── start.sh                    # NVIDIA 启动脚本 —— source common/lib.sh
│   └── install-nsight-compute.sh   # 容器启动后安装 Nsight Compute（ncu）
├── hygon/start.sh         # Hygon 启动脚本
├── cambricon/start.sh     # Cambricon 启动脚本
├── ascend/start.sh        # Ascend（910B）启动脚本
├── ascend-910c/start.sh   # Ascend 910C 启动脚本 —— 平台逻辑相同，910C 专用 base 镜像
├── ascend-vllm/start.sh   # 基于上游 vllm-ascend 镜像的 Ascend 启动脚本
├── ascend-vllm-910c/start.sh  # vllm-ascend 镜像，Atlas A3（16 卡）变体
├── metax/start.sh         # Metax 启动脚本
├── iluvatar/start.sh      # Iluvatar 启动脚本
├── mthreads/start.sh      # 摩尔线程启动脚本
├── kunlunxin/start.sh     # 昆仑芯启动脚本
└── thead/start.sh         # 平头哥启动脚本
```

每个 `<platform>/start.sh` 的结构都是一样的：

1. 设置 `PLATFORM`,通常还有 `TOOLKIT_VERSION`。
2. 定义 `platform_hardware_args`（必须），以及按需定义
   `platform_user_groups`、`platform_build_args`、`platform_post_build_exec`
   （可选钩子——见[架构](architecture.md)）。
3. `source common/lib.sh`。
4. 调用 `lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"`——或者对于需要在容器启动后
   额外挂载/执行一步操作的平台,是围绕它的一层薄封装。

## 3. 心智模型：一个容器是怎么"诞生"的

运行 `./nvidia/start.sh`（或任意其他启动脚本）会依次做这些事：

1. **解析参数**（`_parse_args`）—— `-n`、`-f`、`--rebuild`、`--repo`、
   `--base-tag` 等 flag（完整列表见[使用说明](usage.md)）。
2. **按需构建 dev 镜像**（`_build_dev`）—— 从 FlagOS base 镜像启动一个
   临时容器,通过 `docker exec` 在其中重放 Dockerfile 里的各层,执行平台
   定义的 `platform_post_build_exec` 钩子（如果有）,最后 `docker commit`
   成 `flaggems-<platform>:dev`。如果镜像已存在且没有传
   `--rebuild`/`--rebuild-dev`,这一步会被跳过。
3. **创建或复用容器**（`_run_container`）—— 如果同名容器还不存在,就带着
   平台的硬件 flag `docker run -d` 一个,挂载仓库和容器 home 目录,然后在
   容器内运行一次 `common/setup.sh` 安装 zsh/Neovim 插件集。如果容器存在
   但已停止,就 `docker start` 它。如果已经在运行,直接复用。
4. **exec 进入容器**—— 用 `docker exec -it` 执行请求的命令（默认 `zsh`）。

后续每次运行,第 2、3 步都是空操作（镜像和容器都已存在），所以重新启动很
快——直接进入 shell。

## 4. 接下来看什么

- 如果想理解构建流程*为什么*是这样设计的、六个构建层各自做了什么,或者
  一个新平台可以定义哪些钩子,看[架构](architecture.md)。
- 如果想横向对比每个现有启动脚本实际往 `platform_hardware_args` 等函数里
  填了什么,看[平台参考](platforms.md)。
- 如果要专门处理 4 个 Ascend 启动脚本中的任意一个,看[Ascend 专题](ascend.md)——
  它们承载了全仓库中最复杂的平台专属逻辑。
- 日常使用的参数、代理/SSH 配置、容器管理命令,看[使用说明](usage.md)。
- 如果要新增一个硬件平台,看[贡献指南](contribution.md)。
