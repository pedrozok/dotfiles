return {
  { "ellisonleao/gruvbox.nvim" },
  {
    "rose-pine/neovim",
    name = "rose-pine",
    config = function()
      -- vim.cmd("colorscheme rose-pine")
      -- vim.cmd("colorscheme rose-pine-main")
      -- vim.cmd("colorscheme rose-pine-moon")
      -- vim.cmd("colorscheme rose-pine-dawn")
    end,
  },
  {
    "navarasu/onedark.nvim",
    lazy = false,
    priority = 1000,
    opts = {},
    config = function()
      -- set a warmer theme at night
      local time = tonumber(os.date("%H"))
      require("onedark").setup({
        -- 'dark', 'darker', 'cool', 'deep', 'warm', 'warmer' and 'light'
        style = (time > 20 and "warm" or "cool"),
      })
      require("onedark").load()
    end,
  },
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {},
    config = function()
      -- vim.cmd([[colorscheme tokyonight-night]])
    end,
  },
}
