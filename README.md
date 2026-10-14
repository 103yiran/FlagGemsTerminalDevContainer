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
│   └── start.sh          # Ascend launcher — sources common/lib.sh
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

- **SSH key configured on the host and the public key added to [GitCode](https://gitcode.com/).**
  The container needs GitCode SSH access to install the editor and shell
  plugins (LazyVim / lazy.nvim and their dependencies are cloned from
  `gitcode.com` mirrors where available). First verify on the host that key
  based access works:

  ```bash
  ssh -T git@gitcode.com    # should print a welcome message, not "Permission denied"
  ```

  If it fails, add the public key (`~/.ssh/id_ed25519.pub`, `~/.ssh/id_rsa.pub`,
  or `~/.ssh/id_ecdsa.pub`) to your GitCode account under *Settings → SSH
  Public Keys*. Without a usable key, plugin installation is skipped and you
  get a bare nvim / plain zsh instead.

- NVIDIA platform: NVIDIA Container Toolkit installed on the host
- Hygon platform: `/dev/kfd`, `/dev/dri` devices available on the host and `/opt/hyhal` mounted
- Cambricon platform: `/dev/cambricon_dev*` and `/dev/cambricon_ctl` devices available on the host
- Ascend platform: `/dev/davinci0`, `/dev/davinci_manager`, `/dev/devmm_svm`, `/dev/hisi_hdc` devices available on the host; `/usr/local/Ascend/driver`, `/usr/local/dcmi`, and `/usr/local/sbin/npu-smi` present on the host
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
| AI tooling | Claude Code CLI (`claude` command) |
| Utilities | `ripgrep`, `fd`, `gh` (GitHub CLI), passwordless `sudo` |
| Profiling | NVIDIA Nsight Compute (`ncu`), NVIDIA only — installed by `nvidia/start.sh`, see `nvidia/install-nsight-compute.sh` |

The FlagGems source tree is bind-mounted at `/workspace/FlagGems` by default. The container's `$HOME` is mapped to `~/<container-name>/` on the host, so `.claude` config, zsh history, and other user data persist across container restarts.

## SSH configuration

`setup.sh` needs SSH access to clone LazyVim, lazy.nvim, and the plugin set.
Plugins are fetched from [GitCode](https://gitcode.com/) mirrors where they
exist, with a direct fall back to GitHub SSH — so **the host must have an SSH
key whose public half is registered on your GitCode account**. Verify with:

```bash
ssh -T git@gitcode.com
```

Then either forwarding mode works:

- **Default (mount `~/.ssh`)**: the host's `~/.ssh` directory is mounted read-only into the container.
- **Agent forwarding (`--ssh-agent`)**: the private key never enters the container; only `SSH_AUTH_SOCK` is forwarded. Requires `ssh-agent` to be running on the host with keys loaded via `ssh-add`.

If no SSH key is available, `setup.sh` skips the nvim/zsh plugin installation with a warning — the rest of the environment still works normally.

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
