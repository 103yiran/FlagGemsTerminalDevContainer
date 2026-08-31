#!/bin/bash
# ascend-refresh-env — 容器内使用：更新 CANN 后重新扫描并刷新所有环境配置。
#
# 用法：sudo bash /usr/local/bin/ascend-refresh-env
#
# 刷新范围：
#   /etc/environment           (sudo 时 PAM 注入，需 root)
#   /etc/ld.so.conf.d/ascend.conf + ldconfig  (需 root)
#   ~/.zshrc / ~/.bashrc       (当前用户或 SUDO_USER)

set -euo pipefail
G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; R='\033[0;31m'; N='\033[0m'
info(){ echo -e "${G}[INFO]${N} $*"; }
warn(){ echo -e "${Y}[WARN]${N} $*"; }
step(){ echo -e "${B}[STEP]${N} $*"; }
ok(){  echo -e "${G}[ OK ]${N} $*"; }
err(){ echo -e "${R}[ERR ]${N} $*" >&2; }

# ── Discover best CANN set_env.sh ────────────────────────────────────────────
_find_set_env() {
    local uhome="${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}"
    uhome="${uhome:-$HOME}"
    local f
    # 1. User-installed (highest priority, updated in-container)
    f=$(find "$uhome/Ascend" -maxdepth 5 -name "set_env.sh" 2>/dev/null | head -1)
    [[ -f "$f" ]] && { echo "$f"; return; }
    # 2. Any user home
    f=$(find /home -maxdepth 6 -name "set_env.sh" -path "*/Ascend/*" 2>/dev/null | head -1)
    [[ -f "$f" ]] && { echo "$f"; return; }
    # 3. System toolkit symlink
    [[ -f /usr/local/Ascend/ascend-toolkit/set_env.sh ]] && \
        { echo /usr/local/Ascend/ascend-toolkit/set_env.sh; return; }
    # 4. Version-agnostic search
    f=$(find /usr/local/Ascend -maxdepth 4 -name "set_env.sh" 2>/dev/null \
        | grep -v nnal | head -1)
    [[ -f "$f" ]] && { echo "$f"; return; }
    # 5. Fallback: vendor.sh baked into image
    [[ -f /etc/profile.d/vendor.sh ]] && echo /etc/profile.d/vendor.sh
}

SET_ENV=$(_find_set_env)
[[ -z "$SET_ENV" ]] && { err "No CANN set_env.sh found."; exit 1; }
info "CANN source: $SET_ENV"

ENV_EXPORTS=$(bash -c "source '$SET_ENV' 2>/dev/null; export -p" 2>/dev/null || true)
[[ -z "$ENV_EXPORTS" ]] && { err "source $SET_ENV returned nothing"; exit 1; }

# ── /etc/environment (root only) ─────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
    step "/etc/environment"
    grep -q "^LANG="   /etc/environment 2>/dev/null || echo "LANG=C.UTF-8"   >> /etc/environment
    grep -q "^LC_ALL=" /etc/environment 2>/dev/null || echo "LC_ALL=C.UTF-8" >> /etc/environment
    while IFS= read -r raw; do
        raw="${raw#declare -x }"
        k="${raw%%=*}"
        v="${raw#*=}"; v="${v%\'}"; v="${v#\'}"
        case "$k" in
            PYTHONPATH) continue;;
            ASCEND_*|ATB_*|LD_LIBRARY_PATH|CMAKE_PREFIX_PATH|TOOLCHAIN_HOME)
                if grep -q "^${k}=" /etc/environment 2>/dev/null; then
                    sed -i "s|^${k}=.*|${k}=${v}|" /etc/environment
                else
                    echo "${k}=${v}" >> /etc/environment
                fi;;
        esac
    done < <(echo "$ENV_EXPORTS")
    ok "/etc/environment updated"
else
    warn "Not root — skipping /etc/environment. Re-run with sudo."
fi

# ── ldconfig (root only) ──────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
    step "ldconfig"
    uhome="${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}"
    uhome="${uhome:-$HOME}"
    {
        echo /usr/local/Ascend/driver/lib64
        echo /usr/local/Ascend/driver/lib64/common
        echo /usr/local/Ascend/driver/lib64/driver
        echo /usr/local/dcmi
        find /usr/local/Ascend -maxdepth 3 -name "lib64" -type d 2>/dev/null \
            | grep -v ascend-toolkit | grep -v nnal || true
        for p in /usr/local/Ascend/ascend-toolkit/latest/lib64 \
                 /usr/local/Ascend/ascend-toolkit/latest/lib64/plugin/opskernel \
                 /usr/local/Ascend/ascend-toolkit/latest/lib64/plugin/nnengine; do
            [[ -d "$p" ]] && echo "$p"
        done
        find /usr/local/Ascend/nnal -maxdepth 6 -name "lib" -type d 2>/dev/null || true
        find "$uhome/Ascend" -maxdepth 5 \( -name "lib64" -o -name "lib" \) \
            -type d 2>/dev/null || true
    } | sort -u > /etc/ld.so.conf.d/ascend.conf
    ldconfig
    ok "ldconfig updated"
fi

# ── Shell rc files ────────────────────────────────────────────────────────────
step "Shell rc files"
TARGET_HOME="${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}"
TARGET_HOME="${TARGET_HOME:-$HOME}"
MARKER="# >>> ascend-env (managed by start.sh) >>>"
MARKER_END="# <<< ascend-env <<<"

BLOCK="$MARKER"$'\n'
while IFS= read -r raw; do
    raw="${raw#declare -x }"
    k="${raw%%=*}"
    [[ "$k" == "PYTHONPATH" ]] && continue
    case "$k" in
        ASCEND_*|ATB_*|LD_LIBRARY_PATH|PATH|CMAKE_PREFIX_PATH|TOOLCHAIN_HOME)
            BLOCK+="export $raw"$'\n';;
    esac
done < <(echo "$ENV_EXPORTS")
BLOCK+='export PATH=/flagos/bin:$PATH'$'\n'
BLOCK+="$MARKER_END"

_write_rc() {
    local rc="$1"
    [[ -f "$rc" ]] || touch "$rc"
    if grep -qF "$MARKER" "$rc" 2>/dev/null; then
        python3 - "$rc" "$BLOCK" <<'PY'
import sys, re
p, blk = sys.argv[1], sys.argv[2]
c = open(p).read()
c = re.sub(r'# >>> ascend-env \(managed by start\.sh\) >>>.*?# <<< ascend-env <<<',
           blk, c, flags=re.DOTALL)
open(p,'w').write(c)
PY
    else
        printf '\n%s\n' "$BLOCK" >> "$rc"
    fi
    echo "  updated: $rc"
}

if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
    # Running as root via sudo — write to the original user's rc files
    # and fix ownership afterwards
    _write_rc "$TARGET_HOME/.zshrc"
    _write_rc "$TARGET_HOME/.bashrc"
    chown "${SUDO_USER}:" "$TARGET_HOME/.zshrc" "$TARGET_HOME/.bashrc" 2>/dev/null || true
else
    _write_rc "$HOME/.zshrc"
    _write_rc "$HOME/.bashrc"
fi
ok "Shell rc files updated"

echo ""
info "Done. Changes take effect in new shell sessions."
info "To apply in the current session: source ~/.zshrc  (or ~/.bashrc)"
