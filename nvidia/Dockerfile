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
# System packages: sudo, zsh, neovim deps, misc tools
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
    && groupadd --gid "$USER_GID" "$USERNAME" \
    && useradd --uid "$USER_UID" --gid "$USER_GID" -m -s /usr/bin/zsh "$USERNAME" \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
    && chmod 0440 "/etc/sudoers.d/$USERNAME" \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------
# Neovim — stable binary from SourceForge mirror
# ------------------------------------------------------------------
RUN wget -q https://master.dl.sourceforge.net/project/neovim.mirror/stable/nvim-linux-x86_64.tar.gz \
        -O /tmp/nvim.tar.gz \
    && tar -xzf /tmp/nvim.tar.gz -C /usr/local --strip-components=1 \
    && rm /tmp/nvim.tar.gz

# ------------------------------------------------------------------
# Claude Code CLI (Node.js + npm)
# ------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @anthropic-ai/claude-code \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------
# Switch to non-root user; zsh/nvim config done via setup.sh
# ------------------------------------------------------------------
USER $USERNAME
WORKDIR /workspace/FlagGems
