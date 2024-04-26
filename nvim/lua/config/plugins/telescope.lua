return {
  'nvim-telescope/telescope.nvim',
  tag = '0.1.6',
  dependencies = { 'nvim-lua/plenary.nvim' },
  defaults = {
    file_ignore_patterns = { '^node_modules/', '^.git/' },
  },
  config = function()
    local builtin = require('telescope.builtin')
    vim.keymap.set('n', '<leader>pf', builtin.find_files, {})
    vim.keymap.set('n', '<C-p>', builtin.git_files, {})
    vim.keymap.set('n', '<C-g>', builtin.live_grep, {})
    -- vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)
  end
}
