# ============================================================
# FlagGems — Hygon terminal development image
#
# Layers development tools on top of the pre-built runtime
# image produced by container/flaggems-hygon-26.04.
#
# Usage: built and launched via dev/hygon/start.sh
# ============================================================

ARG RUNTIME_IMAGE=flaggems-hygon:runtime
FROM ${RUNTIME_IMAGE}

ARG USERNAME=user
ARG USER_UID=1000
ARG USER_GID=1000

# ------------------------------------------------------------------
# Switch apt sources to Aliyun mirror (Ubuntu 26.04 plucky)
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
# System packages: sudo, zsh, neovim, misc tools
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
        neovim \
        gh \
    && groupadd --gid "$USER_GID" "$USERNAME" \
    && useradd --uid "$USER_UID" --gid "$USER_GID" -m -s /usr/bin/zsh "$USERNAME" \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
    && chmod 0440 "/etc/sudoers.d/$USERNAME" \
    && rm -rf /var/lib/apt/lists/*

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
# Switch to non-root user; pre-download LazyVim + all plugins
# ------------------------------------------------------------------
USER $USERNAME

RUN --mount=type=ssh \
    git clone --depth=1 git@github.com:LazyVim/starter.git \
        "${HOME}/.config/nvim" \
    && rm -rf "${HOME}/.config/nvim/.git" \
    && nvim --headless "+Lazy! sync" +qa

WORKDIR /workspace/FlagGems
