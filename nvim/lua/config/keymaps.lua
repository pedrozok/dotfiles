local keymap = vim.keymap
local opts = {
  noremap = true,
  silent = true,
}
-- panel navigation
keymap.set("n", "<C-J>", "<C-W><C-J>")
keymap.set("n", "<C-K>", "<C-W><C-K>")
keymap.set("n", "<C-L>", "<C-W><C-L>")
keymap.set("n", "<C-H>", "<C-W><C-H>")

keymap.set("n", "<Esc><Esc>", ":w<CR>")

-- shift selected lines up and down
keymap.set("v", "J", ":m '>+1<CR>gv=gv", opts)
keymap.set("v", "K", ":m '<-2<CR>gv=gv", opts)

-- tab navigation
keymap.set("n", "L", "<cmd>bnext<cr>", opts)
keymap.set("n", "H", "<cmd>bprev<cr>", opts)
