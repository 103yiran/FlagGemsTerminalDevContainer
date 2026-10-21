# Overview

## 1. What this repository is

FlagGemsTerminalDevContainer is a set of launcher scripts that spin up a
terminal-based development container for [FlagGems](https://github.com/FlagOpen/FlagGems)
contributors, one per supported hardware platform: NVIDIA, Hygon (plain and
vllm variants), Cambricon, Ascend (four variants), Metax, Iluvatar, Moore
Threads, Kunlunxin, and T-Head. Every platform shares the same container shape — zsh + oh-my-zsh,
Neovim (LazyVim), Claude Code CLI, Codex CLI, and a FlagGems-ready Python
environment — and differs only in which device files, kernel driver, and
toolkit get wired in.

The repository does not define its own Dockerfile build graph at run time.
Instead, `Dockerfile` documents the layers as a reference, and the actual
build is carried out by replaying the equivalent steps inside a running
container (see [Architecture](architecture.md) for why).

## 2. Repository layout

```
FlagGemsTerminalDevContainer/
├── Dockerfile            # reference layer list (ARG PLATFORM branches); not docker-built directly
├── common/
│   ├── lib.sh            # shared shell logic: arg parsing, image build, container run
│   └── setup.sh          # runs once inside a new container: oh-my-zsh, Neovim/LazyVim
├── nvidia/
│   ├── start.sh                    # NVIDIA launcher — sources common/lib.sh
│   └── install-nsight-compute.sh   # installs Nsight Compute (ncu) post-launch
├── hygon/start.sh         # Hygon launcher
├── cambricon/start.sh     # Cambricon launcher
├── ascend/start.sh        # Ascend (910B) launcher
├── ascend-910c/start.sh   # Ascend 910C launcher — same platform logic, 910C base image
├── ascend-vllm/start.sh   # Ascend launcher on the upstream vllm-ascend image
├── ascend-vllm-910c/start.sh  # vllm-ascend image, Atlas A3 (16-device) variant
├── hygon-vllm/start.sh      # Hygon DCU launcher on the upstream vllm image
├── metax/start.sh         # Metax launcher
├── iluvatar/start.sh      # Iluvatar launcher
├── mthreads/start.sh      # Moore Threads launcher
├── kunlunxin/start.sh     # Kunlunxin launcher
└── thead/start.sh         # T-Head launcher
```

Every `<platform>/start.sh` follows the same shape:

1. Set `PLATFORM` and, usually, `TOOLKIT_VERSION`.
2. Define `platform_hardware_args` (required) and, where needed,
   `platform_user_groups`, `platform_build_args`, `platform_post_build_exec`
   (optional hooks — see [Architecture](architecture.md)).
3. `source common/lib.sh`.
4. Call `lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"` — or a thin wrapper around
   it, for platforms that need to inject extra mounts or run a step after the
   container starts.

## 3. Mental model: how a container comes to exist

Running `./nvidia/start.sh` (or any other launcher) does the following, in
order:

1. **Parse arguments** (`_parse_args`) — flags like `-n`, `-f`,
   `--rebuild`, `--repo`, `--base-tag` (full list in [Usage](usage.md)).
2. **Build the dev image if missing** (`_build_dev`) — starts a throwaway
   container from the FlagOS base image, replays the Dockerfile's layers
   inside it via `docker exec`, runs the platform's `platform_post_build_exec`
   hook if defined, then `docker commit`s the result as `flaggems-<platform>:dev`.
   Skipped if the image already exists and `--rebuild`/`--rebuild-dev` wasn't
   passed.
3. **Create or reuse the container** (`_run_container`) — if a container by
   that name doesn't exist yet, `docker run -d` it with the platform's
   hardware flags, bind-mount the repo(s) and the container's home directory,
   then run `common/setup.sh` inside it once to install the zsh/Neovim
   plugin set. If it exists but is stopped, `docker start` it. If it's
   already running, reuse it as-is.
4. **Exec into it** — `docker exec -it` with the requested command
   (`zsh` by default).

On every subsequent run, steps 2 and 3 are no-ops (image and container both
already exist), so re-launching is fast — you land straight in a shell.

## 4. Where to go next

- [Architecture](architecture.md) if you need to understand *why* the build
  works this way, what each of the six build layers does, or what hooks a
  new platform can define.
- [Platforms](platforms.md) for a side-by-side reference of what every
  existing launcher actually passes to `platform_hardware_args` and friends.
- [Ascend](ascend.md) if you're working with any of the four Ascend
  launchers specifically — they carry by far the most platform-specific
  logic in the repository.
- [Usage](usage.md) for day-to-day flags, proxy/SSH setup, and container
  management commands.
- [Contributing](contribution.md) if you're adding a new hardware platform.
