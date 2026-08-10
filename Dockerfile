# ============================================================
# FlagGems — terminal development image (NVIDIA + Hygon + Cambricon + Ascend)
#
# Layers development tools on top of FlagOS base images from Harbor.
# Select the target platform via PLATFORM, TOOLKIT, and BASE_IMAGE_TAG build-args:
#
#   PLATFORM=nvidia     (default)  — TOOLKIT default: cuda13.3
#   PLATFORM=hygon                 — TOOLKIT default: dtk26.04
#   PLATFORM=cambricon             — TOOLKIT default: neuware4.7.2
#   PLATFORM=ascend                — TOOLKIT default: cann9.0.0
#   TOOLKIT                        — override toolkit version (replaces per-platform default)
#   BASE_IMAGE_TAG=2.1.2           — FlagOS base image version
#
# Resulting base image: flagos-base-<PLATFORM>-<TOOLKIT>:<BASE_IMAGE_TAG>
#
# Usage: built and launched via nvidia/start.sh, hygon/start.sh,
#        cambricon/start.sh, or ascend/start.sh
# ============================================================

ARG PLATFORM=nvidia
ARG TOOLKIT=cuda13.3
ARG BASE_IMAGE_TAG=2.1.2
ARG BASE_IMAGE_REGISTRY=harbor.baai.ac.cn/flagos-base

FROM ${BASE_IMAGE_REGISTRY}/flagos-base-${PLATFORM}-${TOOLKIT}:${BASE_IMAGE_TAG} AS base

ARG USERNAME=user
ARG USER_UID=1000
ARG USER_GID=1000

# Transfer ownership of the /flagos venv and uv's Python cache to the
# non-root user.  mkdir -p guards paths absent in some base images.
# Symlink uv into /usr/local/bin so it is on PATH for all users; the
# binary lives at /root/.local/bin/uv (installed by the FlagOS base image).
# Place uv cache at /usr/local/share/uv to avoid /root traversal issues.
RUN mkdir -p /usr/local/share/uv /root/.local/bin /flagos \
    && chown -R "${USER_UID}:${USER_GID}" /usr/local/share/uv \
    && chown -R "${USER_UID}:${USER_GID}" /flagos \
    && if [ -f /root/.local/bin/uv ]; then \
           ln -sf /root/.local/bin/uv /usr/local/bin/uv; \
       fi

# Point uv to the shared cache location
ENV UV_CACHE_DIR=/usr/local/share/uv

# ------------------------------------------------------------------
# Switch apt sources to Aliyun mirror
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
# System packages — NVIDIA extras: python3-pip, clang-format,
# openssh-client, pre-commit / flake8 / black / isort (via pip)
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
# add-apt-repository requires api.launchpad.net; add the PPA manually instead.
# ------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl gnupg \
    && curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x9dbb0be9366964f134855e2255f96fcf8231b6dd' \
        | gpg --dearmor -o /usr/share/keyrings/neovim-ppa.gpg \
    && echo 'deb [arch=arm64 signed-by=/usr/share/keyrings/neovim-ppa.gpg] https://ppa.launchpadcontent.net/neovim-ppa/unstable/ubuntu noble main' \
        > /etc/apt/sources.list.d/neovim-ppa.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends neovim \
    && rm -rf /var/lib/apt/lists/* \
    && nvim --version | head -1

# ------------------------------------------------------------------
# Claude Code CLI — Node.js from Aliyun mirror + npm via npmmirror
# ------------------------------------------------------------------
RUN curl -fsSL --retry 3 \
        "https://mirrors.aliyun.com/nodejs-release/v22.23.1/node-v22.23.1-linux-arm64.tar.xz" \
        -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && npm install -g @anthropic-ai/claude-code \
        --registry https://registry.npmmirror.com

# ------------------------------------------------------------------
# Switch to non-root user
# ------------------------------------------------------------------
USER $USERNAME

WORKDIR /workspace
