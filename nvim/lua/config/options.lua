-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Undo, swap and backup files keep plaintext copies of a secret after the env file is gone.
-- Defined here, not in autocmds.lua, so it also covers a file opened from the command line.
vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
  pattern = { ".env*", "*.env" },
  command = "setlocal noundofile noswapfile nobackup",
})
