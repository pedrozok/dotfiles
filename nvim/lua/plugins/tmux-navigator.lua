return {
  -- The vim half of the tmux vim-aware pane navigation: hands C-h/j/k/l back
  -- to tmux at the edge of the last split. .tmux.conf implements the other
  -- half. The keys must be declared here as lazy `keys` handlers - LazyVim
  -- remaps C-h/j/k/l to window moves on VeryLazy via safe_keymap_set, which
  -- only yields to keys owned by a lazy handler; a plain `lazy = false` plugin
  -- gets clobbered after startup and the handoff never fires.
  {
    "christoomey/vim-tmux-navigator",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
    },
    keys = {
      { "<C-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Navigate left (tmux-aware)" },
      { "<C-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Navigate down (tmux-aware)" },
      { "<C-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Navigate up (tmux-aware)" },
      { "<C-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Navigate right (tmux-aware)" },
    },
  },
}
