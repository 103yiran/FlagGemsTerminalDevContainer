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
    # The template comments out the $HOME/.local/bin PATH line; uncomment it so
    # tools installed there (uv, cargo binaries, etc.) are available immediately.
    sed -i 's|^# export PATH=\$HOME/bin:\$HOME/.local/bin|export PATH=$HOME/bin:$HOME/.local/bin|' \
        "${HOME}/.zshrc"
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
        # Clone the starter *template* (LazyVim/starter), not the plugin
        # repo (LazyVim/LazyVim).  The plugin repo ships a hard-coded check
        # that prints "Do not use this repository directly / Press any key to
        # exit" and blocks — causing nvim --headless to hang forever.
        if git clone --depth=1 git@gitcode.com:gh_mirrors/sta/starter.git \
                "${HOME}/.config/nvim" \
            || git clone --depth=1 https://github.com/LazyVim/starter.git \
                "${HOME}/.config/nvim"; then
            rm -rf "${HOME}/.config/nvim/.git"

            # ── Patch: lua/config/lazy.lua with gitcode mirrors ───────────
            # Overwrite lua/config/lazy.lua to:
            # 1. Bootstrap lazy.nvim from gitcode GitHub_Trending/la/lazy.nvim
            # 2. Hook Plugin.init to rewrite each plugin's GitHub URL to gitcode
            #    Pattern: GitHub_Trending/<repo-name[0:2]>/<repo-name>
            cat > "${HOME}/.config/nvim/lua/config/lazy.lua" << 'LUA'
-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "git@gitcode.com:gh_mirrors/la/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Override lazy.nvim's git.url_format to redirect plugin clones to gitcode.
-- lazy.nvim calls url_format:format("owner/repo") to build the clone URL.
-- By setting url_format to a table whose :format() method we intercept every
-- clone and redirect it to gitcode gh_mirrors where available.
--
-- gitcode gh_mirrors layout: git@gitcode.com:gh_mirrors/<repo[0:2]>/<repo>.git
-- e.g. "folke/snacks.nvim" -> git@gitcode.com:gh_mirrors/sn/snacks.nvim.git
--
-- Owners whose repos are largely absent from gh_mirrors (e.g. echasnovski/mini.*)
-- fall back to GitHub SSH directly — connectivity to github.com via SSH is
-- available in this environment.
--
-- This works because vim.tbl_deep_extend preserves metatables, so lazy.nvim's
-- Config.options.git.url_format ends up being this table, and the subsequent
-- url_format:format(plugin_spec) call hits our custom method.

-- Owners that should go directly to GitHub SSH (not in gitcode gh_mirrors).
local github_direct_owners = {
  echasnovski = true,
}

local gitcode_url_format = setmetatable({}, {
  __index = {
    format = function(_, s)
      -- s is "owner/repo" or "owner/repo.git"
      local owner, repo = s:match("([^/]+)/([^/]+)")
      if not repo then
        -- Fallback: no slash found, use s as repo name
        repo = s:gsub("%.git$", "")
        local prefix = repo:sub(1, 2):lower()
        return ("git@gitcode.com:gh_mirrors/%s/%s.git"):format(prefix, repo)
      end
      repo = repo:gsub("%.git$", "")
      -- Route known-missing owners directly to GitHub SSH
      if github_direct_owners[owner] then
        return ("git@github.com:%s/%s.git"):format(owner, repo)
      end
      local prefix = repo:sub(1, 2):lower()
      return ("git@gitcode.com:gh_mirrors/%s/%s.git"):format(prefix, repo)
    end,
  },
})

require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false,
  },
  git = {
    -- Redirect all plugin clones to gitcode gh_mirrors (covers virtually all
    -- GitHub repos). url_format:format("owner/repo") is lazy.nvim's internal
    -- hook for building clone URLs from short "owner/repo" specs.
    url_format = gitcode_url_format,
    -- Disable partial clone (--filter=blob:none).
    -- Partial clone writes the original GitHub URL as the promisor remote,
    -- causing subsequent blob fetches to hit GitHub directly (blocked).
    -- With filter=false all objects are transferred upfront at clone time.
    filter = false,
    timeout = 120,
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = { enabled = true },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
LUA

            # ── Disable plugins that require the tree-sitter CLI binary ───
            mkdir -p "${HOME}/.config/nvim/lua/plugins"
            cat > "${HOME}/.config/nvim/lua/plugins/no-treesitter-cli.lua" << 'LUA'
-- Disable tree-sitter features that require the CLI binary.
return {
  -- Disable nvim-treesitter-playground (requires tree-sitter CLI)
  { "nvim-treesitter/playground", enabled = false },
  -- Keep nvim-treesitter itself but disable auto-install and build
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      auto_install = false,  -- Don't auto-install parsers (needs tree-sitter CLI)
    },
    build = nil,  -- Disable the :TSUpdate command (needs tree-sitter CLI)
  },
}
LUA

            info "Syncing LazyVim plugins (this may take a while)..."

            # Pre-check: ensure .local/share/nvim has write permissions and space
            mkdir -p "${HOME}/.local/share/nvim/lazy"
            touch "${HOME}/.local/share/nvim/.writetest" 2>/dev/null \
                && rm -f "${HOME}/.local/share/nvim/.writetest" \
                || { warn "~/.local/share/nvim is not writable — plugin sync will fail"; }

            timeout 300 nvim --headless "+Lazy! sync" +qa \
                || warn "Lazy sync exited non-zero — some plugins may be missing"

            # Post-sync: recover any plugin whose .git dir exists but working tree
            # is empty.  This happens when git clone's partial-clone (--filter=blob:none)
            # succeeds in transferring objects but fails during checkout — leaving only
            # the .git directory.  `git checkout -f HEAD` re-writes the working tree
            # from the already-present object database without re-fetching anything.
            local _lazy_dir="${HOME}/.local/share/nvim/lazy"
            for _plugin_dir in "${_lazy_dir}"/*/; do
                [[ -d "${_plugin_dir}.git" ]] || continue
                # Count non-.git files; if zero, checkout is incomplete
                local _nfiles
                _nfiles=$(find "${_plugin_dir}" -mindepth 1 -not -path "*/.git/*" | wc -l)
                if [[ "${_nfiles}" -eq 0 ]]; then
                    local _pname
                    _pname=$(basename "${_plugin_dir}")
                    warn "${_pname}: checkout incomplete — recovering with git checkout -f HEAD"
                    git -C "${_plugin_dir}" checkout -f HEAD 2>&1 \
                        && info "${_pname}: recovered ($(find "${_plugin_dir}" -not -path "*/.git/*" -mindepth 1 | wc -l) files)" \
                        || warn "${_pname}: recovery failed"
                fi
            done
        else
            warn "LazyVim clone failed — skipping nvim setup"
        fi
    fi
else
    info "LazyVim config already present at ~/.config/nvim — skipping clone"
fi

# ------------------------------------------------------------------
info "setup.sh done. Start a new zsh session or run: exec zsh"
