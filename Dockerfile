# ============================================================
# FlagGems — terminal development image (NVIDIA + Hygon)
#
# Layers development tools on top of the pre-built runtime
# image.  Select the target platform via PLATFORM build-arg:
#
#   PLATFORM=nvidia  (default)  — runtime: flaggems-nvidia:runtime
#   PLATFORM=hygon              — runtime: flaggems-hygon:runtime
#
# Usage: built and launched via nvidia/start.sh or hygon/start.sh
# ============================================================

ARG PLATFORM=nvidia
ARG RUNTIME_IMAGE=flaggems-${PLATFORM}:runtime
FROM ${RUNTIME_IMAGE}

ARG USERNAME=user
ARG USER_UID=1000
ARG USER_GID=1000

# Transfer ownership of the /flagos venv and uv's Python cache to the
# non-root user.  chown is used rather than chmod so that execute bits
# on every binary are inherited correctly regardless of how they were
# originally set by the runtime image.
# /root itself must remain traversable for uv to resolve its Python path.
RUN chmod o+x /root \
    && chown -R "${USER_UID}:${USER_GID}" /root/.local/share/uv \
    && chown -R "${USER_UID}:${USER_GID}" /flagos

# ------------------------------------------------------------------
# Switch apt sources to Aliyun mirror
# (works for both Ubuntu 24.04 noble and 26.04 plucky)
# ------------------------------------------------------------------
RUN sed -i \
        -e 's|http://archive.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
        -e 's|http://security.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
        /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null \
    || sed -i \
        -e 's|http://archive.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
        -e 's|http://security.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
        /etc/apt/sources.list

# ------------------------------------------------------------------
# System packages: common tools + platform-specific extras
#
# NVIDIA extras: python3-pip, clang-format, openssh-client,
#                pre-commit / flake8 / black / isort (via pip)
# ------------------------------------------------------------------
ARG PLATFORM
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        sudo \
        zsh \
        git \
        curl \
        wget \
        unzip \
        ca-certificates \
        ripgrep \
        fd-find \
        gh \
        $([ "$PLATFORM" = "nvidia" ] && echo "python3-pip clang-format openssh-client") \
    && if [ "$PLATFORM" = "nvidia" ]; then \
        /usr/bin/pip3 install --no-cache-dir --break-system-packages \
            --timeout 120 --retries 5 \
            --index-url https://mirrors.aliyun.com/pypi/simple/ \
            pre-commit==3.7.1 \
            flake8==7.1.0 \
            black==23.7.0 \
            isort==5.12.0; \
       fi \
    && groupadd --gid "$USER_GID" "$USERNAME" \
    && useradd --uid "$USER_UID" --gid "$USER_GID" -m -s /usr/bin/zsh "$USERNAME" \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
    && chmod 0440 "/etc/sudoers.d/$USERNAME" \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------
# Neovim stable (>= 0.11) via neovim-ppa/unstable
# (apt universe only has 0.9; AppImage/tarball requires GitHub access)
# ------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository ppa:neovim-ppa/unstable \
    && apt-get update \
    && apt-get install -y --no-install-recommends neovim \
    && rm -rf /var/lib/apt/lists/* \
    && nvim --version | head -1

# ------------------------------------------------------------------
# Claude Code CLI — Node.js from Aliyun mirror + npm via npmmirror
# ------------------------------------------------------------------
RUN curl -fsSL --retry 3 \
        "https://mirrors.aliyun.com/nodejs-release/v22.23.1/node-v22.23.1-linux-x64.tar.xz" \
        -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && npm install -g @anthropic-ai/claude-code \
        --registry https://registry.npmmirror.com

# ------------------------------------------------------------------
# Switch to non-root user
# (LazyVim + zsh plugins installed at first container start via setup.sh)
# ------------------------------------------------------------------
USER $USERNAME

WORKDIR /workspace
