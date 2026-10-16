# Contributing

## 1. Adding a new hardware platform

The minimal launcher needs three things — a `PLATFORM` identity, a
`platform_hardware_args` function, and a `source` + `lib_main` call. Start
from the simplest existing example, `cambricon/start.sh`:

```bash
#!/usr/bin/env bash
# <platform>/start.sh — launch the FlagGems <Platform> development container.
#
# Base image:  <registry>/<base-image>:<tag>
#              (toolkit <toolkit>; dev image flaggems-<platform>:dev)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

PLATFORM="<platform>"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-<toolkit>}"

platform_hardware_args() {
    cat << 'EOF'
--device=/dev/<devfile0>
--device=/dev/<devfile1>
EOF
}

source "${REPO_ROOT}/common/lib.sh"
lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
```

From there, add only the hooks your platform actually needs — don't define
a hook that just echoes nothing. See [Architecture §3](architecture.md#3-the-platform_-hook-contract)
for the full contract and [Platforms](platforms.md) for how each existing
launcher used it:

- **Need a group the driver gates on?** Add `platform_user_groups`,
  echoing `name` or `name:gid` (one per line) — see `mthreads/start.sh`
  for the GID-pinning pattern (`getent group render | cut -d: -f3`).
- **Need a host path mounted into the *build* container** (to bake
  something into the image, like Ascend's driver)**?** Add
  `platform_build_args`, and pair it with `platform_post_build_exec` to
  actually do the copy/chmod before commit.
- **Need a host path mounted into the *running* container, every launch?**
  Define a `<PLATFORM>_EXTRA_MOUNTS` array and a `_<platform>_patch_mounts`
  function, then wrap `lib_main` the way `hygon/start.sh`,
  `iluvatar/start.sh`, and `mthreads/start.sh` do — copy their wrapper
  verbatim and swap in your own patch function call. Don't reinvent the
  wrapper; keeping its shape identical across platforms is what makes a
  future `common/lib.sh` refactor (e.g. a formal `platform_extra_mounts`
  hook) a mechanical find-and-replace instead of auditing N bespoke
  wrappers.
- **Need something to run only once the container is actually started**
  (not at image-build time)**?** Wrap `_run_container` the way
  `nvidia/start.sh` does for `install-nsight-compute.sh` — use
  `eval "_orig_run_container() $(declare -f _run_container | tail -n +2)"`
  to copy the function body, not a name alias (aliasing by name causes
  infinite recursion, since bash resolves the name at call time).
- **Base image doesn't follow `flagos-runtime-<platform>-<toolkit>`
  naming?** Set `BASE_IMAGE_REGISTRY`/`BASE_IMAGE_NAME`/`BASE_IMAGE_TAG`
  yourself before sourcing `common/lib.sh` — see `thead/start.sh` or
  `ascend-910c/start.sh`.

After adding or changing a launcher, update:

- `Dockerfile`'s header comment listing `PLATFORM=` options, and its
  `ARG PLATFORM` branches if the platform needs its own apt/pip packages in
  build layer 3.
- `README.md` / `README_cn.md` — the repository layout tree, the
  prerequisites list (device files required on the host), and a `### Launch
  (<Platform>)` entry.
- `docs/en/platforms.md` / `docs/zh-cn/platforms.md` — add a row to both
  tables.

## 2. Testing a launcher change

There's no automated test suite for the launchers themselves (they're thin
wrappers around `docker` invocations) — verify by hand:

```bash
# Force a full rebuild to catch build-layer regressions
./<platform>/start.sh --rebuild-dev -f

# Confirm the container summary shows the expected image/mounts
# (printed automatically by _print_summary before you're exec'd in)

# From inside the container, sanity-check the toolchain:
python3 -c "import torch; print(torch.__version__)"
claude --version
codex --version
```

If your change affects `common/lib.sh` or `common/setup.sh` directly, test
against at least two platforms (one FlagOS-runtime-based, one with a
non-standard base image like `nvidia` or `thead`) since those are the two
code paths most likely to diverge.

## 3. Style conventions

- Comments explain *why*, not *what* — see almost any function in
  `common/lib.sh` or `ascend/start.sh` for the expected density. A one-line
  `# fetch the driver` above an obvious `cp` isn't useful; a paragraph
  explaining *why* a bind-mount would break permissions is.
- Prefer extending the existing hook/wrapper patterns described above over
  inventing a new mechanism for a single platform — a platform-specific
  one-off is harder for the next contributor to find than a hook that's
  already documented and used elsewhere.
- Keep `common/lib.sh` platform-agnostic. Anything that only one or two
  platforms need belongs in that platform's `start.sh`, gated behind a hook,
  not behind an `if [[ "$PLATFORM" == ... ]]` branch inside `common/lib.sh`
  itself — the one existing exception (`nvidia`'s `PATH` prepend in
  `_build_dev`'s commit step) is called out in a comment precisely because
  it's an exception.
