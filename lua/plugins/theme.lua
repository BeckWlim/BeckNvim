return {
  {
    "crusoexia/vim-monokai",
    priority = 1000,
    config = function()
      local function set_completion_highlights()
        vim.api.nvim_set_hl(0, "Pmenu", { bg = "#232526", fg = "#DCDCDC" })
        vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#3A3D3F", fg = "#FFFFFF", bold = true })
        vim.api.nvim_set_hl(0, "PmenuFloatBorder", { fg = "#666666" })
        vim.api.nvim_set_hl(0, "CmpItemAbbr", { fg = "#DCDCDC" })
        vim.api.nvim_set_hl(0, "CmpItemAbbrMatch", { fg = "#F92672", bold = true })
        vim.api.nvim_set_hl(0, "CmpItemAbbrMatchFuzzy", { fg = "#F92672" })
        vim.api.nvim_set_hl(0, "CmpItemMenu", { fg = "#75715E" })

        local kind_colors = {
          Function = "#A6E22E",
          Method = "#A6E22E",
          Class = "#A6E22E",
          Interface = "#A6E22E",
          Struct = "#A6E22E",
          Variable = "#66D9EF",
          Module = "#66D9EF",
          Property = "#66D9EF",
          Keyword = "#F92672",
          Field = "#F92672",
          Operator = "#F92672",
          Snippet = "#AE81FF",
          Constant = "#AE81FF",
          Enum = "#AE81FF",
          EnumMember = "#AE81FF",
          Unit = "#E6DB74",
          Value = "#E6DB74",
          Color = "#E6DB74",
          Folder = "#E6DB74",
          Text = "#F8F8F2",
          File = "#F8F8F2",
          Reference = "#F8F8F2",
        }

        for kind, color in pairs(kind_colors) do
          vim.api.nvim_set_hl(0, "CmpItemKind" .. kind, { fg = color })
        end
      end

      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("CmpHighlight", { clear = true }),
        pattern = "*",
        callback = set_completion_highlights,
      })

      vim.cmd.colorscheme("monokai")
      set_completion_highlights()
    end,
  },
  {
    "glepnir/dashboard-nvim",
    event = "VimEnter",
    config = function()
      require("dashboard").setup({})
    end,
    dependencies = { "nvim-tree/nvim-web-devicons" },
  },
}
