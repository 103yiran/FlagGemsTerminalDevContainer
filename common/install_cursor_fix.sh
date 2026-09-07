#!/usr/bin/env bash
# Install LazyVim cursor visibility fix for all platforms
# This script should be run INSIDE the container

set -e

CURSOR_FIX_URL="https://raw.githubusercontent.com/your-repo/cursor-fix.lua"

echo "🔧 Installing LazyVim cursor visibility fix..."
echo ""

# Create LazyVim plugins directory if it doesn't exist
PLUGINS_DIR="$HOME/.config/nvim/lua/plugins"
mkdir -p "$PLUGINS_DIR"

# Check if cursor-fix.lua exists in common directory (development mode)
if [[ -f "/workspace/FlagGemsTerminalDevContainer/common/cursor-fix.lua" ]]; then
    echo "📦 Found cursor-fix.lua in mounted repo, copying..."
    cp "/workspace/FlagGemsTerminalDevContainer/common/cursor-fix.lua" "$PLUGINS_DIR/cursor-fix.lua"
elif [[ -f "./cursor-fix.lua" ]]; then
    echo "📦 Found cursor-fix.lua in current directory, copying..."
    cp "./cursor-fix.lua" "$PLUGINS_DIR/cursor-fix.lua"
else
    echo "📝 Creating cursor-fix.lua from embedded content..."
    cat > "$PLUGINS_DIR/cursor-fix.lua" << 'EOF'
-- LazyVim custom configuration to fix cursor visibility on Python comments
-- Works on all platforms (Ascend, CUDA, ROCm)

return {
  -- Override colorscheme settings to fix cursor visibility
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        -- Apply after any colorscheme loads
        vim.api.nvim_create_autocmd("ColorScheme", {
          pattern = "*",
          callback = function()
            -- Set highly visible cursor colors (bright green)
            vim.api.nvim_set_hl(0, "Cursor", { fg = "#000000", bg = "#00ff00", bold = true })
            vim.api.nvim_set_hl(0, "TermCursor", { fg = "#000000", bg = "#00ff00", bold = true })
            vim.api.nvim_set_hl(0, "lCursor", { fg = "#000000", bg = "#00ff00", bold = true })

            -- Subtle cursorline background
            vim.api.nvim_set_hl(0, "CursorLine", { bg = "#2d2d2d" })
            vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#ffff00", bold = true })

            -- Fix Comment highlighting - remove background color
            local comment_hl = vim.api.nvim_get_hl(0, { name = "Comment" })
            if comment_hl.bg then
              vim.api.nvim_set_hl(0, "Comment", {
                fg = comment_hl.fg or "#6c7086",
                italic = true,
              })
            end
          end,
        })
      end,
    },
  },

  -- Configure cursor options
  {
    "LazyVim/LazyVim",
    opts = function(_, opts)
      -- Enable cursorline
      vim.opt.cursorline = true
      vim.opt.termguicolors = true

      -- Set cursor shape and blinking
      vim.opt.guicursor = {
        "n-v-c:block-Cursor/lCursor",
        "i-ci-ve:ver25-Cursor/lCursor",
        "r-cr:hor20-Cursor/lCursor",
        "o:hor50-Cursor/lCursor",
        "a:blinkwait700-blinkoff400-blinkon250",
      }

      -- Apply highlights immediately
      vim.schedule(function()
        vim.cmd([[
          highlight! Cursor guifg=#000000 guibg=#00ff00 gui=bold ctermfg=0 ctermbg=10
          highlight! TermCursor guifg=#000000 guibg=#00ff00 gui=bold ctermfg=0 ctermbg=10
          highlight! lCursor guifg=#000000 guibg=#00ff00 gui=bold ctermfg=0 ctermbg=10
          highlight! CursorLine guibg=#2d2d2d ctermbg=236
          highlight! CursorLineNr guifg=#ffff00 gui=bold ctermfg=11 cterm=bold
        ]])
      end)
    end,
  },
}
EOF
fi

echo "✅ Cursor fix installed to: $PLUGINS_DIR/cursor-fix.lua"
echo ""
echo "📝 LazyVim will automatically load this plugin on next nvim launch."
echo ""
echo "🔄 To apply immediately:"
echo "   1. Restart nvim, or"
echo "   2. In nvim run: :Lazy reload cursor-fix"
echo "   3. Then run: :colorscheme <your-theme>"
echo ""
echo "💡 Color customization:"
echo "   Edit: $PLUGINS_DIR/cursor-fix.lua"
echo "   Change 'bg = \"#00ff00\"' to your preferred color:"
echo "   - #ffff00 (yellow)"
echo "   - #00ffff (cyan)"
echo "   - #ff00ff (magenta)"
