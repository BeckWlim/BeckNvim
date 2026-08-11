return {
    {
        "williamboman/mason-lspconfig.nvim",
        dependencies = {
            "williamboman/mason.nvim",
            "neovim/nvim-lspconfig",
            "hrsh7th/cmp-nvim-lsp",
        },
        config = function()
            -- mason 配置
            require "mason".setup {
              ui = {
                icons = {
                  package_installed = "✓",
                  package_pending = "➜",
                  package_uninstalled = "✗"
                }
              }
            }
            -- mason-lspconfig 配置
            require("mason-lspconfig").setup {
              -- 选择需要启动的 lsp 服务器的语言
              ensure_installed = { "bashls", "basedpyright", "clangd", "lua_ls", "marksman", "vimls" }
            }

            local capabilities = require("cmp_nvim_lsp").default_capabilities()

            -- Apply completion capabilities to every language server.
            vim.lsp.config("*", {
              capabilities = capabilities,
            })

            vim.lsp.config("basedpyright", {
              root_markers = {
                "pyrightconfig.json",
                "basedpyrightconfig.json",
                "pyproject.toml",
                "setup.py",
                ".git",
              },
              before_init = function(_, config)
                local root_dir = config.root_dir
                if type(root_dir) ~= "string" then
                  return
                end

                local python_path = root_dir .. "/.venv/bin/python"
                if vim.fn.executable(python_path) == 1 then
                  config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
                    python = { pythonPath = python_path },
                  })
                end
              end,
              settings = {
                basedpyright = {
                  analysis = {
                    -- 默认使用第三方库源码推导类型，并报告第三方导入问题。
                    useLibraryCodeForTypes = true,
                    diagnosticSeverityOverrides = {
                      reportMissingImports = "error",
                      reportMissingModuleSource = "warning",
                      reportMissingTypeStubs = "warning",
                    },
                  },
                },
              },
            })
            vim.lsp.enable("basedpyright")

            vim.lsp.config("clangd", {
              cmd = { "clangd" },
              filetypes = { "c", "cpp" },
              root_markers = { ".clangd", "compile_commands.json", ".git" },
            })
            vim.lsp.enable("clangd")
        end
    },
    {
        "hrsh7th/nvim-cmp",
        dependencies = {
            -- 补全插件
            "hrsh7th/cmp-nvim-lsp",
            -- 路径补全插件
            "hrsh7th/cmp-path",
            -- 第三方片段引擎
            "L3MON4D3/LuaSnip",
            "saadparwaiz1/cmp_luasnip",
            "rafamadriz/friendly-snippets"
        },
        config = function()
            local cmp_ok, cmp = pcall(require, "cmp")
            local luasnip_ok, luasnip = pcall(require, "luasnip")
            if not cmp_ok or not luasnip_ok then
            return
            end
            require "luasnip.loaders.from_vscode".lazy_load()
            cmp.setup {
            -- 片段引擎
            snippet = {
                expand = function(args)
                require "luasnip".lsp_expand(args.body)
                end,
            },
            mapping = cmp.mapping.preset.insert {
                ['<CR>'] = cmp.mapping.confirm({ select = true }),
            },
            -- 指定资源
            sources = cmp.config.sources({
                { name = 'nvim_lsp' },
                { name = 'luasnip' },
                { name = 'path' }
                },{
                { name = 'buffer' }
                }),
            -- 补全窗口样式
            window = {
                completion = {
                    border = "rounded",
                    winhighlight = "Normal:Pmenu,FloatBorder:Pmenu,CursorLine:PmenuSel,Search:None",
                },
                documentation = {
                    border = "rounded",
                    winhighlight = "Normal:Pmenu,FloatBorder:Pmenu",
                },
            },
            -- 补全菜单高亮
            formatting = {
                format = function(entry, vim_item)
                    -- 限制补全菜单宽度
                    vim_item.abbr = vim.fn.strcharpart(vim_item.abbr, 0, 50)
                    -- 添加来源标记
                    local source_names = {
                        nvim_lsp = "[LSP]",
                        luasnip = "[Snp]",
                        buffer = "[Buf]",
                        path = "[Pth]",
                    }
                    vim_item.menu = source_names[entry.source.name] or "[" .. entry.source.name .. "]"
                    return vim_item
                end,
            },
            }
        end
    },
}
