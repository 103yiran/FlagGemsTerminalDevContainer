#!/usr/bin/env bash
# setup.sh — run once inside the container to configure zsh and nvim.
# Idempotent: safe to run multiple times.
set -euo pipefail

# ------------------------------------------------------------------
# zsh: oh-my-zsh + plugins
# ------------------------------------------------------------------
if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    echo "==> Installing oh-my-zsh..."
    RUNZSH=no CHSH=no \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    echo "==> Installing zsh-autosuggestions..."
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
        "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    echo "==> Installing zsh-syntax-highlighting..."
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
        "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# Enable plugins in .zshrc
sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' \
    "${HOME}/.zshrc" 2>/dev/null || true

# ------------------------------------------------------------------
# nvim: LazyVim config already pre-installed in the image.
# If ~/.config/nvim is missing for some reason, re-clone the starter.
# ------------------------------------------------------------------
if [[ ! -d "${HOME}/.config/nvim" ]]; then
    echo "==> Re-installing LazyVim starter config (was not found in image)..."
    git clone --depth=1 https://github.com/LazyVim/starter \
        "${HOME}/.config/nvim"
    rm -rf "${HOME}/.config/nvim/.git"
    nvim --headless "+Lazy! sync" +qa
fi

echo "==> setup.sh done. Start a new zsh session or run: exec zsh"
