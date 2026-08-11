return {
    {
        "folke/neoconf.nvim",
        priority = 1000,  -- load before lspconfig/mason so they pick up per-project settings
        dependencies = { "neovim/nvim-lspconfig" },
        config = function()
            require("neoconf").setup({
                import = {
                    vscode = true,  -- also read .vscode/settings.json if present
                },
            })
        end,
    },
}
