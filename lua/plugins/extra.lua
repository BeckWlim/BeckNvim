return {
    {
        'nvim-lualine/lualine.nvim',
        config = function()
            require('lualine').setup()
        end
    },
    {
        "kyazdani42/nvim-tree.lua",
        config = function()
            require("nvim-tree").setup({
                sort = {
                    sorter = "case_sensitive",
                },
                view = {
                    width = 30,
                },
                renderer = {
                    group_empty = true,
                },
                filters = {
                    dotfiles = true,
                },
            })
        end,
        event = "VimEnter",
        dependencies = "nvim-tree/nvim-web-devicons"
    },
    {
       "akinsho/toggleterm.nvim",
		config = function()
			require('toggleterm').setup({
				open_mapping = [[<c-t>]],
				start_in_insert = true,
				direction = 'horizontal'
			})
		end
    },
    {
        "MeanderingProgrammer/render-markdown.nvim",
        ft = { "markdown" },
        opts = {
            file_types = { "markdown" },
            preset = "lazy",
        },
        dependencies = {
            "nvim-treesitter/nvim-treesitter",
            "nvim-tree/nvim-web-devicons",
        },
    },
    {
        "nvim-treesitter/nvim-treesitter-context",
        opts = {
            enable = true,
            max_lines = 3,
            multiline_threshold = 2,
            mode = "cursor",
            trim_scope = "outer",
        },
        dependencies = {
            "nvim-treesitter/nvim-treesitter",
        },
        config = function(_, opts)
            require("treesitter-context").setup(opts)

            local function set_context_highlights()
                vim.api.nvim_set_hl(0, "TreesitterContext", {
                    bg = "#3A3D32",
                    fg = "#F8F8F2",
                    bold = true,
                })
                vim.api.nvim_set_hl(0, "TreesitterContextLineNumber", {
                    bg = "#3A3D32",
                    fg = "#A6A69C",
                })
                vim.api.nvim_set_hl(0, "TreesitterContextBottom", {
                    underline = true,
                    sp = "#A6E22E",
                })
            end

            set_context_highlights()
            vim.api.nvim_create_autocmd("ColorScheme", {
                group = vim.api.nvim_create_augroup("TreesitterContextHighlight", { clear = true }),
                callback = set_context_highlights,
            })
        end,
    },
}
