# ============================================================
# FlagGems — NVIDIA terminal development image
#
# Layers development tools on top of the pre-built runtime
# image produced by container/flaggems-nvidia-13.3.
#
# Usage: built and launched via nvidia/start.sh
# ============================================================

ARG RUNTIME_IMAGE=flaggems-nvidia:runtime
FROM ${RUNTIME_IMAGE}

ARG USERNAME=user
ARG USER_UID=1000
ARG USER_GID=1000

# ------------------------------------------------------------------
# Switch apt sources to Aliyun mirror (Ubuntu 24.04 noble)
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
# System packages: sudo, zsh, misc tools,
#                  pre-commit toolchain (flake8, black, isort,
#                  clang-format, pre-commit)
# ------------------------------------------------------------------
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
        python3-pip \
        clang-format \
        openssh-client \
        gh \
    && /usr/bin/pip3 install --no-cache-dir --break-system-packages \
        --timeout 120 --retries 5 \
        --index-url https://mirrors.aliyun.com/pypi/simple/ \
        pre-commit==3.7.1 \
        flake8==7.1.0 \
        black==23.7.0 \
        isort==5.12.0 \
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

WORKDIR /workspace/FlagGems
