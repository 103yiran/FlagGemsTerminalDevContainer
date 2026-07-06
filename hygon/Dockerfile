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
RUN curl -fsSL --retry 5 --retry-delay 10 --retry-max-time 300 \
        https://master.dl.sourceforge.net/project/neovim.mirror/stable/nvim-linux-x86_64.tar.gz \
        -o /tmp/nvim.tar.gz \
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
# GitHub CLI (gh)
# ------------------------------------------------------------------
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------
# Switch to non-root user; pre-download LazyVim + all plugins
# ------------------------------------------------------------------
USER $USERNAME

RUN git clone --depth=1 https://github.com/LazyVim/starter \
        "${HOME}/.config/nvim" \
    && rm -rf "${HOME}/.config/nvim/.git" \
    && nvim --headless "+Lazy! sync" +qa

WORKDIR /workspace/FlagGems
