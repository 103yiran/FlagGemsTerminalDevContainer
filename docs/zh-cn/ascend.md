# Ascend 专题

Ascend 有 4 个启动脚本（`ascend/start.sh`、`ascend-910c/start.sh`、
`ascend-vllm/start.sh`、`ascend-vllm-910c/start.sh`),承载了全仓库里最
复杂的平台专属逻辑——driver 烘焙、带有真实内核级坑点的 `HwHiAiUser`
权限模型、CANN 环境发现/注入,以及 cannbot 插件安装。本页把 4 个变体放在
一起讲,因为除了 base 镜像和设备数量之外,它们几乎共享全部逻辑。

## 1. 4 个变体，分别是为了什么

| 启动脚本 | Base 镜像 | 目标硬件 | 设备范围 |
|----------|-----------|---------|---------|
| `ascend/start.sh` | `flagos-runtime-ascend-cann9.0.0`（FlagOS runtime） | 910B | `/dev/davinci0`–`7` |
| `ascend-910c/start.sh` | `flagos-base-ascend-cann9.0.0-910c`（FlagOS base，910C 专用） | 910C | `/dev/davinci0`–`7` |
| `ascend-vllm/start.sh` | `vllm-ascend:v0.30.0rc1`（上游镜像，非 FlagOS） | 910B | `/dev/davinci0`–`7` |
| `ascend-vllm-910c/start.sh` | `vllm-ascend:v0.30.0rc1-a3`（上游 `Dockerfile.a3`） | Atlas A3（910_93） | `/dev/davinci0`–`15`（16 张卡） |

4 个脚本都设置 `PLATFORM="ascend"`,共享完全相同的设备权限配置、shell
环境注入,以及 cannbot 安装逻辑——只有 base 镜像引用、由此得到的
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

## 5. cannbot 插件

4 个 Ascend 启动脚本都会在构建 dev 镜像时安装一组
[cannbot](https://www.npmjs.com/package/@cannbot-plugin/cannbot) 插件,
叠加在 `common/lib.sh` 构建第 5 层已经为所有平台安装好的 Claude Code 和
Codex CLI 之上。这一步是 `platform_post_build_exec` 的一部分,自动完成,
不需要额外参数——对每个插件、每个 tool 分别执行：

```bash
npx -y @cannbot-plugin/cannbot@latest install <plugin> --tool claude
npx -y @cannbot-plugin/cannbot@latest install <plugin> --tool codex
```

插件列表：

- `triton-op-generator`
- `hccl-op-generator`
- `model-infer-optimize`
- `ops-registry-invoke`
- `ops-direct-invoke`

这些插件为 `claude` 和 `codex` 提供了 Ascend 专属的上下文,用于生成
Triton/HCCL 算子,以及在模型推理场景中注册/调用算子。单个 plugin 安装
失败（比如 npm registry 偶发抓取失败）只会打印警告——不会导致整个镜像
构建失败。如果某个插件没装上,重新执行 `--rebuild-dev` 即可重试。
