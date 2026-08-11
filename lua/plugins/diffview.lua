return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  keys = {
    { "<Space>dv", "<cmd>DiffviewOpen<cr>", desc = "Diffview: current branch vs HEAD" },
    { "<Space>dvm", "<cmd>DiffviewOpen main<cr>", desc = "Diffview: vs main" },
    { "<Space>dvh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history" },
    { "<Space>dvc", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
  },
}
