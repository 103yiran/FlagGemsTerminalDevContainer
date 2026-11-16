# Ascend

Ascend has five launchers (`ascend/start.sh`, `ascend-910c/start.sh`,
`ascend-vllm/start.sh`, `ascend-vllm-910c/start.sh`,
`ascend-vllm-950dt/start.sh`) and carries by far the most platform-specific
logic in the repository — driver baking, a `HwHiAiUser` permission model
with a real kernel-level gotcha, CANN environment discovery/injection, and
the cannbot-knowledge install. This page covers all five together, since
they share essentially everything except their base image and device count.

## 1. The five variants, and why they exist

| Launcher | Base image | Hardware target | Device range |
|----------|-----------|------------------|---------------|
| `ascend/start.sh` | `flagos-runtime-ascend-cann9.0.0` (FlagOS runtime) | 910B | `/dev/davinci0`–`7` |
| `ascend-910c/start.sh` | `flagos-base-ascend-cann9.0.0-910c` (FlagOS base, 910C-specific) | 910C | `/dev/davinci0`–`7` |
| `ascend-vllm/start.sh` | `vllm-ascend:v0.30.0rc1` (upstream, not FlagOS) | 910B | `/dev/davinci0`–`7` |
| `ascend-vllm-910c/start.sh` | `vllm-ascend:v0.30.0rc1-a3` (upstream `Dockerfile.a3`) | Atlas A3 (910_93) | `/dev/davinci0`–`15` (16 devices) |
| `ascend-vllm-950dt/start.sh` | `vllm-ascend:v0.30.0rc2-a5` (upstream, 950DT build) | 950DT | `/dev/davinci0`–`7` |

All five set `PLATFORM="ascend"` and share identical device-permission,
shell-env-injection, and cannbot-knowledge-install logic — only the base image
reference, the resulting `DEV_IMAGE`/`CONTAINER_NAME`, and (for the `-910c`
Atlas A3 variant) the device count differ. The `-vllm` variants additionally
default to mounting a `../FlagGems-vllm` sibling checkout instead of plain
FlagGems, matching the upstream image's vLLM-tuned Python environment —
override with `--repo` if you want plain FlagGems there too.

## 2. Driver and dcmi baking

The host's Ascend driver files (e.g.
`driver/lib64/common/libaivault.so`) ship with permissions `0400`, owned by
uid 1000 (`HwHiAiUser` on the host), and the immutable (`chattr +i`) flag
set. Even container root cannot `chmod` them, and a bind-mount exposes
those raw host permissions as-is — so any container user whose uid isn't
exactly 1000 gets `EACCES` when `aclInit` tries to `dlopen` the `.so`,
surfacing as Ascend error `507899`.

The fix happens at image-build time, inside `platform_post_build_exec`:

1. `platform_build_args` mounts `/usr/local/Ascend/driver` and
   `/usr/local/dcmi` from the host into the *build* container, read-only.
2. `platform_post_build_exec` copies both into the image layer (`cp -a`,
   not a mount), clears the immutable flag (`chattr -Ri`), and
   `chmod -R a+rX`s them. Because this happens inside a `docker commit`-bound
   container, root owns the copy outright and the chmod actually sticks.
3. At container-run time, the driver is *not* bind-mounted again (that would
   shadow the fixed copy with the original restrictive permissions) —
   only `/usr/local/dcmi` and `/usr/local/sbin/npu-smi` are, since the dcmi
   host files are already world-readable.

The `-vllm` variants additionally `rm -rf` any existing
`/usr/local/Ascend/driver`/`dcmi` before copying, since the vllm-ascend base
image already ships its own CANN/driver install there — the host driver
always wins, since it's the one that actually matches the NPU firmware
running on that machine.

## 3. Why NPU access is usually root-only

On a shared Ascend host, NPU access inside the container typically works
**only as root**:

```bash
docker exec -u root -w /workspace/FlagGems flaggems-ascend-dev-$(id -un) \
    bash -lc 'pytest tests/test_abs.py -vs'
```

As a non-root user, `/dev/davinci*` fails to open with `EBUSY` (errno 16),
`npu-smi info` reports `dcmi model initialized failed ... ret is -8020`, and
inside PyTorch this surfaces as `aclInit` error `507899` /
`Resource_Busy(EL0005)`.

**This is not a file-permission problem.** `start.sh` already creates the
`HwHiAiUser` group with a GID matching the device nodes and adds the
container user to it — you can confirm this side is correct:

```bash
docker exec -u $(id -un) <container> id          # expect groups=...,1000(HwHiAiUser)
docker exec -u root <container> stat -c '%n %u:%g %a' /dev/davinci0   # expect 1000:1000 660
```

`EBUSY` means the kernel allowed the `open()` and the *driver* then refused
it. The Ascend driver grants each card to one namespace at a time
(`uda_occupy_dev_by_ns` in the host's `dmesg`, logging `Conflict open
udevid`). Once another namespace holds a card, the driver only admits a
process that is **both** real root **and** holds full capabilities — adding
a user to `HwHiAiUser`, or granting capabilities to a non-root user, cannot
change that.

Consequences:

- Prefer `docker exec -u root` for anything that touches the NPU. CPU-only
  work (editing, linting, `pytest` on CPU) needs no special treatment.
- Do **not** remove `--privileged` expecting non-root access to start
  working — privileged mode is precisely what lets *root* bypass the
  namespace check; without it, root loses NPU access too.
- Non-root access only becomes possible when the cards assigned to you
  aren't held by another namespace, which requires a host-wide convention
  (every container launched with `--runtime=ascend
  -e ASCEND_VISIBLE_DEVICES=<ids>` instead of `--privileged` + explicit
  `--device` flags) and so cannot be fixed from this repository alone.
- Clearing stale namespace ownership requires reloading the Ascend kernel
  modules or rebooting the host, disrupting every container on the
  machine — coordinate with the host administrator.

## 4. CANN environment discovery and injection

Because `docker exec` skips PAM, `/etc/environment` is never loaded in an
interactive `docker exec` session — so Ascend environment variables
(`ASCEND_HOME_PATH`, `ASCEND_TOOLKIT_HOME`, etc.) are instead injected
directly into `~/.zshrc`/`~/.bashrc`, between managed markers
(`# >>> ascend-env (managed by start.sh) >>>` / `# <<< ascend-env <<<`) so
re-running `start.sh` updates the block in place rather than duplicating it.

The source of truth is discovered dynamically rather than hard-coded to one
CANN version, checked in priority order:

1. A user-installed CANN under `~/Ascend/**/set_env.sh` (newest wins).
2. `/usr/local/Ascend/ascend-toolkit/set_env.sh` (the `latest` symlink).
3. Any other `set_env.sh` under `/usr/local/Ascend` (excluding `nnal`).
4. `/etc/profile.d/vendor.sh`, baked into the base image, as a last resort.

The discovered script is sourced in a clean subshell and its exports are
filtered: `PYTHONPATH` is explicitly dropped (CANN's own Python packages
would otherwise shadow the `/flagos` venv's site-packages and break `import
triton`), while `ASCEND_*`, `ATB_*`, `LD_LIBRARY_PATH`, `PATH`,
`CMAKE_PREFIX_PATH`, and `TOOLCHAIN_HOME` are kept. `/flagos/bin` is
re-prepended to `PATH` at the end of the block so the FlagOS venv's `python3`
still wins.

If CANN gets upgraded inside a running container, re-run the injection
without restarting via the installed helper:

```bash
sudo ascend-refresh-env
```

`sudo` itself also gets configured (a `/etc/sudoers.d/ascend-env` drop-in)
to preserve `PATH`/`LD_LIBRARY_PATH`/`ASCEND_*`/`ATB_*` and disable
`secure_path`, so `sudo python3`/`sudo pytest` keep using the active venv
instead of resetting to the system interpreter. A `sudo-python` wrapper at
`/usr/local/bin/sudo-python` handles the common case of wanting the active
`$VIRTUAL_ENV`'s interpreter specifically under `sudo`.

## 5. cannbot-knowledge

All five Ascend launchers install
[cannbot-knowledge](https://gitcode.com/cann/cannbot-knowledge) — a
searchable, source-traceable CANN domain knowledge base covering operator
development for AscendC/PyPTO/TileLang/Triton, model migration, inference
optimization, and graph-mode/Runtime scenarios. It replaces the old
npm-based `@cannbot-plugin/cannbot` plugin install.

The old cannbot plugin installed globally via `npx` with no dependency on
any project path, so it could live inside `platform_post_build_exec` during
image build (before the repo is ever mounted). cannbot-knowledge's
`install.sh <tool> <project-path> [consumer|contributor]` requires
`<project-path>` to already exist and writes project-scoped files
(`.claude/skills`, a managed block in `CLAUDE.md`, `.agents/skills`,
`.cannbot/knowledge.env`) directly into it — so this step has to run after
the repo is mounted into the container, not at build time. It now lives in
the `_run_container` override (`_ascend_install_cannbot_knowledge`), run
after Ascend environment initialization and before the group-change
restart, on every container start/attach:

```bash
bash install.sh claude <WORKSPACE_DIR> consumer
bash install.sh codex  <WORKSPACE_DIR> consumer
```

where `<WORKSPACE_DIR>` is the path the repo is mounted at inside the
container (`/workspace/FlagGems` by default). The knowledge repo itself is
cloned once into the container user's home at
`~/.cannbot/cannbot-knowledge` (install.sh's own default), which is
bind-mounted to `$HOME/<container-name>` on the host, so it survives
container restarts/recreation — a later run just fast-forwards the existing
clone instead of re-cloning. The install runs as the container user (not
root) in a login shell so `PATH` picks up `/flagos/bin`'s `python3` (>=
3.10) from `_ascend_inject_shell_env`.

`consumer` mode installs three read-only query skills:
`knowledge-query`, `ascendc-api-knowledge-query`, and
`runtime-api-knowledge-query`, for general knowledge search, Ascend C API
lookups, and CANN Runtime API recommendations/comparisons. `contributor`
mode additionally installs `knowledge-ingest`, `knowledge-lint`, and two
operator-extraction skills, for contributing back to the knowledge base;
these launchers only need `consumer`.

A failed install (e.g. a `git clone` network hiccup, or too old a Python)
only logs a warning and is skipped — it does not fail `start.sh`. Rerun it
manually inside the container if needed:

```bash
cd ~/.cannbot/cannbot-knowledge && bash install.sh claude /workspace/FlagGems consumer
```
