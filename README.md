# FlagGemsTerminalDevContainer

A terminal development container environment for [FlagGems](https://github.com/FlagOpen/FlagGems) contributors, supporting NVIDIA, Hygon, Cambricon, Ascend, Metax, Iluvatar, Moore Threads, Kunlunxin, and T-Head hardware platforms. The container ships with zsh, Neovim (LazyVim), Claude Code, and a full code-quality toolchain out of the box.

[中文文档](README_cn.md)

## Repository layout

```
FlagGemsTerminalDevContainer/
├── Dockerfile            # unified dev image (NVIDIA + Hygon + Cambricon + Ascend + Metax + Iluvatar + Moore Threads + T-Head via ARG PLATFORM)
├── common/
│   ├── lib.sh            # shared shell logic (arg parsing, build, run)
│   └── setup.sh          # runs once inside a new container to install zsh/nvim plugins
├── nvidia/
│   └── start.sh          # NVIDIA launcher — sources common/lib.sh
├── hygon/
│   └── start.sh          # Hygon launcher — sources common/lib.sh
├── cambricon/
│   └── start.sh          # Cambricon launcher — sources common/lib.sh
├── ascend/
│   └── start.sh          # Ascend (910B) launcher — sources common/lib.sh
├── ascend-910c/
│   └── start.sh          # Ascend 910C launcher — same platform logic, 910C-specific base image
├── ascend-vllm/
│   └── start.sh          # Ascend launcher on the upstream vllm-ascend image — same platform logic, vllm-ascend base image
├── ascend-vllm-910c/
│   └── start.sh          # Ascend launcher on the upstream vllm-ascend image, Atlas A3 (-a3) tag — same platform logic, 16-device range
├── metax/
│   └── start.sh          # Metax launcher — sources common/lib.sh
├── iluvatar/
│   └── start.sh          # Iluvatar launcher — sources common/lib.sh
├── mthreads/
│   └── start.sh          # Moore Threads launcher — sources common/lib.sh
├── kunlunxin/
│   └── start.sh          # Kunlunxin launcher — sources common/lib.sh
└── thead/
    └── start.sh          # T-Head launcher — sources common/lib.sh
```

## Prerequisites

- Docker installed and accessible
- FlagGems source tree checked out as a sibling of this repository:

  ```
  parent/
  ├── FlagGems/                      # FlagGems source
  └── FlagGemsTerminalDevContainer/  # this repo
  ```

  Additional repos (e.g. `FlagTree`) can be mounted at runtime via `--repo`.

- **Outbound access to GitHub/GitCode**, needed to install the editor and
  shell plugins (LazyVim / lazy.nvim and their dependencies are cloned over
  HTTPS, preferring `gitcode.com` mirrors with a `github.com` fallback).
  - If the host reaches GitHub/GitCode directly, nothing further is needed.
  - If the host only has an HTTP(S) proxy (e.g. `http_proxy`/`https_proxy`
    exported from `~/.bashrc`), that's enough — `start.sh` forwards those
    variables into the container automatically.
  - An SSH key on the host with its public half added to
    [GitCode](https://gitcode.com/) is an optional extra fallback, tried only
    if both HTTPS attempts fail. Verify it with `ssh -T git@gitcode.com` if
    you want to rely on it.
  - If none of the above gets through, plugin installation is skipped and you
    get a bare nvim / plain zsh instead.

- NVIDIA platform: NVIDIA Container Toolkit installed on the host
- Hygon platform: `/dev/kfd`, `/dev/dri` devices available on the host and `/opt/hyhal` mounted
- Cambricon platform: `/dev/cambricon_dev*` and `/dev/cambricon_ctl` devices available on the host
- Ascend platform (`ascend/`, `ascend-910c/`, `ascend-vllm/`, and `ascend-vllm-910c/`): `/dev/davinci0`, `/dev/davinci_manager`, `/dev/devmm_svm`, `/dev/hisi_hdc` devices available on the host (`ascend-vllm-910c/` expects up to 16 devices, `/dev/davinci0`–`/dev/davinci15`, matching Atlas A3 nodes); `/usr/local/Ascend/driver`, `/usr/local/dcmi`, and `/usr/local/sbin/npu-smi` present on the host
- Metax platform: `/dev/mxcd` and `/dev/dri` devices available on the host; user must be in the `video` group
- Iluvatar platform: `/dev/iluvatar0` through `/dev/iluvatar15` devices available on the host and `/usr/local/corex` present on the host
- Moore Threads platform: `/dev/mtgpu.0` through `/dev/mtgpu.7` and `/dev/dri` devices available on the host, `/usr/bin/mthreads-gmi` present on the host; user must be in the `render` and `video` groups
- Kunlunxin platform: `/dev/xpu0` through `/dev/xpu7` and `/dev/xpuctrl` devices available on the host
- T-Head platform: `/dev/alixpu`, `/dev/alixpu_ctl`, and `/dev/alixpu_ppu0` through `/dev/alixpu_ppu7` devices available on the host

## Quick start

```bash
git clone https://github.com/your-org/FlagGemsTerminalDevContainer.git
```

### Launch (NVIDIA)

```bash
./nvidia/start.sh
```

`start.sh` also installs NVIDIA Nsight Compute (`ncu`) into the container after it starts (idempotent — skipped if already installed). To pin or upgrade the version:

```bash
NSIGHT_COMPUTE_VERSION=2026.4.0 ./nvidia/start.sh
```

See `nvidia/install-nsight-compute.sh` for details, including the `.run`-installer fallback for versions not yet in NVIDIA's apt repo.

### Launch (Hygon)

```bash
./hygon/start.sh
```

### Launch (Cambricon)

```bash
./cambricon/start.sh
```

### Launch (Ascend)

```bash
./ascend/start.sh
```

### Launch (Ascend 910C)

```bash
./ascend-910c/start.sh
```

Same platform setup as `ascend/start.sh` (device mounts, driver baking, CANN
env injection) but built on the 910C-specific base image
(`flagos-base-ascend-cann9.0.0-910c`) instead of
`flagos-runtime-ascend-cann9.0.0`. Uses its own dev image/container name
(`flaggems-ascend-910c:dev`, `flaggems-ascend-910c-dev-<username>`) so it
never collides with a plain Ascend container on the same host.

### Launch (Ascend, vllm-ascend base image)

```bash
./ascend-vllm/start.sh
```

Same platform setup as `ascend/start.sh` (device mounts, driver baking,
HwHiAiUser group, CANN env injection) but built on the upstream
[vllm-ascend](https://github.com/vllm-project/vllm-ascend) image
(`m.daocloud.io/quay.io/ascend/vllm-ascend:v0.26.0rc1`) instead of a
FlagOS `flagos-runtime`/`flagos-base` image. That base image ships vLLM,
torch_npu, and vllm-ascend preinstalled into the system Python (no `/flagos`
venv), runs as root by default, and has no `HwHiAiUser` group — this launcher
adds the same non-root NPU access setup used by `ascend-910c/start.sh` on top
of it. Uses its own dev image/container name (`flaggems-vllm-ascend:dev`,
`flaggems-vllm-ascend-dev-<username>`) so it never collides with the other
Ascend containers on the same host. Defaults to mounting the
`../FlagGems-vllm` sibling checkout (still at `/workspace/FlagGems` inside
the container) rather than plain FlagGems — use `--repo` to mount something
else. Override `BASE_IMAGE_TAG` to pin a different vllm-ascend release.

### Launch (Ascend, vllm-ascend base image, Atlas A3)

```bash
./ascend-vllm-910c/start.sh
```

Same as `ascend-vllm/start.sh` above (same base image stack, same non-root
NPU access setup, same `../FlagGems-vllm` default mount) but pinned to the
`v0.26.0rc1-a3` tag — vllm-ascend's own [Dockerfile.a3](https://github.com/vllm-project/vllm-ascend/blob/v0.26.0rc1/Dockerfile.a3)
build, targeting Atlas A3 (910_93) hardware instead of 910B. The only other
difference is the device range: this launcher mounts `/dev/davinci0` through
`/dev/davinci15` (16 devices) to match a typical Atlas A3 node, rather than
the 8-device range (`/dev/davinci0`–`/dev/davinci7`) used by the other three
Ascend launchers. Uses its own dev image/container name
(`flaggems-vllm-ascend-910c:dev`, `flaggems-vllm-ascend-910c-dev-<username>`)
so it never collides with the other Ascend containers on the same host.

### Ascend cannbot plugins

All four Ascend launchers (`ascend`, `ascend-910c`, `ascend-vllm`,
`ascend-vllm-910c`) install a set of [cannbot](https://www.npmjs.com/package/@cannbot-plugin/cannbot)
plugins into the dev image during build, on top of the Claude Code and Codex
CLIs already installed by `common/lib.sh`. This happens automatically — no
extra flags needed — via:

```bash
npx -y @cannbot-plugin/cannbot@latest install <plugin> --tool claude
npx -y @cannbot-plugin/cannbot@latest install <plugin> --tool codex
```

for each of the following plugins:

- `triton-op-generator`
- `hccl-op-generator`
- `model-infer-optimize`
- `ops-registry-invoke`
- `ops-direct-invoke`

These give both `claude` and `codex` Ascend-specific context for generating
Triton/HCCL ops and invoking/registering ops during model inference work. A
single plugin failing to install (e.g. a flaky npm registry fetch) only logs
a warning and does not fail the image build — rerun `start.sh` to retry if a
plugin didn't make it in.

### Launch (Metax)

```bash
./metax/start.sh
```

### Launch (Iluvatar)

```bash
./iluvatar/start.sh
```

### Launch (Moore Threads)

```bash
./mthreads/start.sh
```

### Launch (Kunlunxin)

```bash
./kunlunxin/start.sh
```

### Launch (T-Head)

```bash
./thead/start.sh
```

On the first run the script will:

1. Build `flaggems-{platform}:dev` from the local `Dockerfile` using the FlagOS base image from Harbor
2. Create a detached container with repositories bind-mounted under `/workspace/`
3. Run `setup.sh` inside the container to install oh-my-zsh, zsh plugins, and LazyVim
4. Drop you into an interactive zsh session via `docker exec -it`

On subsequent runs, existing images and containers are reused — no rebuild required.

## start.sh options

All platforms share the same interface:

| Flag | Description |
|------|-------------|
| `-n NAME` / `--name NAME` | Container name (default: `flaggems-{platform}-dev-<username>`) |
| `-f` / `--force` | Force-recreate the container |
| `--rebuild-dev` / `--rebuild` | Force-rebuild the dev image |
| `--repo PATH` | Mount a repository at `/workspace/<name>` (repeatable; default: `../FlagGems`) |
| `-c CMD` / `--cmd CMD` | Command to exec into the container (default: `zsh`) |
| `--ssh-agent` | Use SSH agent forwarding instead of mounting `~/.ssh` |
| `--base-tag VERSION` | FlagOS base image version (default: `2.1.2`) |

The container's working directory is set to the first `--repo` path (or `/workspace/FlagGems` by default).

Examples:

```bash
# Rebuild the dev image and enter the container
./nvidia/start.sh --rebuild

# Mount FlagTree instead of FlagGems
./nvidia/start.sh --repo ../FlagTree

# Mount multiple repos at once (workdir = first repo)
./nvidia/start.sh --repo ../FlagTree --repo ../FlagGems

# Run a specific command instead of dropping into zsh
./nvidia/start.sh -c "python train.py"

# Use a custom container name (useful on shared machines)
./nvidia/start.sh -n my_flaggems_dev
```

## Container environment

| Component | Details |
|-----------|---------|
| Shell | zsh + oh-my-zsh with `zsh-autosuggestions` and `zsh-syntax-highlighting` |
| Editor | Neovim ≥ 0.11 (LazyVim; plugins synced automatically on first launch) |
| Python | `/flagos` virtualenv with FlagGems and its dependencies pre-installed (from the base image) |
| Code quality | `pre-commit`, `flake8`, `black`, `isort`, `clang-format` (NVIDIA and T-Head only) |
| AI tooling | Claude Code CLI (`claude` command), Codex CLI (`codex` command) |
| Utilities | `ripgrep`, `fd`, `gh` (GitHub CLI), passwordless `sudo` |
| Profiling | NVIDIA Nsight Compute (`ncu`), NVIDIA only — installed by `nvidia/start.sh`, see `nvidia/install-nsight-compute.sh` |

The FlagGems source tree is bind-mounted at `/workspace/FlagGems` by default. The container's `$HOME` is mapped to `~/<container-name>/` on the host, so `.claude` config, zsh history, and other user data persist across container restarts.

## Network configuration

`setup.sh` needs outbound access to clone LazyVim, lazy.nvim, and the plugin
set. It clones over HTTPS by default — [GitCode](https://gitcode.com/)
mirrors first, falling back to `github.com` directly — so plain internet
access or an HTTP(S) proxy is enough; no SSH key is required.

**Host behind a proxy (no direct GitHub/GitCode access):** export
`http_proxy`/`https_proxy` before running `start.sh` (e.g. from `~/.bashrc`).
`common/lib.sh` detects them and forwards them into both the image build and
the running container automatically — no other configuration needed.

**Optional SSH fallback:** if HTTPS fails (both the GitCode mirror and the
GitHub fallback), `setup.sh` tries SSH as a last resort, provided the host
has a key whose public half is registered on your GitCode account. Verify
with:

```bash
ssh -T git@gitcode.com
```
## Known limitations (Ascend)

On a shared Ascend host, NPU access inside the container usually works **only as root**. Run workloads with `-u root`:

```bash
docker exec -u root -w /workspace/FlagGems flaggems-ascend-dev-$(id -un) \
    bash -lc 'pytest tests/test_abs.py -vs'
```

As a non-root user, `/dev/davinci*` fails to open with `EBUSY` (errno 16, "Device or resource busy") and `npu-smi info` reports `dcmi model initialized failed ... ret is -8020`. A failure inside PyTorch typically surfaces as `aclInit` error `507899` / `Resource_Busy(EL0005)`.

**This is not a file-permission problem.** `start.sh` already creates the `HwHiAiUser` group with the GID matching the device nodes and adds your user to it. You can confirm the group side is correct:

```bash
docker exec -u $(id -un) <container> id          # expect groups=...,1000(HwHiAiUser)
docker exec -u root <container> stat -c '%n %u:%g %a' /dev/davinci0   # expect 1000:1000 660
```

`EBUSY` means the kernel already allowed the open and the driver then refused it. The Ascend driver grants each card to one namespace at a time (`uda_occupy_dev_by_ns` in the host's `dmesg`, logging `Conflict open udevid`). When another namespace holds a card, the driver only admits a process that is **both** real root **and** holds full capabilities — so adding a user to `HwHiAiUser` cannot help, and neither can granting capabilities to a non-root user.

Consequences for day-to-day use:

- Prefer `docker exec -u root` for anything that touches the NPU. CPU-only work (editing, linting, `pytest` on CPU) needs no special treatment.
- Do **not** remove `--privileged` from `ascend/start.sh` expecting non-root access to start working. Privileged mode is precisely what lets root bypass the namespace check; without it root loses NPU access too.
- Non-root access only becomes possible when the cards assigned to you are not held by another namespace. That requires a host-wide convention — every container launched with `--runtime=ascend -e ASCEND_VISIBLE_DEVICES=<ids>` instead of `--privileged` plus explicit `--device` flags — and so cannot be fixed from this repository alone.
- Clearing stale namespace ownership requires reloading the Ascend kernel modules or rebooting the host, which disrupts every container on the machine. Coordinate with the host administrator.

## SSH configuration

Either SSH forwarding mode works for this fallback:

- **Default (mount `~/.ssh`)**: the host's `~/.ssh` directory is mounted read-only into the container.
- **Agent forwarding (`--ssh-agent`)**: the private key never enters the container; only `SSH_AUTH_SOCK` is forwarded. Requires `ssh-agent` to be running on the host with keys loaded via `ssh-add`.

If none of HTTPS, proxy, or SSH gets through, `setup.sh` skips the nvim/zsh
plugin installation with a warning — the rest of the environment still works
normally.

## Container management

```bash
# List containers
docker ps -a | grep flaggems

# Re-enter a running container
docker exec -it flaggems-nvidia-dev-$(id -un) zsh

# Stop the container
docker stop flaggems-nvidia-dev-$(id -un)

# Remove the container (image is kept)
docker rm flaggems-nvidia-dev-$(id -un)
```
