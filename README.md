# FlagGemsTerminalDevContainer

A terminal development container environment for [FlagGems](https://github.com/FlagOpen/FlagGems) contributors, supporting NVIDIA, Hygon, and Cambricon hardware platforms. The container ships with zsh, Neovim (LazyVim), Claude Code, and a full code-quality toolchain out of the box.

[中文文档](README_cn.md)

## Repository layout

```
FlagGemsTerminalDevContainer/
├── Dockerfile            # unified dev image (NVIDIA + Hygon + Cambricon via ARG PLATFORM)
├── common/
│   ├── lib.sh            # shared shell logic (arg parsing, build, run)
│   └── setup.sh          # runs once inside a new container to install zsh/nvim plugins
├── nvidia/
│   └── start.sh          # NVIDIA launcher — sources common/lib.sh
├── hygon/
│   └── start.sh          # Hygon launcher — sources common/lib.sh
└── cambricon/
    └── start.sh          # Cambricon launcher — sources common/lib.sh
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

- NVIDIA platform: NVIDIA Container Toolkit installed on the host
- Hygon platform: `/dev/kfd`, `/dev/dri` devices available on the host and `/opt/hyhal` mounted
- Cambricon platform: `/dev/cambricon_dev*` and `/dev/cambricon_ctl` devices available on the host

## Quick start

```bash
git clone https://github.com/your-org/FlagGemsTerminalDevContainer.git
```

### Launch (NVIDIA)

```bash
./nvidia/start.sh
```

### Launch (Hygon)

```bash
./hygon/start.sh
```

### Launch (Cambricon)

```bash
./cambricon/start.sh
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
| `--base-tag VERSION` | FlagOS base image version (default: `2.1.1`) |

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
| Code quality | `pre-commit`, `flake8`, `black`, `isort`, `clang-format` (NVIDIA only) |
| AI tooling | Claude Code CLI (`claude` command) |
| Utilities | `ripgrep`, `fd`, `gh` (GitHub CLI), passwordless `sudo` |

The FlagGems source tree is bind-mounted at `/workspace/FlagGems` by default. The container's `$HOME` is mapped to `~/<container-name>/` on the host, so `.claude` config, zsh history, and other user data persist across container restarts.

## SSH configuration

`setup.sh` needs SSH access to GitHub to clone LazyVim and zsh plugins.

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
