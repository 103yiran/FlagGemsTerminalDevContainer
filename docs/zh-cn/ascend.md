# Ascend 专题

Ascend 有 5 个启动脚本（`ascend/start.sh`、`ascend-910c/start.sh`、
`ascend-vllm/start.sh`、`ascend-vllm-910c/start.sh`、
`ascend-vllm-950dt/start.sh`),承载了全仓库里最
复杂的平台专属逻辑——driver 烘焙、带有真实内核级坑点的 `HwHiAiUser`
权限模型、CANN 环境发现/注入,以及 cannbot-knowledge 知识库安装。本页把
5 个变体放在一起讲,因为除了 base 镜像和设备数量之外,它们几乎共享全部
逻辑。

## 1. 5 个变体，分别是为了什么

| 启动脚本 | Base 镜像 | 目标硬件 | 设备范围 |
|----------|-----------|---------|---------|
| `ascend/start.sh` | `flagos-runtime-ascend-cann9.0.0`（FlagOS runtime） | 910B | `/dev/davinci0`–`7` |
| `ascend-910c/start.sh` | `flagos-base-ascend-cann9.0.0-910c`（FlagOS base，910C 专用） | 910C | `/dev/davinci0`–`7` |
| `ascend-vllm/start.sh` | `vllm-ascend:v0.30.0rc1`（上游镜像，非 FlagOS） | 910B | `/dev/davinci0`–`7` |
| `ascend-vllm-910c/start.sh` | `vllm-ascend:v0.30.0rc1-a3`（上游 `Dockerfile.a3`） | Atlas A3（910_93） | `/dev/davinci0`–`15`（16 张卡） |
| `ascend-vllm-950dt/start.sh` | `vllm-ascend:v0.30.0rc2-a5`（上游镜像，950DT 构建） | 950DT | `/dev/davinci0`–`7` |

5 个脚本都设置 `PLATFORM="ascend"`,共享完全相同的设备权限配置、shell
环境注入,以及 cannbot-knowledge 安装逻辑——只有 base 镜像引用、由此得到的
`DEV_IMAGE`/`CONTAINER_NAME`,以及（Atlas A3 的 `-910c` 变体）设备数量
不同。`-vllm` 系列额外默认挂载 `../FlagGems-vllm` 这个同级目录而不是
普通 FlagGems,匹配上游镜像为 vLLM 调优过的 Python 环境——如果也想在这
里用普通 FlagGems,用 `--repo` 覆盖即可。

## 2. Driver 和 dcmi 的烘焙

宿主机上的 Ascend driver 文件（例如
`driver/lib64/common/libaivault.so`）权限是 `0400`,属主是 uid 1000
（宿主机上的 `HwHiAiUser`）,并且设置了 immutable（`chattr +i`）标志。
即便容器内的 root 也无法 `chmod` 它们,而 bind-mount 会把宿主机的这些
原始权限原样暴露进容器——所以任何 uid 不是恰好 1000 的容器用户,在
`aclInit` 尝试 `dlopen` 这个 `.so` 时都会遇到 `EACCES`,表现为 Ascend
错误码 `507899`。

修复发生在镜像构建阶段,在 `platform_post_build_exec` 里：

1. `platform_build_args` 把宿主机的 `/usr/local/Ascend/driver` 和
   `/usr/local/dcmi` 以只读方式挂载进*构建*容器。
2. `platform_post_build_exec` 把两者拷贝（`cp -a`,不是挂载）进镜像层,
   清除 immutable 标志（`chattr -Ri`),再 `chmod -R a+rX`。因为这发生在
   一个即将被 `docker commit` 的容器里,root 对这份拷贝拥有完整所有权,
   chmod 才能真正生效。
3. 到容器运行阶段,driver 不会再次被 bind-mount（那样会用原始的严格权限
   盖掉已经修好的拷贝）——只有 `/usr/local/dcmi` 和
   `/usr/local/sbin/npu-smi` 会被挂载,因为宿主机上的 dcmi 文件本身就是
   全局可读的。

`-vllm` 系列在拷贝之前还会先 `rm -rf` 已存在的
`/usr/local/Ascend/driver`/`dcmi`,因为 vllm-ascend 的 base 镜像本身就
自带了一套 CANN/driver 安装——宿主机的 driver 始终优先,因为它才是真正
匹配这台机器上 NPU 固件的那一份。

## 3. 为什么 NPU 访问通常只能用 root

在共享的 Ascend 主机上,容器内访问 NPU 通常**只能用 root**：

```bash
docker exec -u root -w /workspace/FlagGems flaggems-ascend-dev-$(id -un) \
    bash -lc 'pytest tests/test_abs.py -vs'
```

非 root 用户打开 `/dev/davinci*` 会失败并报 `EBUSY`（errno 16),
`npu-smi info` 会报 `dcmi model initialized failed ... ret is -8020`,在
PyTorch 里则表现为 `aclInit` 错误 `507899` / `Resource_Busy(EL0005)`。

**这不是文件权限问题。** `start.sh` 已经创建了 GID 与设备节点匹配的
`HwHiAiUser` 组,并把容器用户加入其中——可以这样确认这一侧配置正确：

```bash
docker exec -u $(id -un) <容器> id          # 期望 groups=...,1000(HwHiAiUser)
docker exec -u root <容器> stat -c '%n %u:%g %a' /dev/davinci0   # 期望 1000:1000 660
```

`EBUSY` 意味着内核已经允许了 `open()`,是*驱动*拒绝了它。Ascend 驱动一次
只把一张卡授予一个 namespace（宿主机 `dmesg` 里的
`uda_occupy_dev_by_ns`,会记录 `Conflict open udevid`）。一旦某张卡被
另一个 namespace 占用,驱动只会放行**同时**满足"真正的 root"和"拥有完整
capabilities"的进程——把用户加入 `HwHiAiUser`,或者给非 root 用户授予
capabilities,都无法改变这一点。

带来的后果：

- 任何涉及 NPU 的操作优先用 `docker exec -u root`。纯 CPU 的工作（编辑、
  lint、CPU 上的 `pytest`）不需要特殊处理。
- **不要**为了让非 root 访问生效而移除 `--privileged`——privileged 模式
  恰恰是让 *root* 能绕过 namespace 检查的关键;没有它,root 同样会失去
  NPU 访问权限。
- 非 root 访问只有在分配给你的卡没有被其他 namespace 占用时才可能实现,
  这需要全主机范围的统一约定（每个容器都用
  `--runtime=ascend -e ASCEND_VISIBLE_DEVICES=<ids>` 启动,而不是
  `--privileged` + 显式 `--device`),所以单靠这个仓库是解决不了的。
- 清除残留的 namespace 占用需要重新加载 Ascend 内核模块或重启主机,会
  影响这台机器上的所有容器——需要和主机管理员协调。

## 4. CANN 环境发现与注入

由于 `docker exec` 会跳过 PAM,交互式 `docker exec` 会话里永远不会加载
`/etc/environment`——所以 Ascend 的环境变量（`ASCEND_HOME_PATH`、
`ASCEND_TOOLKIT_HOME` 等）改为直接注入 `~/.zshrc`/`~/.bashrc`,夹在管理
标记之间（`# >>> ascend-env (managed by start.sh) >>>` /
`# <<< ascend-env <<<`),这样重新运行 `start.sh` 时会原地更新这段内容,
而不是重复追加。

这份环境变量的来源是动态发现的,而不是硬编码某个 CANN 版本,按以下优先级
查找：

1. 用户自己安装在 `~/Ascend/**/set_env.sh` 下的 CANN（取最新的）。
2. `/usr/local/Ascend/ascend-toolkit/set_env.sh`（`latest` 软链接）。
3. `/usr/local/Ascend` 下任何其他 `set_env.sh`（排除 `nnal`）。
4. 作为最后手段,使用 base 镜像自带的 `/etc/profile.d/vendor.sh`。

找到的脚本会在一个干净的子 shell 里被 source,然后对导出的变量做过滤：
显式丢弃 `PYTHONPATH`（否则 CANN 自带的 Python 包会盖掉 `/flagos`
虚拟环境的 site-packages,导致 `import triton` 失败),保留
`ASCEND_*`、`ATB_*`、`LD_LIBRARY_PATH`、`PATH`、`CMAKE_PREFIX_PATH`、
`TOOLCHAIN_HOME`。注入块的最后会再把 `/flagos/bin` 前置回 `PATH`,确保
FlagOS 虚拟环境的 `python3` 仍然优先。

如果在运行中的容器里升级了 CANN,可以用安装好的辅助命令重新注入,无需
重启容器：

```bash
sudo ascend-refresh-env
```

`sudo` 本身也会被配置（一个 `/etc/sudoers.d/ascend-env` drop-in）来保留
`PATH`/`LD_LIBRARY_PATH`/`ASCEND_*`/`ATB_*` 并关闭 `secure_path`,这样
`sudo python3`/`sudo pytest` 会继续用当前激活的虚拟环境,而不是被重置成
系统解释器。`/usr/local/bin/sudo-python` 这个 wrapper 专门处理"想在
`sudo` 下用当前 `$VIRTUAL_ENV` 对应的解释器"这个常见场景。

## 5. cannbot-knowledge 知识库

5 个 Ascend 启动脚本都会安装
[cannbot-knowledge](https://gitcode.com/cann/cannbot-knowledge)——一个
面向 CANN 社区的可检索、可溯源的领域知识库,覆盖 AscendC/PyPTO/TileLang
/Triton 等算子开发、模型迁移、推理优化,以及图模式、Runtime 等场景。它
取代了旧版基于 npm 的 `@cannbot-plugin/cannbot` 插件安装方式。

旧版 cannbot 插件通过全局 `npx` 安装,不依赖任何项目路径,所以可以放在
`platform_post_build_exec` 里,在镜像构建阶段（此时仓库还未挂载）完成。
cannbot-knowledge 的 `install.sh <tool> <project-path> [consumer|contributor]`
要求 `<project-path>` 是一个已经存在的目录,并把项目专属文件（
`.claude/skills`、`CLAUDE.md` 里的管理块、`.agents/skills`、
`.cannbot/knowledge.env`）直接写进这个目录——因此这一步必须在仓库已经
挂载到容器之后运行,而不是镜像构建期。它现在是 `_run_container` 覆盖逻辑
的一部分（`_ascend_install_cannbot_knowledge`),在 Ascend 环境初始化之后、
容器因组权限变更重启之前执行,每次启动/重新连接容器都会执行一次：

```bash
bash install.sh claude <WORKSPACE_DIR> consumer
bash install.sh codex  <WORKSPACE_DIR> consumer
```

其中 `<WORKSPACE_DIR>` 就是仓库挂载进容器的路径（默认
`/workspace/FlagGems`）。知识库仓库本身克隆到容器用户 home 下的
`~/.cannbot/cannbot-knowledge`（`install.sh` 自带的默认位置),该 home 目录
通过 bind mount 落在宿主机的 `$HOME/<容器名>` 下,所以重启或重建容器都不会
丢失这份克隆,第二次运行会直接 fast-forward 更新而不是重新 clone。安装以
容器用户身份（非 root）在 login shell 下运行,这样 PATH 能取到
`_ascend_inject_shell_env` 注入的 `/flagos/bin` 下的 `python3`（要求
`>= 3.10`）。

`consumer` 模式只装三个只读检索 Skill：`knowledge-query`、
`ascendc-api-knowledge-query`、`runtime-api-knowledge-query`——分别用于
通用知识检索、Ascend C API 查询、CANN Runtime API 推荐/比较。
`contributor` 模式还会额外装 `knowledge-ingest`、`knowledge-lint` 和两个
算子知识提取 Skill,面向要往知识库贡献内容的场景；这些启动脚本只需要
`consumer`,没有走 `contributor` 路径。

安装失败（比如 git clone 网络问题,或目标 Python 版本太旧）只会打印
`print_warn` 警告并跳过——不会导致 `start.sh` 整体失败。可以手动在容器里
重跑：

```bash
cd ~/.cannbot/cannbot-knowledge && bash install.sh claude /workspace/FlagGems consumer
```
