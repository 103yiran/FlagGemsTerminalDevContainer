# FlagGemsTerminalDevContainer Documentation

Detailed documentation for contributors who need to understand how this
repository builds and launches FlagGems development containers, not just how
to run `start.sh`. For a quick start, see the top-level [README](../../README.md)
instead — these pages go deeper into the architecture, the per-platform
differences, and how to extend the repository with a new backend.

[中文文档](../zh-cn/_index.md)

## Contents

- [Overview](overview.md) — what this repository is, repository layout, and
  the mental model for how a container comes to exist (`_build_dev` /
  `_run_container`).
- [Architecture](architecture.md) — `common/lib.sh`'s build pipeline
  (run→exec→commit, the six image layers), the `platform_*` hook contract,
  and `common/setup.sh`'s zsh/Neovim bootstrap with its network fallback
  chain.
- [Platforms](platforms.md) — a backend-by-backend reference: base image,
  device files, groups, extra mounts, and hooks used by each of the 13
  launchers.
- [Ascend](ascend.md) — a deeper look at the four Ascend variants
  (`ascend`, `ascend-910c`, `ascend-vllm`, `ascend-vllm-910c`): driver
  baking, the `HwHiAiUser` permission model, the root-only NPU-access
  limitation, and the cannbot plugin install.
- [Usage](usage.md) — `start.sh` flags, environment variable overrides,
  network/proxy/SSH configuration, and container management commands.
- [Contributing](contribution.md) — how to add a new hardware platform
  (minimal launcher vs. one needing extra mounts/groups/hooks), and the
  conventions the existing launchers follow.
