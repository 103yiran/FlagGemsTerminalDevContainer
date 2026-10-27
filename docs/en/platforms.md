# Platforms

A side-by-side reference for all 15 launchers. See [Architecture](architecture.md)
for what each hook actually does, and [Ascend](ascend.md) for a deeper look
at the four Ascend variants specifically.

## 1. Base images and identity

| Launcher | `PLATFORM` | Base image | Toolkit | Dev image / default container name |
|----------|-----------|------------|---------|--------------------------------------|
| `nvidia/start.sh` | `nvidia` | `harbor.baai.ac.cn/flagos-app/vllm0.24.0-generic-13.3:2.2.0-0.3.0` | `cuda13.3` | `flaggems-nvidia:dev` / `flaggems-nvidia-dev-<user>` |
| `nvidia-vllm/start.sh` | `nvidia` | `nvcr.io/nvidia/vllm:26.10.pre1-py3` | n/a (upstream image) | `flaggems-vllm-nvidia:dev` / `flaggems-vllm-nvidia-dev-<user>` |
| `hygon/start.sh` | `hygon` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-hygon-dtk26.04:2.1.2` | `dtk26.04` | `flaggems-hygon:dev` / `flaggems-hygon-dev-<user>` |
| `hygon-vllm/start.sh` | `hygon` | `harbor.sourcefind.cn:5443/hcu/admin/base/vllm:0.21.0-ubuntu22.04-dtk2604-py3.10` | n/a (upstream image) | `flaggems-vllm-dcu:dev` / `flaggems-vllm-dcu-dev-<user>` |
| `cambricon/start.sh` | `cambricon` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-cambricon-neuware4.7.2:2.1.2` | `neuware4.7.2` | `flaggems-cambricon:dev` / `flaggems-cambricon-dev-<user>` |
| `ascend/start.sh` | `ascend` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-ascend-cann9.0.0:2.2.0` | `cann9.0.0` | `flaggems-ascend:dev` / `flaggems-ascend-dev-<user>` |
| `ascend-910c/start.sh` | `ascend` | `harbor.baai.ac.cn/flagos-base/flagos-base-ascend-cann9.0.0-910c:2.2.0` | `cann9.0.0` | `flaggems-ascend-910c:dev` / `flaggems-ascend-910c-dev-<user>` |
| `ascend-vllm/start.sh` | `ascend` | `m.daocloud.io/quay.io/ascend/vllm-ascend:v0.30.0rc1` | n/a (upstream image) | `flaggems-vllm-ascend:dev` / `flaggems-vllm-ascend-dev-<user>` |
| `ascend-vllm-910c/start.sh` | `ascend` | `m.daocloud.io/quay.io/ascend/vllm-ascend:v0.30.0rc1-a3` | n/a (upstream image, `Dockerfile.a3`) | `flaggems-vllm-ascend-910c:dev` / `flaggems-vllm-ascend-910c-dev-<user>` |
| `metax/start.sh` | `metax` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-metax-maca3.8.1.3:2.1.2` | `maca3.8.1.3` | `flaggems-metax:dev` / `flaggems-metax-dev-<user>` |
| `iluvatar/start.sh` | `iluvatar` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-iluvatar-corex4.5.0:2.1.2` | `corex4.5.0` | `flaggems-iluvatar:dev` / `flaggems-iluvatar-dev-<user>` |
| `mthreads/start.sh` | `mthreads` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-mthreads-musa5.2.0:2.1.2` | `musa5.2.0` | `flaggems-mthreads:dev` / `flaggems-mthreads-dev-<user>` |
| `kunlunxin/start.sh` | `kunlunxin` | `harbor.baai.ac.cn/flagos-runtime/flagos-runtime-kunlunxin-xre5.37.1:2.2.0` | `xre5.37.1` | `flaggems-kunlunxin:dev` / `flaggems-kunlunxin-dev-<user>` |
| `thead/start.sh` | `thead` | `pkg.flytiger-eco.com/docker_release/pytorch:v2.1.1-2.10.0-ubuntu24.04-cuda13.0-py312` | n/a (plain PyTorch image) | `flaggems-thead:dev` / `flaggems-thead-dev-<user>` |

Note: all four Ascend launchers set `PLATFORM="ascend"` internally (so they
share the Dockerfile's apt-package and group-creation branch, and
`common/lib.sh`'s default flagos-runtime naming logic) — they distinguish
themselves purely via `BASE_IMAGE_NAME`/`BASE_IMAGE_TAG` and distinct
`DEV_IMAGE`/`CONTAINER_NAME` overrides, never by changing `PLATFORM` itself.
`hygon-vllm/start.sh` follows the same pattern with `PLATFORM="hygon"` against
the upstream Hygon DCU vllm image. `nvidia-vllm/start.sh` follows the same
pattern with `PLATFORM="nvidia"` against the upstream NVIDIA NGC vllm image.

## 2. Hardware access: devices, groups, mounts, hooks

| Launcher | Device files (`platform_hardware_args`) | Extra `docker run` flags | Groups (`platform_user_groups`) | Extra host mounts | Build-time hooks |
|----------|------------------------------------------|---------------------------|----------------------------------|--------------------|---------------------|
| `nvidia` | — (`--gpus all` handles device exposure) | `--gpus all`, `--ulimit nofile=1048576:1048576` | — | — | — (post-*container-start* hook: `install-nsight-compute.sh`) |
| `nvidia-vllm` | same as `nvidia` | same as `nvidia` | — | — | — (post-*container-start* hook: `install-nsight-compute.sh`, same as `nvidia`) |
| `hygon` | `/dev/kfd`, `/dev/mkfd`, `/dev/dri` | `--group-add video`, `--group-add 39`, `--privileged` | — | `/opt/hyhal` | — |
| `hygon-vllm` | same as `hygon` | same as `hygon` | — | `/opt/hyhal` | — |
| `cambricon` | `/dev/cambricon_dev0`–`7`, `/dev/cambricon_ctl` | — | — | — | — |
| `ascend` (and all 3 other Ascend variants) | `/dev/davinci0`–`7` (`-910c` variants: `0`–`15`), `/dev/davinci_manager`, `/dev/devmm_svm`, `/dev/hisi_hdc` | `--privileged`, `--pid=host`, `--security-opt label=disable` | `HwHiAiUser` | `/usr/local/dcmi`, `/usr/local/sbin/npu-smi` | `platform_build_args` (mounts host driver read-only) + `platform_post_build_exec` (bakes driver/dcmi into image, installs cannbot plugins) — see [Ascend](ascend.md) |
| `metax` | `/dev/mxcd`, `/dev/dri` | `--group-add=video` | — | — | — |
| `iluvatar` | `/dev/itrctl`, `/dev/iluvatar0`–`15` | — | — | `/usr/local/corex` (read-only) | — |
| `mthreads` | `/dev/mtgpu.0`–`7`, `/dev/dri` | `--group-add render`, `--group-add video` | `render` (GID pinned to match the host's) | `/usr/bin/mthreads-gmi` (read-only) | — |
| `kunlunxin` | `/dev/xpu0`–`7`, `/dev/xpuctrl` | — | — | — | — |
| `thead` | `/dev/alixpu`, `/dev/alixpu_ctl`, `/dev/alixpu_ppu0`–`7` | `--privileged`, `--init`, `--shm-size=8g` | — | — | — |

A few things worth calling out:

- **Ascend's device/group setup is the most involved in the repository** —
  beyond what's in the table, it also patches device file permissions,
  resolves a `HwHiAiUser` GID conflict with the base image's `ubuntu` group,
  and configures `sudo`/shell-rc environment injection for CANN. See
  [Ascend](ascend.md) for the full picture.
- **`mthreads` is the only non-Ascend platform using `platform_user_groups`.**
  Its base image has no `render` group by default, so `--group-add render`
  at `docker run` time would fail unless the group is created first (with a
  GID matching the host's, so it actually maps to the real device owner).
- **`--privileged` appears on three platforms** (`hygon`, `ascend`/variants,
  `thead`) for different reasons — Hygon and T-Head use it as a blanket
  device-access grant from their respective reference `docker run` commands,
  while Ascend relies on it specifically to let root bypass the driver's
  namespace-ownership check (see [Ascend](ascend.md) §3 for why this
  matters and must not be removed).

## 3. Build-time packages that differ by platform

Only `nvidia` and `thead` get the extra apt/pip packages in build layer 3:
`python3-pip clang-format openssh-client` via apt, and
`pre-commit==3.7.1 flake8==7.1.0 black==23.7.0 isort==5.12.0` via
`/usr/bin/pip3 --break-system-packages`. Every other platform's `python3-pip`
needs are expected to come from the FlagOS base image's `/flagos` venv
instead.

## 4. Launchers that wrap `lib_main` vs. just calling it

Most launchers end with a plain `lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"`
call. Seven wrap it (or `_run_container`) instead, because they need to act
at a point the hook contract doesn't cover directly:

- **`hygon`, `hygon-vllm`, `iluvatar`, `mthreads`** — each defines a
  `_<platform>_patch_mounts` function that prepends a platform-specific `-v`
  mount to `REPO_MOUNT_ARGS`, and a `_<platform>_lib_main` wrapper that calls
  `_parse_args`, then the patch function, then replays the rest of
  `lib_main`'s body by hand. `hygon-vllm` copies `hygon`'s wrapper verbatim —
  same DCU hardware, just a different (upstream vllm) base image.
- **`ascend`** (shared by all four Ascend variants, since they source the
  same `ascend-refresh-env.sh`-adjacent logic independently in each
  `start.sh`) — wraps `_run_container` itself (via `declare -f` to copy its
  body, avoiding infinite recursion from name-based aliasing) to patch mounts
  *and* run device-permission setup, shell-env injection, and a conditional
  container restart after the container is created.
- **`nvidia`, `nvidia-vllm`** — each wraps `_run_container` the same way, but
  only to invoke `install-nsight-compute.sh` once the container is confirmed
  running. `nvidia-vllm` copies `nvidia`'s wrapper verbatim — same GPU
  hardware, just a different (upstream vllm) base image.

## 5. Known per-platform limitations

- **Ascend**: NPU access from a non-root user inside the container is
  usually blocked by a driver-level namespace conflict on shared hosts, even
  when group membership and device permissions are entirely correct. See
  [Ascend §3](ascend.md#3-why-npu-access-is-usually-root-only) for the full
  explanation and the `docker exec -u root` workaround.
- **`ascend-vllm` / `ascend-vllm-910c` / `hygon-vllm` / `nvidia-vllm`**:
  default to mounting a `../FlagGems-vllm` sibling checkout rather than plain
  FlagGems (use `--repo` to override), since the upstream vllm-ascend / DCU
  vllm / NVIDIA vllm image's Python environment is tuned for the vLLM
  integration path.
