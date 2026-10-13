#!/usr/bin/env bash
# cambricon/start.sh — launch the FlagGems Cambricon development container.
#
# Base image:  harbor.baai.ac.cn/flagos-runtime/flagos-runtime-cambricon-neuware4.7.2:2.1.2
#              (toolkit neuware4.7.2; dev image flaggems-cambricon:dev)
#
# Options, host requirements (an SSH key on the host with its public key
# registered on GitCode) and examples:  ./cambricon/start.sh --help
# Full documentation:  common/lib.sh, README.md
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="cambricon"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-neuware4.7.2}"

# ── Platform hardware flags ───────────────────────────────────────
platform_hardware_args() {
    cat << 'EOF'
--device=/dev/cambricon_dev0
--device=/dev/cambricon_dev1
--device=/dev/cambricon_dev2
--device=/dev/cambricon_dev3
--device=/dev/cambricon_dev4
--device=/dev/cambricon_dev5
--device=/dev/cambricon_dev6
--device=/dev/cambricon_dev7
--device=/dev/cambricon_ctl
EOF
}

# ── Load shared logic and run ─────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"
lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
