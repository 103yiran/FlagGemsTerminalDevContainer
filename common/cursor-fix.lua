-- LazyVim custom configuration to fix cursor visibility on Python comments
-- Works on all platforms (Ascend, CUDA, ROCm)
--
-- Installation:
--   mkdir -p ~/.config/nvim/lua/plugins
--   Copy this file to: ~/.config/nvim/lua/plugins/cursor-fix.lua
--
-- Then restart nvim or run: :Lazy reload cursor-fix

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
