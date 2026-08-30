local M = {}

function M.setup()
  local cmp = require('cmp')
  local luasnip = require('luasnip')
  require('luasnip.loaders.from_vscode').lazy_load()

  cmp.setup({
    snippet = {
      expand = function(args)
        luasnip.lsp_expand(args.body)
      end,
    },
    mapping = cmp.mapping.preset.insert({
      ['<CR>'] = cmp.mapping.confirm({ select = true }),
    }),
    sources = cmp.config.sources({
      { name = 'nvim_lsp' },
      { name = 'luasnip' },
      { name = 'path' },
    }, {
      { name = 'buffer' },
    }),
    window = {
      completion = {
        border = 'rounded',
        winhighlight = 'Normal:Pmenu,FloatBorder:Pmenu,CursorLine:PmenuSel,Search:None',
      },
      documentation = {
        border = 'rounded',
        winhighlight = 'Normal:Pmenu,FloatBorder:Pmenu',
      },
    },
    formatting = {
      format = function(entry, item)
        local source_names = {
          nvim_lsp = '[LSP]',
          luasnip = '[Snp]',
          buffer = '[Buf]',
          path = '[Pth]',
        }
        local formatted_item = vim.tbl_extend('force', {}, item, {
          abbr = vim.fn.strcharpart(item.abbr, 0, 50),
          menu = source_names[entry.source.name] or ('[' .. entry.source.name .. ']'),
        })
        return formatted_item
      end,
    },
  })
end

return M
