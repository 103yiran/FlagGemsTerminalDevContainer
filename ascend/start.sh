#!/usr/bin/env bash
# ascend/start.sh — launch the FlagGems Ascend development container.
#
# Step 1: build (or skip) flaggems-ascend:dev from root Dockerfile
#         using harbor.baai.ac.cn/flagos-runtime/flagos-runtime-ascend-cann9.0.0 as base
# Step 2: start container with -itd (detached), then exec into it
#
# SSH key forwarding (applied at container creation, pick one):
#   ~/.ssh dir mount  — default; keys available as files (read-only)
#   SSH agent forward — private key never leaves the host; requires
#                       ssh-agent running with keys loaded on the host
#
# Usage:
#   ./ascend/start.sh                         # default container name, mounts FlagGems
#   ./ascend/start.sh -n my_container         # custom container name
#   ./ascend/start.sh -f                      # force-recreate container
#   ./ascend/start.sh --rebuild-dev           # force-rebuild dev image
#   ./ascend/start.sh --rebuild               # force-rebuild dev image
#   ./ascend/start.sh --ssh-agent             # use SSH agent forwarding instead
#   ./ascend/start.sh -c "python a.py"        # exec command (default: zsh)
#   ./ascend/start.sh --repo ../FlagTree      # mount FlagTree instead of FlagGems
#   ./ascend/start.sh --repo ../A --repo ../B # mount multiple repos
#   ./ascend/start.sh --base-tag 2.1.2        # use FlagOS base image version 2.1.2
#
# See common/lib.sh for full option documentation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FLAGGEMS_ROOT="$(cd "$SCRIPT_DIR/../../FlagGems" && pwd)"

# ── Platform identity ─────────────────────────────────────────────
PLATFORM="ascend"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-cann9.0.0}"

# ── Platform hardware flags ───────────────────────────────────────
platform_hardware_args() {
    # Use privileged mode for Ascend NPU access
    # This is required to avoid DCMI conflicts with host services like npu-exporter
    # Use host PID namespace to avoid driver namespace conflicts
    cat << EOF
--privileged
--pid=host
--security-opt label=disable
EOF

    # Explicitly mount Ascend device files so the kernel driver registers this
    # container's namespace (owned by root, see --user=root in _run_container).
    # Without explicit --device flags, /dev/devmm_svm and /dev/hisi_hdc are
    # absent inside the container, which breaks both torch_npu and npu-smi.
    for dev in \
        /dev/davinci0 /dev/davinci1 /dev/davinci2 /dev/davinci3 \
        /dev/davinci4 /dev/davinci5 /dev/davinci6 /dev/davinci7 \
        /dev/davinci_manager /dev/devmm_svm /dev/hisi_hdc
    do
        [[ -e "$dev" ]] && echo "--device=${dev}"
    done
}

# ── Platform extra mounts ─────────────────────────────────────────
# Ascend only needs npu-smi and dcmi from the host at runtime.
# The driver is baked into the dev image during _build_dev (see
# platform_post_build_exec below) so it is not bind-mounted here —
# bind-mounting would shadow the image copy and re-expose the immutable
# host files that non-root users cannot read.
ASCEND_EXTRA_MOUNTS=(
    -v /usr/local/dcmi:/usr/local/dcmi
    -v /usr/local/sbin/npu-smi:/usr/local/sbin/npu-smi
)

# ── Platform user groups ──────────────────────────────────────────
# Groups to add the user to during creation (HwHiAiUser is required for NPU access).
# This function will be called by common/lib.sh during user creation.
platform_user_groups() {
    echo "HwHiAiUser"
}

# ── Platform build-container extra args ──────────────────────────
# Mount the host driver read-only into the build container so
# platform_post_build_exec can copy it into the image layer.
platform_build_args() {
    [[ -d /usr/local/Ascend/driver ]] && echo "-v /usr/local/Ascend/driver:/tmp/host-ascend-driver:ro" || true
    [[ -d /usr/local/dcmi          ]] && echo "-v /usr/local/dcmi:/tmp/host-dcmi:ro"                   || true
}

# ── Platform post-build hook ──────────────────────────────────────
# Copy the Ascend driver and dcmi from the host into the image, then
# fix permissions so non-root users can read the .so files.
#
# WHY this is necessary:
#   The host driver files (e.g. driver/lib64/common/libaivault.so) have
#   permissions 0400 and owner uid=1000 (HwHiAiUser user), plus chattr +i
#   (immutable).  Even container root cannot chmod them.  A bind-mount
#   exposes those raw host permissions inside the container, so any user
#   with uid != 1000 gets EACCES when aclInit tries to dlopen the .so,
#   yielding error 507899.
#
#   By copying the files into the image layer during build (where root has
#   full ownership of the copy) and running chmod a+rX, the resulting image
#   has world-readable driver libs.  At runtime we no longer bind-mount
#   /usr/local/Ascend/driver, so the fixed copy is what the container sees.
platform_post_build_exec() {
    local _ctr="$1"

    if [[ -d /usr/local/Ascend/driver ]]; then
        print_step "将 Ascend driver 烘焙进镜像并修复权限..."
        docker exec -u root "$_ctr" bash -c '
            set -e
            cp -a /tmp/host-ascend-driver /usr/local/Ascend/driver
            # Remove immutable flag if present (chattr +i from the host copy)
            chattr -Ri /usr/local/Ascend/driver 2>/dev/null || true
            chmod -R a+rX /usr/local/Ascend/driver
            echo "driver baked: $(du -sh /usr/local/Ascend/driver | cut -f1)"
        '
    fi

    if [[ -d /usr/local/dcmi ]]; then
        print_step "将 dcmi 烘焙进镜像并修复权限..."
        docker exec -u root "$_ctr" bash -c '
            set -e
            cp -a /tmp/host-dcmi /usr/local/dcmi
            chattr -Ri /usr/local/dcmi 2>/dev/null || true
            chmod -R a+rX /usr/local/dcmi
        '
    fi
}

# ── Platform environment variables ────────────────────────────────
# Pass driver LD_LIBRARY_PATH at container creation time so it is available
# in every docker exec session (docker exec skips PAM, so /etc/environment
# is never loaded).  ASCEND_HOME_PATH and other CANN vars are version-specific
# paths that live in vendor.sh inside the image; we inject them into the
# user's shell rc at setup time (see _ascend_inject_shell_env below) so they
# survive across sessions without hard-coding a version string here.
ASCEND_ENV_VARS=(
    -e LD_LIBRARY_PATH=/usr/local/Ascend/driver/lib64:/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/driver:/usr/local/dcmi:\${LD_LIBRARY_PATH}
)

# Override _run_container to inject the extra mounts before calling the base.
# We patch REPO_MOUNT_ARGS after parsing so lib_main picks it up transparently.
_ascend_patch_mounts() {
    REPO_MOUNT_ARGS=("${ASCEND_EXTRA_MOUNTS[@]}" "${ASCEND_ENV_VARS[@]}" "${REPO_MOUNT_ARGS[@]}")
}

# Configure Ascend NPU device access for a non-root user.
#
# HwHiAiUser group: The NPU kernel driver checks group membership by name.
# The FlagOS base image ships GID 1000 as 'ubuntu', not 'HwHiAiUser'.
# We create a second entry for GID 1000 named HwHiAiUser (groupadd -o
# permits duplicate GIDs) and add the user to it.
#
# /root permissions: The uv Python virtual environment at /flagos uses symlinks
# into /root/.local/share/uv/python/. We set /root to 755 and /root/.local to
# o+rX so non-root users can traverse to the Python interpreter.
#
# driver permissions: The driver is baked into the image by platform_post_build_exec
# with a+rX, so no runtime chmod is needed here.
#
# dcmi permissions: /usr/local/dcmi is still bind-mounted from the host (dcmi
# is also baked but the mount shadows it — see below for the chmod).  The host
# dcmi files have permissive permissions (r--r--r-- root:root) so no fix is
# needed for dcmi either; but we chmod o+rX defensively.
#
# This grants the user access to /dev/davinci[0-7] for training workloads
# (torch_npu, etc). npu-smi (monitoring tool) uses /dev/davinci_manager
# via DCMI and will fail with -8020 when npu-exporter holds the DCMI lock;
# use `sudo npu-smi` or `docker exec -u root` for monitoring if needed.
_ascend_setup_device_permissions() {
    local _username="$(id -un)"
    local _hw_gid
    _hw_gid=$(stat -c '%g' /dev/davinci0 2>/dev/null || true)

    if [[ -z "$_hw_gid" ]]; then
        print_warn "未找到 /dev/davinci0，跳过 Ascend 权限配置"
        return
    fi

    print_step "配置 Ascend 设备访问权限 (HwHiAiUser GID=${_hw_gid})..."

    docker exec -u root "${CONTAINER_NAME}" bash -c "
        set -e
        # Ascend driver checks group membership by name 'HwHiAiUser', not GID.
        # Ensure HwHiAiUser group exists with the correct GID matching the device.

        # If GID ${_hw_gid} is already used by 'ubuntu' group, move it to avoid conflict.
        if getent group ubuntu | grep -q ':${_hw_gid}:'; then
            # Find next available GID
            new_gid=\$(( ${_hw_gid} + 1 ))
            while getent group \$new_gid >/dev/null 2>&1; do
                new_gid=\$(( new_gid + 1 ))
            done
            groupmod -g \$new_gid ubuntu 2>/dev/null || true
        fi

        # Update HwHiAiUser GID if it exists with wrong GID
        if getent group HwHiAiUser >/dev/null 2>&1; then
            current_gid=\$(getent group HwHiAiUser | cut -d: -f3)
            if [ \"\$current_gid\" != \"${_hw_gid}\" ]; then
                groupmod -g ${_hw_gid} HwHiAiUser
            fi
        else
            # Create HwHiAiUser group if it doesn't exist
            groupadd -g ${_hw_gid} HwHiAiUser
        fi

        # Ensure the user is in the HwHiAiUser group (idempotent)
        if ! id -nG '${_username}' | grep -qw HwHiAiUser; then
            usermod -aG HwHiAiUser '${_username}'
        fi

        # Make Ascend device files group-accessible so non-root members of
        # HwHiAiUser can open them. The kernel driver sets these to mode 0600
        # (owner root) on some hosts; group-read/write is required for NPU access.
        for dev in /dev/davinci0 /dev/davinci1 /dev/davinci2 /dev/davinci3 \
                   /dev/davinci4 /dev/davinci5 /dev/davinci6 /dev/davinci7 \
                   /dev/davinci_manager /dev/devmm_svm /dev/hisi_hdc; do
            [[ -e \"\$dev\" ]] && chmod g+rw \"\$dev\" 2>/dev/null || true
        done

        # Fix /root permissions for uv virtual environment access
        chmod 755 /root 2>/dev/null || true
        chmod -R o+rX /root/.local 2>/dev/null || true

        # /usr/local/dcmi is bind-mounted; chmod defensively (files are typically
        # already r--r--r-- on most hosts, but be safe).
        chmod -R o+rX /usr/local/dcmi 2>/dev/null || true
    "
    print_success "已配置用户 ${_username} 的 Ascend 设备访问权限 (HwHiAiUser GID=${_hw_gid})"

    # ── sudo environment configuration ────────────────────────────────
    # sudo resets PATH (via secure_path) and strips LD_LIBRARY_PATH (hardcoded
    # in its unsafe-env list). Fix both:
    #   1. !secure_path + env_keep PATH  → virtual-env python3 survives sudo
    #   2. /etc/environment LD_LIBRARY_PATH → PAM injects it before sudo resets env,
    #      so Ascend .so files are found without any wrapper tricks
    print_step "配置 sudo 环境变量保留..."
    # Write the setup script to a temp file on the host, copy it into the
    # container, then execute it as root.  Using a file avoids the stdin
    # limitation of `docker exec ... bash << 'EOF'` (docker exec does not
    # connect the host's stdin to the container process).
    local _sudo_setup
    _sudo_setup=$(mktemp /tmp/ascend_sudo_setup.XXXXXX.sh)
    cat > "${_sudo_setup}" << 'SCRIPT_EOF'
#!/bin/bash
set -e

# sudoers drop-in: disable secure_path so the venv python3 survives sudo,
# and preserve key env vars.  LANG/LD_LIBRARY_PATH/ASCEND_* come in via
# /etc/environment (PAM), so env_keep is a belt-and-suspenders extra.
cat > /etc/sudoers.d/ascend-env << 'SUDOERS'
# Disable secure_path so the active virtual environment PATH is preserved
Defaults !secure_path

# Preserve user environment variables across sudo
Defaults env_keep += "PATH VIRTUAL_ENV PYTHONPATH"
Defaults env_keep += "ASCEND_HOME_PATH ASCEND_TOOLKIT_HOME ASCEND_OPP_PATH ASCEND_AICPU_PATH"
Defaults env_keep += "TOOLCHAIN_HOME CMAKE_PREFIX_PATH"
Defaults env_keep += "LANG LC_ALL LC_CTYPE LANGUAGE"
SUDOERS
chmod 440 /etc/sudoers.d/ascend-env
visudo -c -f /etc/sudoers.d/ascend-env

# /etc/environment is read by PAM before sudo resets the environment, so
# values written here survive even though sudo strips them from the inherited
# env.  This is critical for zsh users: zsh non-login shells never source
# /etc/profile.d/vendor.sh (unlike bash), so ASCEND_HOME_PATH would be absent
# and torch_npu._C._get_cann_version would fall back to a binary file and
# raise UnicodeDecodeError.
grep -q "^LANG="   /etc/environment 2>/dev/null || echo "LANG=C.UTF-8"   >> /etc/environment
grep -q "^LC_ALL=" /etc/environment 2>/dev/null || echo "LC_ALL=C.UTF-8" >> /etc/environment

if ! grep -q "^LD_LIBRARY_PATH=" /etc/environment 2>/dev/null; then
    ld_path=$(grep "^export LD_LIBRARY_PATH=" /etc/profile.d/vendor.sh 2>/dev/null \
              | sed "s/export LD_LIBRARY_PATH=//;s/'//g" | head -1)
    [[ -n "$ld_path" ]] && echo "LD_LIBRARY_PATH=\"${ld_path}\"" >> /etc/environment
fi

grep "^export ASCEND" /etc/profile.d/vendor.sh 2>/dev/null \
    | sed "s/^export //;s/'//g" \
    | while IFS= read -r line; do
        key="${line%%=*}"
        grep -q "^${key}=" /etc/environment 2>/dev/null || echo "$line" >> /etc/environment
    done
SCRIPT_EOF

    docker cp "${_sudo_setup}" "${CONTAINER_NAME}:/tmp/ascend_sudo_setup.sh"
    docker exec -u root "${CONTAINER_NAME}" bash /tmp/ascend_sudo_setup.sh
    docker exec -u root "${CONTAINER_NAME}" rm -f /tmp/ascend_sudo_setup.sh
    rm -f "${_sudo_setup}"
    print_success "sudo 环境配置完成（PATH、LD_LIBRARY_PATH、ASCEND_* 已保留）"

    # ── ldconfig for capabilities-enabled Python ──────────────────────
    # When Python has file capabilities (CAP_SYS_ADMIN), the dynamic linker
    # ignores LD_LIBRARY_PATH for security. Add Ascend libraries to the
    # system cache so they're found without LD_LIBRARY_PATH.
    # Paths are discovered dynamically so the config survives CANN version changes.
    print_step "配置系统库缓存 (ldconfig)..."
    docker exec -u root "${CONTAINER_NAME}" bash -c '
        {
            # Driver libs (bind-mount from host, always fixed paths)
            echo /usr/local/Ascend/driver/lib64
            echo /usr/local/Ascend/driver/lib64/common
            echo /usr/local/Ascend/driver/lib64/driver
            echo /usr/local/dcmi

            # CANN versioned lib64 — discover actual version directories
            find /usr/local/Ascend -maxdepth 3 -name "lib64" -type d 2>/dev/null \
                | grep -v ascend-toolkit | grep -v nnal || true

            # ascend-toolkit via the "latest" symlink
            for p in \
                /usr/local/Ascend/ascend-toolkit/latest/lib64 \
                /usr/local/Ascend/ascend-toolkit/latest/lib64/plugin/opskernel \
                /usr/local/Ascend/ascend-toolkit/latest/lib64/plugin/nnengine
            do
                [[ -d "$p" ]] && echo "$p" || true
            done

            # ATB lib (cxx_abi_1 or cxx_abi_0)
            find /usr/local/Ascend/nnal -maxdepth 6 -name "lib" -type d 2>/dev/null || true
        } | sort -u > /etc/ld.so.conf.d/ascend.conf
        ldconfig
    '
    print_success "系统库缓存已更新"
}

# Inject ASCEND_* environment variables from vendor.sh into the user's shell
# rc files (~/.zshrc and ~/.bashrc) inside the container.
#
# Why not source vendor.sh wholesale?
#   vendor.sh sets PYTHONPATH to CANN's own Python packages, which shadows
#   /flagos site-packages and breaks `import triton` and other packages
#   installed in the FlagOS venv.  We cherry-pick only the vars that
#   torch_npu needs (ASCEND_HOME_PATH, ASCEND_TOOLKIT_HOME, ASCEND_OPP_PATH,
#   ASCEND_AICPU_PATH) plus PATH additions, and leave PYTHONPATH alone.
#
# Why not use /etc/environment?
#   docker exec skips PAM, so /etc/environment is never loaded in interactive
#   sessions started via `docker exec`.  Shell rc files are the only reliable
#   mechanism.
_ascend_inject_shell_env() {
    local _username="$(id -un)"
    print_step "注入 Ascend 环境变量到用户 shell rc..."

    local _inject_script
    _inject_script=$(mktemp /tmp/ascend_inject_env.XXXXXX.sh)
    cat > "${_inject_script}" << 'SCRIPT_EOF'
#!/bin/bash
set -e

VENDOR="/etc/profile.d/vendor.sh"
MARKER="# >>> ascend-env (managed by start.sh) >>>"
MARKER_END="# <<< ascend-env <<<"

if [[ ! -f "$VENDOR" ]]; then
    echo "[WARN] $VENDOR not found, skipping shell env injection" >&2
    exit 0
fi

# Build the block to inject: export every ASCEND_* var from vendor.sh,
# plus PATH additions, but skip PYTHONPATH (it shadows /flagos venv packages).
ENV_BLOCK="$MARKER"$'\n'
while IFS= read -r line; do
    # Skip PYTHONPATH — it prepends CANN's site-packages and breaks /flagos venv
    [[ "$line" =~ ^export\ PYTHONPATH= ]] && continue
    # Include ASCEND_*, ATB_*, PATH, LD_LIBRARY_PATH, CMAKE_PREFIX_PATH, TOOLCHAIN_HOME
    if [[ "$line" =~ ^export\ (ASCEND_|ATB_|PATH=|LD_LIBRARY_PATH=|CMAKE_PREFIX_PATH=|TOOLCHAIN_HOME=) ]]; then
        ENV_BLOCK+="$line"$'\n'
    fi
done < <(grep "^export " "$VENDOR")
# Ensure /flagos/bin leads PATH so `python3` resolves to the FlagOS venv
# interpreter rather than the system one (/usr/bin/python3).
ENV_BLOCK+='export PATH=/flagos/bin:$PATH'$'\n'
ENV_BLOCK+="$MARKER_END"

# Write the block into ~/.zshrc and ~/.bashrc (idempotent: replace if exists)
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [[ -f "$rc" ]] || touch "$rc"
    if grep -qF "$MARKER" "$rc" 2>/dev/null; then
        # Replace existing block
        python3 - "$rc" "$ENV_BLOCK" << 'PYEOF'
import sys, re
rc_path, block = sys.argv[1], sys.argv[2]
content = open(rc_path).read()
pattern = r'# >>> ascend-env \(managed by start\.sh\) >>>.*?# <<< ascend-env <<<'
new_content = re.sub(pattern, block, content, flags=re.DOTALL)
open(rc_path, 'w').write(new_content)
PYEOF
    else
        printf '\n%s\n' "$ENV_BLOCK" >> "$rc"
    fi
done

echo "[OK] Ascend env injected into ~/.zshrc and ~/.bashrc"
SCRIPT_EOF

    docker cp "${_inject_script}" "${CONTAINER_NAME}:/tmp/ascend_inject_env.sh"
    docker exec -u "${_username}" "${CONTAINER_NAME}" bash /tmp/ascend_inject_env.sh
    docker exec -u root "${CONTAINER_NAME}" rm -f /tmp/ascend_inject_env.sh
    rm -f "${_inject_script}"
    print_success "Ascend 环境变量已注入用户 shell rc（PYTHONPATH 已排除以保护 /flagos venv）"
}

# ── Load shared logic ─────────────────────────────────────────────
# shellcheck source=../common/lib.sh
source "${REPO_ROOT}/common/lib.sh"

# Wrap lib_main to inject the extra mounts after arg parsing.
# _parse_args populates REPO_MOUNT_ARGS; we extend it before _run_container.
#
# Use `declare -f` to copy the *body* of lib.sh's _run_container, not just a
# name alias.  Aliasing by name causes infinite recursion because bash resolves
# function names at call time, so _orig_run_container would always call the new
# wrapper instead of the original implementation.
eval "_orig_run_container() $(declare -f _run_container | tail -n +2)"
_run_container() {
    _ascend_patch_mounts

    # Record whether the container already existed and was running before we call
    # _orig_run_container.  We only want to restart (for group-change propagation)
    # when the container was just freshly created, not when a peer is already
    # connected — a docker restart would kill every active `docker exec` session
    # in other terminal windows.
    local _was_running=false
    container_running && _was_running=true

    _orig_run_container "$@"

    # Setup device permissions after container is created
    if container_running; then
        _ascend_setup_device_permissions
        _ascend_inject_shell_env

        # Initialize Ascend environment (critical for DCMI to work)
        print_step "初始化 Ascend 运行环境..."
        docker exec "${CONTAINER_NAME}" bash -c '
            # Source set_env.sh from whichever CANN version is installed,
            # without hard-coding the version string.
            for f in \
                /usr/local/Ascend/ascend-toolkit/set_env.sh \
                /usr/local/Ascend/nnal/atb/set_env.sh \
                $(find /usr/local/Ascend -maxdepth 4 -name set_env.sh 2>/dev/null | grep -v ascend-toolkit | head -1)
            do
                [[ -f "$f" ]] && source "$f" 2>/dev/null || true
            done
            exit 0
        ' 2>&1 | grep -v "DrvMngGetConsoleLogLevel" || true
        print_success "Ascend 环境已初始化"

        # Only restart the container to propagate usermod group changes when it
        # was just freshly created.  If it was already running before this
        # invocation, other terminal windows may have active `docker exec`
        # sessions — restarting would kill them and is unnecessary (the groups
        # were already set up in a previous run).
        if ! $_was_running; then
            print_step "重启容器以使组成员变更生效..."
            docker restart "${CONTAINER_NAME}" > /dev/null
            # Wait until the container is running again before handing control back
            local _wait=0
            until container_running || [[ $_wait -ge 15 ]]; do
                sleep 1
                _wait=$(( _wait + 1 ))
            done
            container_running \
                && print_success "容器已重启，NPU 设备访问已就绪" \
                || { print_error "容器重启超时，请手动检查: docker ps -a | grep ${CONTAINER_NAME}"; return 1; }
        else
            print_info "容器已在运行，跳过重启（避免断开其他已连接的窗口）"
        fi
    fi
}

lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
