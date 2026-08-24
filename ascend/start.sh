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
# Ascend requires driver, dcmi and npu-smi from the host.
ASCEND_EXTRA_MOUNTS=(
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver
    -v /usr/local/dcmi:/usr/local/dcmi
    -v /usr/local/sbin/npu-smi:/usr/local/sbin/npu-smi
)

# ── Platform user groups ──────────────────────────────────────────
# Groups to add the user to during creation (HwHiAiUser is required for NPU access).
# This function will be called by common/lib.sh during user creation.
platform_user_groups() {
    echo "HwHiAiUser"
}

# ── Platform environment variables ────────────────────────────────
# Add Ascend driver libraries to LD_LIBRARY_PATH
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

        # Fix /root permissions for uv virtual environment access
        chmod 755 /root 2>/dev/null || true
        chmod -R o+rX /root/.local 2>/dev/null || true
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
    print_step "配置系统库缓存 (ldconfig)..."
    docker exec -u root "${CONTAINER_NAME}" bash -c '
        cat > /etc/ld.so.conf.d/ascend.conf << "EOF"
/usr/local/Ascend/driver/lib64
/usr/local/Ascend/driver/lib64/common
/usr/local/Ascend/driver/lib64/driver
/usr/local/Ascend/cann-9.0.0/lib64
/usr/local/Ascend/cann-9.0.0/lib64/plugin/opskernel
/usr/local/Ascend/cann-9.0.0/lib64/plugin/nnengine
/usr/local/Ascend/ascend-toolkit/latest/lib64
/usr/local/Ascend/ascend-toolkit/latest/lib64/plugin/opskernel
/usr/local/Ascend/nnal/atb/latest/atb/cxx_abi_1/lib
/usr/local/dcmi
EOF
        ldconfig
    '
    print_success "系统库缓存已更新"
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
    _orig_run_container "$@"

    # Setup device permissions after container is created
    if container_running; then
        _ascend_setup_device_permissions

        # Initialize Ascend environment (critical for DCMI to work)
        print_step "初始化 Ascend 运行环境..."
        docker exec "${CONTAINER_NAME}" bash -c '
            source /usr/local/Ascend/ascend-toolkit/set_env.sh 2>/dev/null || true
            source /usr/local/Ascend/cann-9.0.0/share/info/ascendnpu-ir/bin/set_env.sh 2>/dev/null || true
            source /usr/local/Ascend/nnal/atb/set_env.sh 2>/dev/null || true
            exit 0
        ' 2>&1 | grep -v "DrvMngGetConsoleLogLevel" || true
        print_success "Ascend 环境已初始化"
    fi
}

lib_main "$SCRIPT_DIR" "$REPO_ROOT" "$@"
