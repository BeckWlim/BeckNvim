return {
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
    },
    {
        'nvim-telescope/telescope.nvim',
        branch = 'master',
        dependencies = {
            'nvim-lua/plenary.nvim',
            {
                'nvim-telescope/telescope-fzf-native.nvim',
                build = 'make',
            },
        },
        config = function()
            local telescope = require("telescope")
            telescope.setup({
                defaults = {
                    path_display = { "smart" },
                    -- live_grep 搜索隐藏和 VCS 忽略文件
                    vimgrep_arguments = {
                        "rg",
                        "--color=never",
                        "--no-heading",
                        "--with-filename",
                        "--line-number",
                        "--column",
                        "--smart-case",
                        "--hidden",
                        "--no-ignore-vcs",
                    },
                    -- find_files 设为非隐藏但不过滤 gitignore
                    file_ignore_patterns = { ".git/", "node_modules/", "__pycache__/" },
                },
            })
            -- fzf-native 可能未编译，安全加载
            pcall(function() telescope.load_extension("fzf") end)

            local builtin = require("telescope.builtin")
            local map = vim.keymap.set
            local opt = { silent = true }

            local function supports_workspace_symbols(bufnr)
              for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
                if client:supports_method("workspace/symbol", bufnr) then
                  return true
                end
              end
              return false
            end

            local function is_inside(path, root)
              path = vim.fs.normalize(path)
              root = vim.fs.normalize(root)
              return path == root or path:sub(1, #root + 1) == root .. "/"
            end

            local function project_root()
              local path = vim.api.nvim_buf_get_name(0)
              if path == "" then
                path = vim.uv.cwd()
              end

              return vim.fs.root(path, {
                "pyrightconfig.json",
                "basedpyrightconfig.json",
                "pyproject.toml",
                "setup.py",
                "compile_commands.json",
                "CMakeLists.txt",
                ".git",
              }) or vim.uv.cwd()
            end

            local function loaded_symbol_buffer(root, filetype)
              for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                local path = vim.api.nvim_buf_get_name(bufnr)
                if vim.api.nvim_buf_is_loaded(bufnr)
                    and path ~= ""
                    and is_inside(path, root)
                    and (not filetype or vim.bo[bufnr].filetype == filetype)
                    and supports_workspace_symbols(bufnr) then
                  return bufnr
                end
              end
            end

            local function python_entrypoint(root)
              local preferred = {
                root .. "/lmcache/__init__.py",
                root .. "/src/__init__.py",
                root .. "/__init__.py",
              }
              for _, path in ipairs(preferred) do
                if vim.uv.fs_stat(path) then
                  return path
                end
              end

              return vim.fs.find(function(name, path)
                return name:sub(-3) == ".py"
                  and not path:find("/.git/", 1, true)
                  and not path:find("/.venv/", 1, true)
              end, { path = root, type = "file", limit = 1 })[1]
            end

            local function open_workspace_symbols(bufnr, attempts_left)
              if supports_workspace_symbols(bufnr) then
                builtin.lsp_dynamic_workspace_symbols({ bufnr = bufnr })
                return
              end

              if attempts_left == 0 then
                vim.notify(
                  "LSP 尚未就绪；请打开一个源码文件后重试 <Space>fw",
                  vim.log.levels.WARN
                )
                return
              end

              vim.defer_fn(function()
                open_workspace_symbols(bufnr, attempts_left - 1)
              end, 200)
            end

            -- Telescope's workspace-symbol picker normally queries only LSP clients
            -- attached to the current buffer.  In a mixed project that makes the
            -- result depend on whether it is invoked from source code or a README.
            local function project_workspace_symbols()
              local current = vim.api.nvim_get_current_buf()
              local root = project_root()

              if vim.bo[current].filetype ~= "markdown" and supports_workspace_symbols(current) then
                builtin.lsp_dynamic_workspace_symbols({ bufnr = current })
                return
              end

              -- Prefer the Python workspace in Python projects, even when the
              -- current buffer is Markdown/YAML or another non-source file.
              local is_python_project = vim.uv.fs_stat(root .. "/pyrightconfig.json")
                or vim.uv.fs_stat(root .. "/basedpyrightconfig.json")
                or vim.uv.fs_stat(root .. "/pyproject.toml")
                or vim.uv.fs_stat(root .. "/setup.py")
              if is_python_project then
                local python_buf = loaded_symbol_buffer(root, "python")
                if python_buf then
                  builtin.lsp_dynamic_workspace_symbols({ bufnr = python_buf })
                  return
                end

                local path = python_entrypoint(root)
                if path then
                  local existing = vim.fn.bufnr(path)
                  local bufnr = existing ~= -1 and existing or vim.fn.bufadd(path)
                  vim.fn.bufload(bufnr)
                  if existing == -1 then
                    vim.bo[bufnr].buflisted = false
                  end
                  vim.notify("正在启动 Python LSP 并建立项目符号索引…")
                  open_workspace_symbols(bufnr, 50)
                  return
                end
              end

              local source_buf = loaded_symbol_buffer(root)
              if source_buf then
                builtin.lsp_dynamic_workspace_symbols({ bufnr = source_buf })
              elseif supports_workspace_symbols(current) then
                builtin.lsp_dynamic_workspace_symbols({ bufnr = current })
              else
                vim.notify("当前项目没有支持 workspace symbols 的 LSP", vim.log.levels.WARN)
              end
            end

            local actions = require("telescope.actions")
            local make_vsplit = function(builtin_fn)
              return function()
                builtin_fn({
                  attach_mappings = function(_, map)
                    map("i", "<CR>", actions.file_vsplit)
                    map("n", "<CR>", actions.file_vsplit)
                    return true
                  end,
                })
              end
            end

            -- VSCode Ctrl+P: find files
            map("n", "<space>ff", builtin.find_files, { silent = true, desc = "Find files" })
            -- Find files → vertical split
            map("n", "<space>fv", make_vsplit(builtin.find_files), { silent = true, desc = "Find files (vsplit)" })
            -- VSCode Ctrl+Shift+F: project-wide text search
            map("n", "<space>fg", builtin.live_grep, { silent = true, desc = "Live grep" })
            -- Find open buffers
            map("n", "<space>fb", builtin.buffers, { silent = true, desc = "Find buffers" })
            -- Recent files (current directory)
            map("n", "<space>fr", function()
              builtin.oldfiles({ cwd = vim.fn.getcwd() })
            end, { silent = true, desc = "Recent files" })
            -- Find buffers → vertical split
            map("n", "<space>bv", make_vsplit(builtin.buffers), { silent = true, desc = "Find buffers (vsplit)" })
            -- Help tags
            map("n", "<space>fh", builtin.help_tags, { silent = true, desc = "Help tags" })
            -- 查看所有按键映射
            map("n", "<space>fk", builtin.keymaps, { silent = true, desc = "Search keymaps" })
            -- Document symbols (当前文件符号)
            map("n", "<space>fs", builtin.lsp_document_symbols, { silent = true, desc = "Document symbols" })
            -- Workspace symbols (全局搜索函数/类/变量)
            map("n", "<space>fw", project_workspace_symbols, { silent = true, desc = "Project workspace symbols" })
            -- VSCode Shift+F12: find all references
            map("n", "gr", builtin.lsp_references, { silent = true, desc = "Find references" })
            -- LSP navigation
            map("n", "gd", builtin.lsp_definitions, { silent = true, desc = "Go to definition" })
            map("n", "gD", vim.lsp.buf.declaration, { silent = true, desc = "Go to declaration" })
            -- Go to implementation with Telescope UI
            map("n", "gI", builtin.lsp_implementations, { silent = true, desc = "Go to implementation" })
        end,
    },
    {
        "numToStr/Comment.nvim",
        config = function()
            require "Comment".setup {}
        end
    },
    {
        "windwp/nvim-autopairs",
        event = "InsertEnter",
        config = function()
            require "nvim-autopairs".setup {
            check_ts = true,
            ts_config = {
                lua = { "string", "source" },
                javascript = { "string", "template_string" },
            },
            fast_wrap = {
                map = '<M-e>',
                chars = { '{', '[', '(', '"', "'" },
                pattern = [=[[%'%"%)%>%]%)%}%,]]=],
                end_key = '$',
                keys = 'qwfpgjluyzxcvbkmarstdheio',
                check_comma = true,
                highlight = 'Search',
                highlight_grey='Comment'
            }
            }
        end
    },
    {
        "lewis6991/gitsigns.nvim",
        config = function()
            require "gitsigns". setup {
            signs = {
                add = { text = '+' },
                change = { text = '~' },
                delete = { text = '_' },
                topdelete = { text = '‾' },
                changedelete = { text = '~' }
            }}
        end
    },
}
