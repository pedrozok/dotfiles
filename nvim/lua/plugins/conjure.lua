return {
  {
    "Olical/conjure",
    ft = { "clojure", "fennel", "python" }, -- etc
    -- dependencies = {
    --   {
    --     "PaterJason/cmp-conjure",
    --     config = function()
    --       local cmp = require("cmp")
    --       local config = cmp.get_config()
    --       table.insert(config.sources, {
    --         name = "buffer",
    --         option = {
    --           sources = {
    --             { name = "conjure" },
    --           },
    --         },
    --       })
    --       cmp.setup(config)
    --     end,
    --   },
    -- },
    config = function(_, opts)
      require("conjure.main").main()
      require("conjure.mapping")["on-filetype"]()

      vim.g.maplocalleader = ","
    end,
    init = function()
      vim.g["conjure#debug"] = true
    end,
  },
}
