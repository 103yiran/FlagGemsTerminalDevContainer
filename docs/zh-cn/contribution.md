# 贡献指南

## 1. 新增一个硬件平台

最小化的启动脚本只需要三件事——一个 `PLATFORM` 身份标识、一个
`platform_hardware_args` 函数,以及一次 `source` + `lib_main` 调用。
可以从仓库里最简单的例子 `cambricon/start.sh` 开始：

```bash
#!/usr/bin/env bash
# <platform>/start.sh — 启动 FlagGems <Platform> 开发容器。
#
# Base 镜像：  <registry>/<base-image>:<tag>
#             （工具链 <toolkit>；dev 镜像 flaggems-<platform>:dev）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

PLATFORM="<platform>"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-<toolkit>}"

platform_hardware_args() {
    cat << 'EOF'
--device=/dev/<devfile0>
--device=/dev/<devfile1>
EOF
}

source "${REPO_ROOT}/common/lib.sh"
lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
```

在此基础上,只添加平台真正需要的钩子——不要定义一个什么都不输出的空
钩子。完整的钩子约定见
[架构 §3](architecture.md#3-platform_-钩子约定),各现有启动脚本的实际
用法见[平台参考](platforms.md)：

- **需要驱动按用户组控制访问？** 加一个 `platform_user_groups`,逐行
  输出 `name` 或 `name:gid`——GID 固定的写法参考 `mthreads/start.sh`
  （`getent group render | cut -d: -f3`）。
- **需要把宿主机路径挂进*构建*容器**（为了把某些东西烘焙进镜像,就像
  Ascend 处理 driver 那样）**？** 加一个 `platform_build_args`,再配合
  `platform_post_build_exec` 在 commit 之前真正完成拷贝/chmod。
- **需要在*运行中*的容器里、每次启动都挂载某个宿主机路径？** 定义一个
  `<PLATFORM>_EXTRA_MOUNTS` 数组和一个 `_<platform>_patch_mounts`
  函数,然后像 `hygon/start.sh`、`iluvatar/start.sh`、`mthreads/start.sh`
  那样封装 `lib_main`——直接照抄它们的封装写法,换成自己的 patch 函数
  调用即可。不要为此重新发明一套封装;保持所有平台的封装形态一致,
  才能让未来 `common/lib.sh` 的重构（比如正式加一个
  `platform_extra_mounts` 钩子）变成一次机械的查找替换,而不是要逐个
  审查 N 份各自为政的封装代码。
- **需要某个操作只在容器真正启动之后执行**（而不是镜像构建时）**？**
  像 `nvidia/start.sh` 对 `install-nsight-compute.sh` 的做法那样封装
  `_run_container`——用
  `eval "_orig_run_container() $(declare -f _run_container | tail -n +2)"`
  拷贝函数体,而不是按名字做别名（按名字别名会导致无限递归,因为 bash
  在调用时才解析函数名）。
- **base 镜像不遵循 `flagos-runtime-<platform>-<toolkit>` 命名？** 在
  `source common/lib.sh` 之前自己设置
  `BASE_IMAGE_REGISTRY`/`BASE_IMAGE_NAME`/`BASE_IMAGE_TAG`——参考
  `thead/start.sh` 或 `ascend-910c/start.sh`。

新增或修改一个启动脚本之后,记得同步更新：

- `Dockerfile` 头部注释里列出的 `PLATFORM=` 选项,以及如果新平台需要在
  构建第 3 层安装自己的 apt/pip 包,还要加对应的 `ARG PLATFORM` 分支。
- `README.md` / `README_cn.md`——目录结构树、前置条件列表（宿主机需要
  的设备文件）,以及一条 `### Launch (<Platform>)` 条目。
- `docs/en/platforms.md` / `docs/zh-cn/platforms.md`——给两份表格各加
  一行。

## 2. 测试一个启动脚本的改动

启动脚本本身没有自动化测试套件（它们只是对 `docker` 调用的薄封装）——
需要手动验证：

```bash
# 强制完整重建,检测构建层回归
./<platform>/start.sh --rebuild-dev -f

# 确认容器信息摘要显示的镜像/挂载符合预期
# （_print_summary 会在 exec 进容器之前自动打印）

# 进入容器后，检查工具链是否正常：
python3 -c "import torch; print(torch.__version__)"
claude --version
codex --version
```

如果改动直接影响 `common/lib.sh` 或 `common/setup.sh`,至少要在两个平台
上测试（一个基于 flagos-runtime 的,一个 base 镜像非标准的,比如
`nvidia` 或 `thead`),因为这两条路径最容易出现分歧。

## 3. 代码风格约定

- 注释解释*为什么*,而不是*做了什么*——`common/lib.sh` 或
  `ascend/start.sh` 里几乎任何一个函数都是预期的注释密度参考。在一句
  明显的 `cp` 上面写一行 `# 拷贝 driver` 没有意义;解释*为什么*
  bind-mount 会破坏权限,才是有价值的注释。
- 优先扩展上面描述的现有钩子/封装模式,而不是为单个平台发明一套新机制——
  一个平台专属的特例,比一个已经被记录、并在别处用过的钩子,更难被下一个
  贡献者找到。
- 保持 `common/lib.sh` 与平台无关。只有一两个平台需要的东西应该放在
  那个平台自己的 `start.sh` 里,挂在某个钩子后面,而不是在
  `common/lib.sh` 内部写 `if [[ "$PLATFORM" == ... ]]` 分支——现有唯一
  的例外（`_build_dev` commit 步骤里针对 `nvidia` 的 `PATH` 前置）之所以
  在注释里被特别点出来,正是因为它是一个例外。
