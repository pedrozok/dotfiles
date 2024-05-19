local force_light_theme = os.getenv("FORCE_LIGHT_THEME")

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
      local hour = tonumber(os.date("%H"))
      local default_theme = "dark"
      -- possible styles: 'dark', 'darker', 'cool', 'deep', 'warm', 'warmer' and 'light'
      local theme = (hour > 20 and "warm" or default_theme)

      if force_light_theme == "true" then
        theme = "light"
      end

      require("onedark").setup({
        style = theme,
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
