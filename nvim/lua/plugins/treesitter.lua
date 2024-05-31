return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "astro",
        "cmake",
        "cpp",
        "css",
        "fish",
        "gitignore",
        "go",
        "graphql",
        "http",
        "java",
        "php",
        "rust",
        "scss",
        "sql",
        "svelte",
        "typescript",
        "tsx",
        "clojure",
      },

      config = function(_, opts)
        require("nvim-treesitter.configs").setup(opts)
      end,
    },
  },
}
