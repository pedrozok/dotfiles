local keymap = vim.keymap
local opts = {
  noremap = true,
  silent = true,
}
-- panel navigation
-- keymap.set("n", "<C-J>", "<C-W><C-J>")
-- keymap.set("n", "<C-K>", "<C-W><C-K>")
-- keymap.set("n", "<C-L>", "<C-W><C-L>")
-- keymap.set("n", "<C-H>", "<C-W><C-H>")

keymap.set("n", "<Esc><Esc>", ":w<CR>")

-- shift selected lines up and down
keymap.set("v", "J", ":m '>+1<CR>gv=gv", opts)
keymap.set("v", "K", ":m '<-2<CR>gv=gv", opts)

-- tab navigation
keymap.set("n", "L", "<cmd>bnext<cr>", opts)
keymap.set("n", "H", "<cmd>bprev<cr>", opts)

-- codecompanion
vim.keymap.set({ "n", "v" }, "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.keymap.set({ "n", "v" }, "<LocalLeader>a", "<cmd>CodeCompanionChat Toggle<cr>", { noremap = true, silent = true })
vim.keymap.set("v", "ga", "<cmd>CodeCompanionChat Add<cr>", { noremap = true, silent = true })

-- Expand 'cc' into 'CodeCompanion' in the command line
vim.cmd([[cab cc CodeCompanion]])
