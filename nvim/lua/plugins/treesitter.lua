return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "astro",
        "cmake",
        "cpp",
        "css",
        "gitignore",
        "go",
        "graphql",
        "http",
        "rust",
        "scss",
        "sql",
        "typescript",
        "tsx",
        "clojure",
        "python",
        "bash",
        "prisma",
        "markdown",
        "markdown_inline",
      },

      config = function(_, opts)
        require("nvim-treesitter.configs").setup(opts)
      end,
    },
  },
}
