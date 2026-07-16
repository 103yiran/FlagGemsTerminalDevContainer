# FlagGemsTerminalDevContainer

A terminal development container environment for [FlagGems](https://github.com/FlagOpen/FlagGems) contributors, supporting both NVIDIA and Hygon hardware platforms. The container ships with zsh, Neovim (LazyVim), Claude Code, and a full code-quality toolchain out of the box.

[中文文档](README_cn.md)

## Repository layout

```
FlagGemsTerminalDevContainer/
├── build-infra/          # submodule — runtime image Dockerfiles
│   └── legacy/
│       ├── flaggems-nvidia-13.3   # NVIDIA CUDA 13.3 runtime Dockerfile
│       └── flaggems-hygon-26.04   # Hygon DTK 26.04 runtime Dockerfile
├── nvidia/
│   ├── Dockerfile        # dev image (dev tools layered on top of runtime)
│   ├── start.sh          # one-shot launch script
│   └── setup.sh          # runs once inside a new container to install zsh/nvim plugins
└── hygon/
    ├── Dockerfile
    ├── start.sh
    └── setup.sh
```

## Prerequisites

- Docker installed and accessible
- FlagGems source tree checked out as a sibling of this repository:

  ```
  parent/
  ├── FlagGems/                      # FlagGems source
  └── FlagGemsTerminalDevContainer/  # this repo
  ```

- NVIDIA platform: NVIDIA Container Toolkit installed on the host
- Hygon platform: `/dev/kfd`, `/dev/dri` devices available on the host and `/opt/hyhal` mounted

## Quick start

### Clone with submodules

```bash
git clone --recurse-submodules https://github.com/your-org/FlagGemsTerminalDevContainer.git
```

If you already cloned without submodules:

```bash
git submodule update --init
```

### Launch (NVIDIA)

```bash
./nvidia/start.sh
```

### Launch (Hygon)

```bash
./hygon/start.sh
```

On the first run the script will:

1. Build `flaggems-{platform}:runtime` from `build-infra/legacy/flaggems-{platform}`
2. Build `flaggems-{platform}:dev` from the local `Dockerfile`
3. Create a detached container with the FlagGems source mounted at `/workspace/FlagGems`
4. Run `setup.sh` inside the container to install oh-my-zsh, zsh plugins, and LazyVim
5. Drop you into an interactive zsh session via `docker exec -it`

On subsequent runs, existing images and containers are reused — no rebuild required.

## start.sh options

Both platforms share the same interface:

| Flag | Description |
|------|-------------|
| `-n NAME` / `--name NAME` | Container name (default: `flaggems-{platform}-dev-<username>`) |
| `-f` / `--force` | Force-recreate the container |
| `--rebuild-runtime` | Force-rebuild the runtime image |
| `--rebuild-dev` | Force-rebuild the dev image |
| `--rebuild` | Force-rebuild both images |
| `-c CMD` / `--cmd CMD` | Command to exec into the container (default: `zsh`) |
| `--ssh-agent` | Use SSH agent forwarding instead of mounting `~/.ssh` (NVIDIA only) |

Examples:

```bash
# Rebuild everything and enter the container
./nvidia/start.sh --rebuild

# Rebuild only the dev image (faster — skips the runtime build)
./nvidia/start.sh --rebuild-dev

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
| Python | `/flagos` virtualenv with FlagGems and its dependencies pre-installed (from the runtime image) |
| Code quality | `pre-commit`, `flake8`, `black`, `isort`, `clang-format` (NVIDIA image) |
| AI tooling | Claude Code CLI (`claude` command) |
| Utilities | `ripgrep`, `fd`, `gh` (GitHub CLI), passwordless `sudo` |

The FlagGems source tree is bind-mounted at `/workspace/FlagGems`, so edits on the host are immediately visible inside the container.

The container's `$HOME` is mapped to `~/<container-name>/` on the host, so `.claude` config, zsh history, and other user data persist across container restarts.

## SSH configuration

`setup.sh` needs SSH access to GitHub to clone LazyVim and zsh plugins.

- **Default (mount `~/.ssh`)**: the host's `~/.ssh` directory is mounted read-only into the container so keys are available as files.
- **Agent forwarding (`--ssh-agent`, NVIDIA only)**: the private key never enters the container; only `SSH_AUTH_SOCK` is forwarded. Requires `ssh-agent` to be running on the host with keys loaded via `ssh-add`.

If no SSH key is available, `setup.sh` skips the nvim/zsh plugin installation with a warning — the rest of the environment still works normally.

## Container management

```bash
# List containers
docker ps -a | grep flaggems

# Re-enter a running container
docker exec -it flaggems-nvidia-dev-$(id -un) zsh

# Stop the container
docker stop flaggems-nvidia-dev-$(id -un)

# Remove the container (images are kept)
docker rm flaggems-nvidia-dev-$(id -un)
```

## How the images are built

The runtime image Dockerfile is sourced from the [build-infra](https://gitcode.com/flagos-ai/build-infra.git) submodule (`legacy/` directory). The FlagGems source tree is used as the Docker build context, producing a runtime image that contains a `/flagos` virtualenv with FlagGems installed.

The dev image layers on top of the runtime image: development tools (zsh, nvim, gh, etc.), a non-root user whose uid/gid match the host user, the Claude Code CLI, and a permission fix that allows the non-root user to write into the `/flagos` venv.
