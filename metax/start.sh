#!/usr/bin/env bash
# metax/start.sh — launch the FlagGems Metax development container.
#
# Base image:  harbor.baai.ac.cn/flagos-runtime/flagos-runtime-metax-maca3.8.1.3:2.1.2
#              (toolkit maca3.8.1.3; dev image flaggems-metax:dev)
#
# Options and examples:  ./metax/start.sh --help
# Host requirements: export http_proxy/https_proxy if GitHub/GitCode are
# not directly reachable (common/lib.sh forwards them into the container);
# an SSH key registered on GitCode is an optional extra fallback.
# Full documentation:  common/lib.sh, README.md
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="metax"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-maca3.8.1.3}"

# ── Platform hardware flags ───────────────────────────────────────
platform_hardware_args() {
    cat << 'EOF'
--device=/dev/mxcd
--device=/dev/dri
--group-add=video
EOF
}

# ── Load shared logic and run ─────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"
lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
