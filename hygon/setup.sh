#!/usr/bin/env bash
# setup.sh — run once inside the container to configure zsh and nvim.
# Idempotent: safe to run multiple times.
#
# Requires SSH agent forwarding for GitHub access.  If the agent has
# no loaded key the GitHub steps are skipped with a warning rather
# than aborting the whole script.
set -uo pipefail

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
info()  { echo "==> $*"; }
warn()  { echo "[WARN] $*" >&2; }
error() { echo "[ERROR] $*" >&2; }

# Write GitHub's public host keys so SSH never prompts for
# verification regardless of which user runs this script.
ensure_github_known_hosts() {
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    local kh="${HOME}/.ssh/known_hosts"
    # Only add if not already present
    if ! grep -q "^github.com " "$kh" 2>/dev/null; then
        cat >> "$kh" <<'EOF'
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
EOF
        chmod 600 "$kh"
    fi
}

# Returns 0 if SSH is usable (agent with key, or key file present).
# Sets GIT_SSH_COMMAND to use the key file directly when no agent.
setup_ssh_for_git() {
    # Prefer agent
    if [[ -n "${SSH_AUTH_SOCK:-}" ]] && ssh-add -l &>/dev/null; then
        info "Using SSH agent for git"
        return 0
    fi
    # Fall back to key file
    for key in "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_rsa" "${HOME}/.ssh/id_ecdsa"; do
        if [[ -f "$key" ]]; then
            export GIT_SSH_COMMAND="ssh -i $key -o StrictHostKeyChecking=accept-new"
            info "Using SSH key file for git: $key"
            return 0
        fi
    done
    return 1
}

# ------------------------------------------------------------------
# 0. GitHub known_hosts
# ------------------------------------------------------------------
ensure_github_known_hosts

# ------------------------------------------------------------------
# 1. git: rewrite https://github.com/ to SSH by default
# ------------------------------------------------------------------
git config --global url."git@github.com:".insteadOf "https://github.com/"
info "git configured: https://github.com/ → git@github.com:"

# ------------------------------------------------------------------
# 2. zsh: oh-my-zsh + plugins (via Gitee mirror, no GitHub needed)
# ------------------------------------------------------------------
if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    info "Installing oh-my-zsh..."
    git clone --depth=1 https://gitee.com/mirrors/oh-my-zsh.git \
        "${HOME}/.oh-my-zsh" \
        || warn "oh-my-zsh clone failed — skipping"
fi

# Always write the oh-my-zsh .zshrc template so the shell is
# properly configured, even if a bare .zshrc already exists.
if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    cp "${HOME}/.oh-my-zsh/templates/zshrc.zsh-template" "${HOME}/.zshrc"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    info "Installing zsh-autosuggestions..."
    git clone --depth=1 https://gitee.com/mirrors/zsh-autosuggestions.git \
        "$ZSH_CUSTOM/plugins/zsh-autosuggestions" \
        || warn "zsh-autosuggestions clone failed — skipping"
fi

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    info "Installing zsh-syntax-highlighting..."
    git clone --depth=1 https://gitee.com/mirrors/zsh-syntax-highlighting.git \
        "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" \
        || warn "zsh-syntax-highlighting clone failed — skipping"
fi

# Enable plugins in .zshrc (safe even if oh-my-zsh install was skipped)
sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' \
    "${HOME}/.zshrc" 2>/dev/null || true

# ------------------------------------------------------------------
# 3. nvim: LazyVim starter config + plugin sync
# ------------------------------------------------------------------
if [[ ! -d "${HOME}/.config/nvim" ]]; then
    if ! setup_ssh_for_git; then
        warn "No SSH key or agent found — skipping LazyVim install."
        warn "To install later: ensure ~/.ssh/id_ed25519 exists and re-run setup.sh."
    else
        info "Installing LazyVim starter config..."
        if git clone --depth=1 git@github.com:LazyVim/starter.git \
                "${HOME}/.config/nvim"; then
            rm -rf "${HOME}/.config/nvim/.git"
            info "Syncing LazyVim plugins (this may take a while)..."
            nvim --headless "+Lazy! sync" +qa \
                || warn "Lazy sync exited non-zero — some plugins may be missing"
        else
            warn "LazyVim clone failed — skipping nvim setup"
        fi
    fi
else
    info "LazyVim config already present at ~/.config/nvim — skipping clone"
fi

# ------------------------------------------------------------------
info "setup.sh done. Start a new zsh session or run: exec zsh"
