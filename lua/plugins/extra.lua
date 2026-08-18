return {
    {
        'nvim-lualine/lualine.nvim',
        config = function()
            local project_markers = {
                ".git",
                "pyproject.toml",
                "package.json",
                "Cargo.toml",
                "go.mod",
                "CMakeLists.txt",
                "Makefile",
            }

            local function project_root(bufnr, filename)
                -- Prefer the most specific LSP workspace containing this file.
                local root
                for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
                    local client_root = client.config.root_dir
                    if type(client_root) == "string"
                        and vim.fs.relpath(client_root, filename)
                        and (not root or #client_root > #root)
                    then
                        root = client_root
                    end
                end

                return root or vim.fs.root(filename, project_markers) or vim.fn.getcwd()
            end

            local function project_relative_path()
                local bufnr = vim.api.nvim_get_current_buf()
                local filename = vim.api.nvim_buf_get_name(bufnr)
                if filename == "" then
                    return "[No Name]"
                end

                filename = vim.fs.normalize(filename)
                local relative = vim.fs.relpath(project_root(bufnr, filename), filename) or filename

                if vim.bo[bufnr].modified then
                    relative = relative .. " [+]"
                end
                if vim.bo[bufnr].readonly then
                    relative = relative .. " [RO]"
                end

                return relative
            end

            require('lualine').setup({
                sections = {
                    lualine_c = {
                        { project_relative_path },
                    },
                },
            })
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
