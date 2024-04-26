return {
  'neoclide/coc.nvim',
  branch = 'release',
  config = function()
    function _G.check_back_space()
      local col = vim.fn.col('.') - 1
      return col == 0 or vim.fn.getline('.'):sub(col, col):match('%s') ~= nil
    end

    local opts = { silent = true, noremap = true, expr = true, replace_keycodes = false }
    vim.keymap.set("i", "<C-space>",
      'coc#pum#visible() ? coc#pum#next(1) : v:lua.check_back_space() ? "<C-space>" : coc#refresh()', opts)
    -- vim.keymap.set("i", "<S-TAB>", [[coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"]], opts)
    vim.keymap.set("i", "<cr>", [[coc#pum#visible() ? coc#pum#confirm() : "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"]],
      opts)
  end,
  build = function()
    print("hello world")
    local coc_global_extensions = {
      'coc-snippets',
      'coc-pairs',
      'coc-tsserver',
      'coc-eslint',
      'coc-prettier',
      'coc-json',
      'coc-lua'
    }
    local combinedString = table.concat(coc_global_extensions, " ")
    vim.cmd("CocInstall " .. combinedString)
  end

}
