return {
  'nvim-tree/nvim-tree.lua',
  dependencies = {
    'nvim-tree/nvim-web-devicons'
  },
  config = function()
    local api = require "nvim-tree.api"
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
    -- optionally enable 24-bit colour
    vim.opt.termguicolors = true
    require("nvim-tree").setup()
    -- toggle tree
    vim.keymap.set('n', '<C-f>', function()
      if (api.tree.is_visible()) then
        return ':NvimTreeToggle<CR>'
      end
      return ':NvimTreeFindFile<CR>'
    end, { expr = true })
  end
}
