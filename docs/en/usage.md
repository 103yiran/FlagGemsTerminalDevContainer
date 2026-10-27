# Usage

## 1. `start.sh` flags

Every launcher shares the same flag set, parsed by `common/lib.sh`'s
`_parse_args`:

| Flag | Description |
|------|-------------|
| `-h` / `--help` | Show help, including the current platform's default container name and base image. |
| `-n NAME` / `--name NAME` | Container name (default: `flaggems-<platform>-dev-<username>`). |
| `-f` / `--force` | Delete and recreate the container (does not touch the image). |
| `--rebuild-dev` / `--rebuild` | Force-rebuild the dev image (equivalent flags). |
| `--repo PATH` | Mount a repository at `/workspace/<basename>`. Repeatable; the working directory is set to the *first* `--repo` path. Default: `../FlagGems` (or `../FlagGems-vllm` for the `ascend-vllm`/`ascend-vllm-910c`/`hygon-vllm`/`nvidia-vllm` launchers). |
| `-c CMD` / `--cmd CMD` | Command to `docker exec` into the container (default: `zsh`). Word-split, so quote multi-word commands: `-c "python train.py"`. |
| `--ssh-agent` | Use SSH agent forwarding instead of mounting `~/.ssh` into the container. |
| `--base-tag VERSION` | Override the FlagOS base image tag. |
| *(positional)* `container_name` | Equivalent to `-n`/`--name`, as a bare positional argument — only valid if `-n` wasn't also given. |

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

## 2. Environment variable overrides

Beyond the flags, a few launcher-level variables can be exported or set
inline before calling `start.sh`:

| Variable | Platforms | Effect |
|----------|-----------|--------|
| `BASE_IMAGE_TAG` | all | Same as `--base-tag`, settable as an env var instead. |
| `TOOLKIT_VERSION` | all except `ascend-vllm*`/`hygon-vllm`/`nvidia-vllm`/`thead` | Overrides the toolkit version baked into the default `flagos-runtime-<platform>-<toolkit>` image name. |
| `BASE_IMAGE_NAME` / `BASE_IMAGE_REGISTRY` | `nvidia`, `nvidia-vllm`, `thead`, `ascend-910c`, `ascend-vllm`, `ascend-vllm-910c`, `hygon-vllm` | Overrides the base image reference entirely, for platforms whose image doesn't follow the `flagos-runtime-<platform>-<toolkit>` naming. |
| `NSIGHT_COMPUTE_VERSION` | `nvidia`, `nvidia-vllm` | Pins/upgrades the Nsight Compute apt package installed after container start — see `nvidia/install-nsight-compute.sh`. |
| `DEV_IMAGE` / `CONTAINER_NAME` | all | Override the computed defaults directly, if you need a name `-n`/`--name` can't express (rare). |

```bash
# Pin a specific Nsight Compute release
NSIGHT_COMPUTE_VERSION=2026.4.0 ./nvidia/start.sh

# Use a different vllm-ascend release tag
BASE_IMAGE_TAG=v0.27.0rc1 ./ascend-vllm/start.sh

# Use a different DCU vllm image tag
BASE_IMAGE_TAG=0.22.0-ubuntu22.04-dtk2604-py3.10 ./hygon-vllm/start.sh
```

## 3. Launching each platform

```bash
./nvidia/start.sh
./hygon/start.sh
./cambricon/start.sh
./ascend/start.sh
./ascend-910c/start.sh
./ascend-vllm/start.sh
./ascend-vllm-910c/start.sh
./hygon-vllm/start.sh
./nvidia-vllm/start.sh
./metax/start.sh
./iluvatar/start.sh
./mthreads/start.sh
./kunlunxin/start.sh
./thead/start.sh
```

On the first run for a given platform, the script will:

1. Build `flaggems-<platform>:dev` from the FlagOS base image (see
   [Architecture §2](architecture.md#2-the-six-build-layers) for the layer
   list).
2. Create a detached container with the repositor(ies) bind-mounted under
   `/workspace/`.
3. Run `common/setup.sh` inside the container to install oh-my-zsh, zsh
   plugins, and LazyVim.
4. Drop you into an interactive zsh session via `docker exec -it`.

On subsequent runs, the existing image and container are reused — no
rebuild, and no re-run of `setup.sh`.

## 4. Container environment

| Component | Details |
|-----------|---------|
| Shell | zsh + oh-my-zsh with `zsh-autosuggestions` and `zsh-syntax-highlighting` |
| Editor | Neovim ≥ 0.11 (LazyVim; plugins synced automatically on first launch) |
| Python | `/flagos` virtualenv with FlagGems and its dependencies pre-installed (from the base image) |
| Code quality | `pre-commit`, `flake8`, `black`, `isort`, `clang-format` (NVIDIA and T-Head only) |
| AI tooling | Claude Code CLI (`claude`), Codex CLI (`codex`), CodeBuddy Code CLI (`codebuddy`); Ascend additionally gets the [cannbot plugins](ascend.md#5-cannbot-plugins) |
| Utilities | `ripgrep`, `fd`, `gh` (GitHub CLI), passwordless `sudo` |
| Profiling | NVIDIA Nsight Compute (`ncu`), NVIDIA only |

The FlagGems source tree is bind-mounted at `/workspace/FlagGems` by
default. The container's `$HOME` is mapped to `~/<container-name>/` on the
host, so `.claude` config, zsh history, and other user data persist across
container restarts and `docker rm`/relaunch cycles (as long as the home
directory itself isn't deleted).

## 5. Network, proxy, and SSH configuration

`common/setup.sh` needs outbound access to clone LazyVim, lazy.nvim, and the
plugin set. It clones over HTTPS by default — [GitCode](https://gitcode.com/)
mirrors first, falling back to `github.com` directly — so plain internet
access or an HTTP(S) proxy is enough; no SSH key is required.

**Host behind a proxy (no direct GitHub/GitCode access):** export
`http_proxy`/`https_proxy` before running `start.sh` (e.g. from
`~/.bashrc`). `common/lib.sh` detects them (`_collect_proxy_args`) and
forwards them into both the image build and the running container
automatically — no other configuration needed.

**Optional SSH fallback:** if HTTPS fails for both the GitCode mirror and
the GitHub fallback, `setup.sh` tries SSH as a last resort, provided the
host has a key whose public half is registered on your GitCode account.
Verify with:

```bash
ssh -T git@gitcode.com
```

**SSH forwarding modes** (either works as this fallback):

- **Default (mount `~/.ssh`)** — the host's `~/.ssh` directory is mounted
  read-only into the container.
- **Agent forwarding (`--ssh-agent`)** — the private key never enters the
  container; only `SSH_AUTH_SOCK` is forwarded. Requires `ssh-agent` running
  on the host with keys loaded via `ssh-add`.

If none of HTTPS, proxy, or SSH gets through, `setup.sh` skips the
nvim/zsh plugin installation with a warning — the rest of the environment
still works normally.

## 6. Container management

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

Removing the container does not remove the dev image or the host-side home
directory (`~/<container-name>/`) — relaunching `start.sh` recreates the
container from the existing image and reattaches the same home directory,
without re-running the Neovim/zsh plugin install.
