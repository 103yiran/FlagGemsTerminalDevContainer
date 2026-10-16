# Architecture

This page covers `common/lib.sh`'s build/run pipeline and the `platform_*`
hook contract every launcher relies on, plus what `common/setup.sh` installs
inside a freshly-created container.

## 1. Why run→exec→commit instead of `docker build`

`_build_dev` in `common/lib.sh` builds the dev image by starting a
throwaway container from the FlagOS base image, running the Dockerfile's
layers inside it with `docker exec`, then `docker commit`-ing the result —
rather than calling `docker build` against `Dockerfile` directly. The
comment at the top of `_build_dev` explains why: the host's seccomp profile
blocks container creation *inside* `docker build` (some base images invoke
tools that themselves try to spawn a container), which is a problem `docker
run --security-opt seccomp=unconfined` sidesteps. `Dockerfile` is kept as a
human-readable reference for the same layers, but it is not what actually
gets built from in this environment.

## 2. The six build layers

Each layer runs as one `docker exec` into the throwaway build container
(`flaggems-build-$$`), as root:

1. **uv cache dir, `/flagos` permissions, uv symlink.** Transfers ownership
   of `/flagos` (the pre-built FlagGems venv) and `/usr/local/share/uv` to
   the host user's uid:gid, opens up `/root` and `/root/.local/share/uv/python`
   so the venv's symlinked Python interpreter stays reachable by a non-root
   user, symlinks `uv` onto `/usr/local/bin`, and installs `pytest==8.3.5`
   into the venv.
2. **apt sources → Aliyun mirror.** Rewrites `/etc/apt/sources.list(.d/ubuntu.sources)`
   to use `mirrors.aliyun.com` instead of `archive.ubuntu.com`/`security.ubuntu.com`.
3. **System packages + user creation.** Installs `sudo zsh git curl wget
   unzip ca-certificates ripgrep fd-find gh openssh-client`, plus (NVIDIA
   and T-Head only) `python3-pip clang-format` and the pinned
   `pre-commit==3.7.1 flake8==7.1.0 black==23.7.0 isort==5.12.0` via pip.
   Creates any platform-specific groups returned by `platform_user_groups`
   (see below), then creates the container user with the host's uid/gid and
   passwordless sudo.
4. **Neovim ≥ 0.11.** Skipped if the base image already satisfies the
   version check; otherwise downloads the `LatestRelease` tarball from the
   NJU mirror (`mirror.nju.edu.cn/github-release/neovim/neovim`), retrying up
   to 3 times with bounded `--max-time` (a stalled proxy can leave a TCP
   connection open with zero bytes moving, which plain `--connect-timeout`
   does not catch).
5. **Node.js + Claude Code CLI + Codex CLI.** Downloads the Node 22.23.1
   tarball from `mirrors.aliyun.com/nodejs-release`, then
   `npm install -g @anthropic-ai/claude-code @openai/codex` via
   `registry.npmmirror.com`, with the same retry/timeout treatment (npm does
   not reliably react to `SIGTERM` while blocked on a stalled fetch, so the
   outer `timeout --kill-after=10` follows up with `SIGKILL`).
6. **zsh `/etc/profile.d` sourcing.** Appends a snippet to `/etc/zsh/zshenv`
   so zsh (the default `EXEC_COMMAND`) sources `/etc/profile.d/*.sh` the way
   bash does via `BASH_ENV` — needed for platform vendor scripts like
   Hygon's `vendor.sh`, which sets `LD_LIBRARY_PATH`/`PATH` for DTK.
   Re-prepends `/flagos/bin` afterwards since `vendor.sh` overwrites `PATH`
   outright.

After layer 6, if the platform defined `platform_post_build_exec`, it runs
next (still inside the build container, still as root), then the container
is committed as `flaggems-<platform>:dev` with `ENV UV_CACHE_DIR=...`,
`USER <username>`, `WORKDIR /workspace`, and (NVIDIA only) a `PATH` change
that prepends `/flagos/bin` to whatever the base image already set.

## 3. The `platform_*` hook contract

A launcher customizes the shared pipeline by defining some subset of these
functions *before* sourcing `common/lib.sh`. `common/lib.sh` checks
`declare -f <hook>` before calling each one, so hooks are purely additive —
a platform that doesn't need one simply doesn't define it.

| Hook | Required? | Called from | Purpose |
|------|-----------|--------------|---------|
| `platform_hardware_args` | **Yes** | `_run_container`, before `docker run` | Echoes extra `docker run` flags, one per line (device files, `--privileged`, `--group-add`, ulimits, etc.) for the long-lived dev container. |
| `platform_user_groups` | No | `_build_dev`, layer 3 | Echoes extra group names (or `name:gid` to pin a GID) to create and add the container user to, before `useradd`. Used when the hardware driver gates access by group membership (e.g. Ascend's `HwHiAiUser`, Moore Threads' `render`). |
| `platform_build_args` | No | `_build_dev`, before starting the build container | Echoes extra `docker run` flags for the *throwaway build container* specifically (e.g. Ascend mounts the host driver read-only so `platform_post_build_exec` can bake it into the image). |
| `platform_post_build_exec` | No | `_build_dev`, after layer 6, before `docker commit` | Runs arbitrary `docker exec -u root` commands against the build container right before it's committed. Used for anything that needs to end up baked into the image layer itself — Ascend's driver/dcmi copy-and-chmod, and the cannbot plugin installs (see [Ascend](ascend.md)). |

Three further extension points are not formal hooks, but conventions every
launcher that needs them follows the same way (see [Platforms](platforms.md)
for who uses which):

- **Extra mounts for the *running* container.** A launcher that needs a
  host path mounted at container-run time (not baked into the image)
  defines its own `<PLATFORM>_EXTRA_MOUNTS` array and a `_<platform>_patch_mounts`
  function that prepends it to `REPO_MOUNT_ARGS`, then either wraps
  `_run_container` (Ascend) or wraps `lib_main` itself to call the patch
  function right after `_parse_args` (Hygon, Iluvatar, Moore Threads).
- **Non-default base image naming.** `common/lib.sh` defaults
  `BASE_IMAGE_NAME` to `${BASE_IMAGE_REGISTRY}/flagos-runtime-${PLATFORM}-${TOOLKIT_VERSION}`.
  Platforms whose base image doesn't follow that naming (NVIDIA, T-Head,
  Ascend 910C, Ascend vllm variants) set `BASE_IMAGE_REGISTRY`/`BASE_IMAGE_NAME`/`BASE_IMAGE_TAG`
  themselves *before* sourcing `common/lib.sh`.
- **Post-container-start steps.** A launcher that needs to run something
  once the long-lived container is actually up (not at image-build time)
  wraps `_run_container` the same way NVIDIA does for `install-nsight-compute.sh`,
  or Ascend does for its device-permission and shell-env injection steps.

## 4. `common/setup.sh`: what happens inside a fresh container

`_run_container` copies `common/setup.sh` into the new container and runs it
once, as the container user, right after the container is created. It is
idempotent — re-running it (e.g. by hand) skips anything already installed.

1. **GitHub known_hosts.** Appends GitHub's public host keys to
   `~/.ssh/known_hosts` so an SSH clone attempt (step 3's fallback) never
   stalls on a host-key prompt.
2. **oh-my-zsh + plugins.** Clones `oh-my-zsh`, `zsh-autosuggestions`, and
   `zsh-syntax-highlighting` from `gitee.com/mirrors/*` (no GitHub needed for
   this part), writes the oh-my-zsh `.zshrc` template, uncomments its
   `$HOME/.local/bin` PATH line, and enables the two plugins in `plugins=(...)`.
3. **LazyVim.** Clones the `LazyVim/starter` *template* (not the `LazyVim/LazyVim`
   plugin repo itself, which hangs under `nvim --headless` with an
   interactive gate) into `~/.config/nvim`, trying in order: the
   `gitcode.com/gh_mirrors/sta/starter` HTTPS mirror, `github.com/LazyVim/starter`
   HTTPS, then (only if an SSH key or agent is available) the SSH form of
   either — see `clone_repo()`. It then overwrites `lua/config/lazy.lua` to
   redirect `lazy.nvim`'s own bootstrap and every plugin clone through the
   same gitcode mirror scheme (with a short list of owners, e.g.
   `echasnovski`/`nvim-mini`, routed straight to GitHub since their repos
   are largely absent from the mirror), disables tree-sitter-CLI-dependent
   features, and runs `nvim --headless "+Lazy! sync" +qa` under a 300s
   timeout. A post-sync pass detects any plugin whose `.git` exists but
   whose working tree is empty (a partial-clone checkout failure) and
   recovers it with `git checkout -f HEAD`.
4. **Cursor visibility fix.** Always installs `~/.config/nvim/lua/plugins/cursor-fix.lua`,
   a small LazyVim override that sets a high-contrast cursor color and
   strips the background color Comment highlighting sometimes inherits —
   independent of whether LazyVim itself was freshly cloned.

If every clone attempt in step 3 fails (no GitHub/GitCode reachability and
no usable proxy or SSH key), the LazyVim step is skipped with a warning and
the rest of the script still completes — you get a bare Neovim and a
otherwise fully configured zsh.
