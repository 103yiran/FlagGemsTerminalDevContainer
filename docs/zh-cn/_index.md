# FlagGemsTerminalDevContainer 文档

本目录面向需要理解本仓库如何构建、启动 FlagGems 开发容器的贡献者,而不只是
如何运行 `start.sh`。如果只想快速上手,请参考根目录的
[README_cn.md](../../README_cn.md);这里的内容会深入讲解整体架构、各平台之间
的差异,以及如何给仓库新增一个硬件后端。

[English](../en/_index.md)

## 目录

- [概览](overview.md) —— 本仓库是什么、目录结构,以及容器是如何"诞生"的
  （`_build_dev` / `_run_container` 的心智模型）。
- [架构](architecture.md) —— `common/lib.sh` 的构建流水线（run→exec→commit、
  六个镜像层）、`platform_*` 钩子约定,以及 `common/setup.sh` 的
  zsh/Neovim 初始化流程及其网络兜底链路。
- [平台参考](platforms.md) —— 按后端逐一列出：base 镜像、设备文件、用户组、
  额外挂载,以及 14 个启动脚本各自使用的钩子。
- [Ascend 专题](ascend.md) —— 深入讲解 4 个 Ascend 变体（`ascend`、
  `ascend-910c`、`ascend-vllm`、`ascend-vllm-910c`）：driver 烘焙、
  `HwHiAiUser` 权限模型、仅 root 可用 NPU 的限制,以及 cannbot 插件安装。
- [使用说明](usage.md) —— `start.sh` 的参数、环境变量覆盖、
  网络/代理/SSH 配置,以及容器管理命令。
- [贡献指南](contribution.md) —— 如何新增一个硬件平台（最小化启动脚本 vs.
  需要额外挂载/用户组/钩子的情形）,以及现有启动脚本遵循的约定。
