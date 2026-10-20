# 平台参考

这里横向列出全部 14 个启动脚本的差异。各钩子具体做了什么见
[架构](architecture.md),4 个 Ascend 变体的深入讲解见
[Ascend 专题](ascend.md)。

## 1. Base 镜像与身份标识

| 启动脚本 | `PLATFORM` | Base 镜像 | 工具链版本 | Dev 镜像 / 默认容器名 |
|----------|-----------|------------|-----------|------------------------|
| `nvidia/start.sh` | `nvidia` | `harbor.baai.ac.cn/flagos-app/vllm0.24.0-generic-13.3:2.2.0-0.3.0` | `cuda13.3` | `flaggems-nvidia:dev` / `flaggems-nvidia-dev-<用户名>` |
| `hygon/start.sh` | `hygon` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-hygon-dtk26.04:2.1.2` | `dtk26.04` | `flaggems-hygon:dev` / `flaggems-hygon-dev-<用户名>` |
| `dcu-vllm/start.sh` | `hygon` | `harbor.sourcefind.cn:5443/hcu/admin/base/vllm:0.21.0-ubuntu22.04-dtk2604-py3.10` | 无（上游镜像） | `flaggems-vllm-dcu:dev` / `flaggems-vllm-dcu-dev-<用户名>` |
| `cambricon/start.sh` | `cambricon` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-cambricon-neuware4.7.2:2.1.2` | `neuware4.7.2` | `flaggems-cambricon:dev` / `flaggems-cambricon-dev-<用户名>` |
| `ascend/start.sh` | `ascend` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-ascend-cann9.0.0:2.2.0` | `cann9.0.0` | `flaggems-ascend:dev` / `flaggems-ascend-dev-<用户名>` |
| `ascend-910c/start.sh` | `ascend` | `harbor.baai.ac.cn/flagos-base/flagos-base-ascend-cann9.0.0-910c:2.2.0` | `cann9.0.0` | `flaggems-ascend-910c:dev` / `flaggems-ascend-910c-dev-<用户名>` |
| `ascend-vllm/start.sh` | `ascend` | `m.daocloud.io/quay.io/ascend/vllm-ascend:v0.30.0rc1` | 无（上游镜像） | `flaggems-vllm-ascend:dev` / `flaggems-vllm-ascend-dev-<用户名>` |
| `ascend-vllm-910c/start.sh` | `ascend` | `m.daocloud.io/quay.io/ascend/vllm-ascend:v0.30.0rc1-a3` | 无（上游镜像，`Dockerfile.a3`） | `flaggems-vllm-ascend-910c:dev` / `flaggems-vllm-ascend-910c-dev-<用户名>` |
| `metax/start.sh` | `metax` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-metax-maca3.8.1.3:2.1.2` | `maca3.8.1.3` | `flaggems-metax:dev` / `flaggems-metax-dev-<用户名>` |
| `iluvatar/start.sh` | `iluvatar` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-iluvatar-corex4.5.0:2.1.2` | `corex4.5.0` | `flaggems-iluvatar:dev` / `flaggems-iluvatar-dev-<用户名>` |
| `mthreads/start.sh` | `mthreads` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-mthreads-musa5.2.0:2.1.2` | `musa5.2.0` | `flaggems-mthreads:dev` / `flaggems-mthreads-dev-<用户名>` |
| `kunlunxin/start.sh` | `kunlunxin` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-kunlunxin-xre5.37.1:2.2.0` | `xre5.37.1` | `flaggems-kunlunxin:dev` / `flaggems-kunlunxin-dev-<用户名>` |
| `thead/start.sh` | `thead` | `pkg.flytiger-eco.com/docker_release/pytorch:v2.1.1-2.10.0-ubuntu24.04-cuda13.0-py312` | 无（普通 PyTorch 镜像） | `flaggems-thead:dev` / `flaggems-thead-dev-<用户名>` |

注意：4 个 Ascend 启动脚本内部都设置的是 `PLATFORM="ascend"`（这样它们
都能复用 Dockerfile 里 apt 包和用户组创建的分支逻辑,以及
`common/lib.sh` 默认的 flagos-runtime 命名逻辑）——它们之间的区别完全
靠各自覆盖 `BASE_IMAGE_NAME`/`BASE_IMAGE_TAG`,以及不同的
`DEV_IMAGE`/`CONTAINER_NAME`,而不是修改 `PLATFORM` 本身。
`dcu-vllm/start.sh` 采用同样的套路,内部设置 `PLATFORM="hygon"`,指向
上游海光 DCU vllm 镜像。

## 2. 硬件访问：设备、用户组、挂载、钩子

| 启动脚本 | 设备文件（`platform_hardware_args`） | 额外 `docker run` flag | 用户组（`platform_user_groups`） | 额外宿主机挂载 | 构建期钩子 |
|----------|----------------------------------------|---------------------------|-------------------------------------|----------------|-------------|
| `nvidia` | 无（`--gpus all` 负责设备暴露） | `--gpus all`、`--ulimit nofile=1048576:1048576` | — | — | 无（有一个容器*启动后*的钩子：`install-nsight-compute.sh`） |
| `hygon` | `/dev/kfd`、`/dev/mkfd`、`/dev/dri` | `--group-add video`、`--group-add 39`、`--privileged` | — | `/opt/hyhal` | — |
| `dcu-vllm` | 与 `hygon` 相同 | 与 `hygon` 相同 | — | `/opt/hyhal` | — |
| `cambricon` | `/dev/cambricon_dev0`–`7`、`/dev/cambricon_ctl` | — | — | — | — |
| `ascend`（及其他 3 个 Ascend 变体） | `/dev/davinci0`–`7`（`-910c` 系列：`0`–`15`）、`/dev/davinci_manager`、`/dev/devmm_svm`、`/dev/hisi_hdc` | `--privileged`、`--pid=host`、`--security-opt label=disable` | `HwHiAiUser` | `/usr/local/dcmi`、`/usr/local/sbin/npu-smi` | `platform_build_args`（只读挂载宿主机 driver）+ `platform_post_build_exec`（把 driver/dcmi 烘焙进镜像,安装 cannbot 插件）——见[Ascend 专题](ascend.md) |
| `metax` | `/dev/mxcd`、`/dev/dri` | `--group-add=video` | — | — | — |
| `iluvatar` | `/dev/itrctl`、`/dev/iluvatar0`–`15` | — | — | `/usr/local/corex`（只读） | — |
| `mthreads` | `/dev/mtgpu.0`–`7`、`/dev/dri` | `--group-add render`、`--group-add video` | `render`（GID 固定为与宿主机一致） | `/usr/bin/mthreads-gmi`（只读） | — |
| `kunlunxin` | `/dev/xpu0`–`7`、`/dev/xpuctrl` | — | — | — | — |
| `thead` | `/dev/alixpu`、`/dev/alixpu_ctl`、`/dev/alixpu_ppu0`–`7` | `--privileged`、`--init`、`--shm-size=8g` | — | — | — |

几个值得关注的点：

- **Ascend 的设备/用户组配置是全仓库最复杂的**——除了表格里的内容,它
  还会修复设备文件权限、处理 `HwHiAiUser` 与 base 镜像自带 `ubuntu` 组之间
  的 GID 冲突,并为 CANN 配置 sudo/shell rc 的环境变量注入。完整内容见
  [Ascend 专题](ascend.md)。
- **`mthreads` 是唯一一个非 Ascend 平台用到 `platform_user_groups`
  的**。它的 base 镜像默认没有 `render` 组,如果不先创建这个组（GID 对齐
  宿主机,这样才能真正映射到实际的设备 owner）,`--group-add render` 在
  `docker run` 时会直接失败。
- **三个平台用到了 `--privileged`**（`hygon`、`ascend`/其变体、
  `thead`），原因各不相同——Hygon 和平头哥是沿用各自参考 `docker run`
  命令里的笼统设备授权方式,而 Ascend 依赖它特指让 root 绕过驱动的
  namespace 归属检查（为什么这很关键、为什么不能移除,见
  [Ascend 专题](ascend.md#3-为什么-npu-访问通常只能用-root) ）。

## 3. 构建期按平台差异化的包

只有 `nvidia` 和 `thead` 在构建第 3 层里额外安装了
`python3-pip clang-format openssh-client`（apt）,以及通过
`/usr/bin/pip3 --break-system-packages` 安装的
`pre-commit==3.7.1 flake8==7.1.0 black==23.7.0 isort==5.12.0`。其他平台的
`python3-pip` 相关需求预期由 FlagOS base 镜像自带的 `/flagos` 虚拟环境
满足。

## 4. 直接调用 `lib_main` vs. 封装 `lib_main`

大多数启动脚本最后都是单纯调用一次
`lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"`。有 5 个会封装它（或者
`_run_container`）,因为它们需要在钩子约定没有直接覆盖的某个时间点做事：

- **`hygon`、`dcu-vllm`、`iluvatar`、`mthreads`** —— 各自定义一个
  `_<platform>_patch_mounts` 函数,把平台专属的 `-v` 挂载前置进
  `REPO_MOUNT_ARGS`,再定义一个 `_<platform>_lib_main` 封装函数,手动
  按顺序调用 `_parse_args`、patch 函数,然后重放 `lib_main` 剩余的逻辑。
  `dcu-vllm` 直接照搬 `hygon` 的封装——同样的 DCU 硬件,只是换了一个
  （上游 vllm）base 镜像。
- **`ascend`**（4 个 Ascend 变体各自在自己的 `start.sh` 里独立实现了这
  一套逻辑）—— 封装 `_run_container` 本身（通过 `declare -f` 拷贝函数体,
  避免按名字别名导致的无限递归）,在容器创建之后再做挂载 patch、设备
  权限配置、shell 环境变量注入,以及有条件的容器重启。
- **`nvidia`** —— 同样封装 `_run_container`,但只是为了在确认容器正在
  运行之后调用一次 `install-nsight-compute.sh`。

## 5. 已知的平台限制

- **Ascend**：即使用户组和设备权限完全正确,在共享主机上非 root 用户
  通常仍然无法访问 NPU,这是驱动层面的 namespace 冲突导致的。完整解释和
  `docker exec -u root` 的解决办法见
  [Ascend 专题 §3](ascend.md#3-为什么-npu-访问通常只能用-root)。
- **`ascend-vllm` / `ascend-vllm-910c` / `dcu-vllm`**：默认挂载的是
  `../FlagGems-vllm` 这个同级目录,而不是普通的 FlagGems（可以用 `--repo`
  覆盖）,因为上游 vllm-ascend / DCU vllm 镜像的 Python 环境是为 vLLM
  集成路径调优过的。
