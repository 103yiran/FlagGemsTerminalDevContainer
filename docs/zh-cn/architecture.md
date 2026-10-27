# 架构

本页讲解 `common/lib.sh` 的构建/运行流水线、所有启动脚本都依赖的
`platform_*` 钩子约定,以及 `common/setup.sh` 在新容器里具体安装了什么。

## 1. 为什么用 run→exec→commit 而不是 `docker build`

`common/lib.sh` 里的 `_build_dev` 构建 dev 镜像的方式是：从 FlagOS base
镜像启动一个临时容器,用 `docker exec` 在其中执行 Dockerfile 里的各层,
再 `docker commit` 得到结果——而不是直接对 `Dockerfile` 跑
`docker build`。`_build_dev` 顶部的注释解释了原因：当前环境的 seccomp
策略会阻止在 `docker build` *内部*创建容器（某些 base 镜像里的工具本身
会尝试拉起容器）,而 `docker run --security-opt seccomp=unconfined` 可以
绕开这个限制。`Dockerfile` 仍然保留作为同一组层的可读文档,但在这套环境
里它并不是实际构建所依赖的那份文件。

## 2. 六个构建层

每一层都是对临时构建容器（`flaggems-build-$$`）执行一次 `docker exec`，
以 root 身份运行：

1. **uv 缓存目录、`/flagos` 权限、uv 软链接。** 把 `/flagos`（预装好的
   FlagGems 虚拟环境）和 `/usr/local/share/uv` 的所有权转给宿主机用户的
   uid:gid,打开 `/root` 和 `/root/.local/share/uv/python` 的权限,确保
   虚拟环境软链接指向的 Python 解释器对非 root 用户仍然可达,把 `uv`
   软链接到 `/usr/local/bin`,并在虚拟环境里安装 `pytest==8.3.5`。
2. **apt 源切换到阿里云镜像。** 把 `/etc/apt/sources.list(.d/ubuntu.sources)`
   里的 `archive.ubuntu.com`/`security.ubuntu.com` 替换成
   `mirrors.aliyun.com`。
3. **系统包 + 用户创建。** 安装 `sudo zsh git curl wget unzip
   ca-certificates ripgrep fd-find gh openssh-client`,以及（仅 NVIDIA 和
   平头哥）`python3-pip clang-format`,并通过 pip 安装固定版本的
   `pre-commit==3.7.1 flake8==7.1.0 black==23.7.0 isort==5.12.0`。先创建
   `platform_user_groups` 返回的平台专属用户组（见下文）,再用宿主机的
   uid/gid 创建容器用户,并配置免密 sudo。
4. **Neovim ≥ 0.11。** 如果 base 镜像自带的版本已经满足要求就跳过；否则
   从 NJU 镜像（`mirror.nju.edu.cn/github-release/neovim/neovim`）下载
   `LatestRelease` 压缩包,失败时重试最多 3 次,并用有限的 `--max-time`
   限制每次尝试（在不稳定的代理环境下,TCP 连接可能已经建立但没有任何
   数据传输,单纯的 `--connect-timeout` 捕捉不到这种情况）。
5. **Node.js + Claude Code CLI + Codex CLI + CodeBuddy Code CLI。** 从
   `mirrors.aliyun.com/nodejs-release` 下载 Node 22.23.1 压缩包,然后通过
   `registry.npmmirror.com` 执行
   `npm install -g @anthropic-ai/claude-code @openai/codex @tencent-ai/codebuddy-code`,同样采用
   重试+超时的保护（npm 在卡住的网络请求上并不会可靠地响应 `SIGTERM`,
   所以外层的 `timeout --kill-after=10` 会在超时后补发 `SIGKILL`）。
6. **让 zsh 加载 `/etc/profile.d`。** 在 `/etc/zsh/zshenv` 里追加一段
   脚本,让 zsh（默认的 `EXEC_COMMAND`）也像 bash 通过 `BASH_ENV` 那样
   加载 `/etc/profile.d/*.sh`——这是像 Hygon 的 `vendor.sh`（为 DTK 设置
   `LD_LIBRARY_PATH`/`PATH`）这类平台 vendor 脚本所需要的。因为
   `vendor.sh` 会直接覆盖 `PATH`,所以之后还要重新把 `/flagos/bin` 前置
   回去。

第 6 层执行完后,如果平台定义了 `platform_post_build_exec`,会接着执行
（同样是在构建容器内,以 root 身份）,然后容器被 commit 成
`flaggems-<platform>:dev`,附带 `ENV UV_CACHE_DIR=...`、
`USER <username>`、`WORKDIR /workspace`,以及——当 `PLATFORM` 是
`nvidia` *且* 构建容器里确实存在 `/flagos` 时——一个把 `/flagos/bin`
前置到 base 镜像原有 `PATH` 前面的改动。第二个条件把 `nvidia-vllm`
排除在外：它同样设置 `PLATFORM="nvidia"`,但构建自一个没有 `/flagos`
虚拟环境的上游 NGC 镜像。

## 3. `platform_*` 钩子约定

启动脚本通过在 `source common/lib.sh` *之前*定义以下函数的某个子集来
定制共享流水线。`common/lib.sh` 在调用每个钩子前都会先 `declare -f` 检查
是否存在,所以钩子纯粹是可选叠加的——不需要某个钩子的平台完全不用定义它。

| 钩子 | 是否必须 | 调用位置 | 作用 |
|------|---------|---------|------|
| `platform_hardware_args` | **是** | `_run_container`，在 `docker run` 之前 | 逐行输出额外的 `docker run` flag（设备文件、`--privileged`、`--group-add`、ulimit 等）,作用于长期运行的 dev 容器。 |
| `platform_user_groups` | 否 | `_build_dev` 第 3 层 | 逐行输出要创建并加入容器用户的额外用户组（`name` 或 `name:gid` 以固定 GID），在 `useradd` 之前执行。用于驱动按用户组成员身份控制访问的场景（例如 Ascend 的 `HwHiAiUser`、摩尔线程的 `render`）。 |
| `platform_build_args` | 否 | `_build_dev`，启动构建容器之前 | 专门为*临时构建容器*输出额外的 `docker run` flag（例如 Ascend 以只读方式挂载宿主机 driver,供 `platform_post_build_exec` 烘焙进镜像）。 |
| `platform_post_build_exec` | 否 | `_build_dev`，第 6 层之后、`docker commit` 之前 | 对构建容器执行任意 `docker exec -u root` 命令,在 commit 之前完成。用于任何需要真正烘焙进镜像层的操作——Ascend 的 driver/dcmi 拷贝与权限修复,以及 cannbot 插件安装（见[Ascend 专题](ascend.md)）。 |

还有三个扩展点不是正式的钩子,但所有需要它们的启动脚本都用同一套约定
（谁用了哪个见[平台参考](platforms.md)）：

- **为*运行中*的容器挂载额外路径。** 需要在容器运行时（而不是构建时）
  挂载某个宿主机路径的启动脚本,会自己定义一个 `<PLATFORM>_EXTRA_MOUNTS`
  数组和一个 `_<platform>_patch_mounts` 函数,把它前置进
  `REPO_MOUNT_ARGS`,再通过封装 `_run_container`（Ascend）或封装
  `lib_main` 本身（Hygon、Iluvatar、摩尔线程）,在 `_parse_args` 之后
  立刻调用这个 patch 函数。
- **非默认的 base 镜像命名。** `common/lib.sh` 默认把 `BASE_IMAGE_NAME`
  设为 `${BASE_IMAGE_REGISTRY}/flagos-runtime-${PLATFORM}-${TOOLKIT_VERSION}`。
  base 镜像不遵循这个命名规则的平台（NVIDIA、NVIDIA vllm、平头哥、
  Ascend 910C、Ascend vllm 系列、Hygon vllm）会在 `source common/lib.sh`
  *之前*自行设置 `BASE_IMAGE_REGISTRY`/`BASE_IMAGE_NAME`/`BASE_IMAGE_TAG`。
- **容器启动之后才执行的步骤。** 需要在长期运行的容器真正启动之后
  （而不是镜像构建时）跑点东西的启动脚本,会用 NVIDIA（以及照搬同一套
  封装的 NVIDIA vllm）对 `install-nsight-compute.sh` 的方式,或者 Ascend
  对设备权限/shell 环境注入的方式,去封装 `_run_container`。

## 4. `common/setup.sh`：新容器里发生了什么

`_run_container` 会把 `common/setup.sh` 拷贝进新建的容器,在容器刚创建后
以容器用户身份运行一次。它是幂等的——重复运行（比如手动再跑一次）会跳过
已经装好的部分。

1. **GitHub known_hosts。** 把 GitHub 的公钥追加到 `~/.ssh/known_hosts`,
   确保第 3 步的 SSH 兜底 clone 不会卡在 host-key 确认提示上。
2. **oh-my-zsh + 插件。** 从 `gitee.com/mirrors/*` clone `oh-my-zsh`、
   `zsh-autosuggestions`、`zsh-syntax-highlighting`（这部分不需要
   GitHub）,写入 oh-my-zsh 的 `.zshrc` 模板,取消注释其中的
   `$HOME/.local/bin` PATH 行,并在 `plugins=(...)` 里启用这两个插件。
3. **LazyVim。** clone `LazyVim/starter` 这个*模板*仓库（不是
   `LazyVim/LazyVim` 插件仓库本身——后者在 `nvim --headless` 下会卡在一个
   交互式拦截上）到 `~/.config/nvim`,依次尝试：`gitcode.com/gh_mirrors/sta/starter`
   的 HTTPS 镜像、`github.com/LazyVim/starter` 的 HTTPS,以及（仅当有可用
   的 SSH key 或 agent 时）两者的 SSH 形式——见 `clone_repo()`。随后会
   覆写 `lua/config/lazy.lua`,让 `lazy.nvim` 自身的 bootstrap 以及每个
   插件的 clone 都走同一套 gitcode 镜像方案（有一小份清单,比如
   `echasnovski`/`nvim-mini`,因为它们的仓库大多不在镜像列表里,会直接
   走 GitHub）,禁用需要 tree-sitter CLI 的功能,最后在 300 秒超时内运行
   `nvim --headless "+Lazy! sync" +qa`。同步完成后还有一轮后处理：检测
   `.git` 存在但工作区为空的插件（partial-clone 的 checkout 失败），用
   `git checkout -f HEAD` 恢复。
4. **光标可见性修复。** 始终安装
   `~/.config/nvim/lua/plugins/cursor-fix.lua`,这是一个很小的 LazyVim
   覆盖配置,设置高对比度的光标颜色,并去掉 Comment 高亮有时继承的背景
   色——这一步与 LazyVim 本身是不是刚刚被 clone 无关,总会执行。

如果第 3 步的所有 clone 尝试都失败（无法直连 GitHub/GitCode,也没有可用
的代理或 SSH key）,LazyVim 这一步会打印警告并跳过,脚本其余部分仍然会
正常跑完——你会得到一个没有插件的 Neovim,以及其他方面配置完整的 zsh。
