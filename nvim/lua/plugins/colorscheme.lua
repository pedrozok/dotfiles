return {
  { "ellisonleao/gruvbox.nvim" },
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    -- opts only, no config function: a custom config replaces lazy.nvim's
    -- default implementation and setup(opts) never runs, silently dropping
    -- the style. LazyVim applies the scheme via its colorscheme option.
    opts = { style = "storm" },
  },
}
