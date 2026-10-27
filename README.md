# FlagGemsTerminalDevContainer

A terminal development container environment for [FlagGems](https://github.com/FlagOpen/FlagGems) contributors, supporting NVIDIA, Hygon, Cambricon, Ascend, Metax, Iluvatar, Moore Threads, Kunlunxin, and T-Head hardware platforms. The container ships with zsh, Neovim (LazyVim), Claude Code, Codex, CodeBuddy Code, and a full code-quality toolchain out of the box.

[中文文档](README_cn.md)

This README only covers the quick start. For repository layout, prerequisites
per platform, `start.sh` flags/env vars, the container environment, network
and SSH configuration, Ascend's known limitations, and how to add a new
platform, see **[docs/en](docs/en/_index.md)**.

## Prerequisites

- Docker installed and accessible.
- FlagGems source tree checked out as a sibling of this repository (other
  repos, e.g. `FlagTree`, can be mounted at runtime via `--repo`):

  ```
  parent/
  ├── FlagGems/                      # FlagGems source
  └── FlagGemsTerminalDevContainer/  # this repo
  ```

- Outbound access to GitHub/GitCode (directly, or via an HTTP(S) proxy) to
  install editor/shell plugins on first launch. See
  [docs/en/usage.md §5](docs/en/usage.md#5-network-proxy-and-ssh-configuration)
  for the fallback chain and proxy/SSH setup — no SSH key is required.
- The device files, kernel modules, and groups each platform needs on the
  host — see [docs/en/platforms.md §1–2](docs/en/platforms.md) for the full
  per-platform reference.

## Quick start

```bash
git clone https://github.com/your-org/FlagGemsTerminalDevContainer.git

./nvidia/start.sh      # NVIDIA
./hygon/start.sh        # Hygon
./cambricon/start.sh    # Cambricon
./ascend/start.sh       # Ascend (910B)
./ascend-910c/start.sh  # Ascend 910C
./ascend-vllm/start.sh      # Ascend, vllm-ascend base image
./ascend-vllm-910c/start.sh # Ascend, vllm-ascend base image, Atlas A3
./hygon-vllm/start.sh   # Hygon DCU, vllm base image
./nvidia-vllm/start.sh  # NVIDIA, upstream vllm base image
./metax/start.sh        # Metax
./iluvatar/start.sh     # Iluvatar
./mthreads/start.sh     # Moore Threads
./kunlunxin/start.sh    # Kunlunxin
./thead/start.sh        # T-Head
```

On the first run the script builds the dev image, creates the container with
the repositories bind-mounted under `/workspace/`, installs oh-my-zsh/LazyVim
inside it, then drops you into zsh. Subsequent runs reuse the existing
image/container. See [docs/en/usage.md](docs/en/usage.md) for the full
`start.sh` flag/env-var reference and examples, and
[docs/en/ascend.md](docs/en/ascend.md) for details specific to the four
Ascend launchers (driver baking, the root-only NPU access limitation, CANN
environment injection, cannbot plugins).

## Where to go next

- [docs/en/overview.md](docs/en/overview.md) — what this repository is and
  how a container comes to exist.
- [docs/en/architecture.md](docs/en/architecture.md) — the build pipeline and
  the `platform_*` hook contract.
- [docs/en/platforms.md](docs/en/platforms.md) — per-platform prerequisites,
  base images, and hardware access.
- [docs/en/ascend.md](docs/en/ascend.md) — the four Ascend launchers in
  depth.
- [docs/en/usage.md](docs/en/usage.md) — flags, env vars, container
  environment, network/SSH, and container management.
- [docs/en/contribution.md](docs/en/contribution.md) — how to add a new
  hardware platform.
