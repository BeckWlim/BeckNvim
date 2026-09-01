local original_actions = package.loaded['telescope.actions']
local original_config = package.loaded['telescope.config']
local original_finders = package.loaded['telescope.finders']
local original_make_entry = package.loaded['telescope.make_entry']
local original_pickers = package.loaded['telescope.pickers']
local original_query_picker = package.loaded['config.search.query_picker']
local original_lsp_locations = package.loaded['config.search.lsp_locations']
local original_buf_request_all = vim.lsp.buf_request_all
local original_get_client_by_id = vim.lsp.get_client_by_id
local original_get_clients = vim.lsp.get_clients
local original_locations_to_items = vim.lsp.util.locations_to_items
local original_make_position_params = vim.lsp.util.make_position_params

local picker_opened = false
local initial_result_count = -1
local close_called = false
local latest_results = {}
local latest_title = ''
local mapped_actions = { i = {}, n = {} }
local request_callbacks = {}
local cancelled_methods = {}
local prompt_buffer = vim.api.nvim_create_buf(false, true)
local source_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(source_buffer)
vim.api.nvim_buf_set_name(source_buffer, vim.fs.joinpath(vim.fn.getcwd(), 'reference_test.py'))
vim.api.nvim_buf_set_lines(source_buffer, 0, -1, false, {
  'def use_value():',
  '    value = create_value()',
  '    print(value)',
})
vim.bo[source_buffer].filetype = 'python'
vim.api.nvim_win_set_cursor(0, { 2, 4 })

package.loaded['telescope.actions'] = {
  close = function()
    close_called = true
  end,
}
package.loaded['telescope.config'] = {
  values = {
    generic_sorter = function()
      return {}
    end,
    qflist_previewer = function()
      return {}
    end,
  },
}
package.loaded['telescope.finders'] = {
  new_table = function(specification)
    return specification.results
  end,
}
package.loaded['telescope.make_entry'] = {
  gen_from_quickfix = function()
    return function(entry)
      return entry
    end
  end,
}
package.loaded['telescope.pickers'] = {
  new = function(_, specification)
    initial_result_count = #specification.finder
    latest_title = specification.prompt_title
    return {
      layout = {
        prompt = {
          border = {
            change_title = function(_, title)
              latest_title = title
            end,
          },
        },
      },
      find = function()
        picker_opened = true
        specification.attach_mappings(prompt_buffer, function(mode, lhs, action)
          mapped_actions[mode][lhs] = action
        end)
      end,
      refresh = function(_, finder)
        latest_results = finder
      end,
    }
  end,
}
package.loaded['config.search.query_picker'] = nil
package.loaded['config.search.lsp_locations'] = nil

rawset(vim.lsp, 'get_clients', function(options)
  if options and (options.method == 'textDocument/references'
    or options.method == 'textDocument/documentHighlight'
  ) then
    return { { id = 1, offset_encoding = 'utf-16' } }
  end
  return {}
end)
rawset(vim.lsp, 'get_client_by_id', function()
  return { id = 1, offset_encoding = 'utf-16' }
end)
rawset(vim.lsp, 'buf_request_all', function(_, method, _, callback)
  request_callbacks[method] = request_callbacks[method] or {}
  table.insert(request_callbacks[method], callback)
  return function()
    cancelled_methods[method] = true
  end
end)
vim.lsp.util.make_position_params = function(_window, _offset_encoding)
  return { textDocument = {}, position = {} }
end
vim.lsp.util.locations_to_items = function(locations, _offset_encoding)
  return vim.tbl_map(function(location)
    return {
      filename = vim.uri_to_fname(location.uri),
      lnum = location.range.start.line + 1,
      col = location.range.start.character + 1,
      text = 'value',
    }
  end, locations)
end

local lsp_locations = require('config.search.lsp_locations')
lsp_locations.references()
assert(picker_opened, 'references picker did not open before the LSP request')
assert(initial_result_count == 0, 'references picker did not start empty')
assert(#latest_results == 1, 'Python local references were not populated synchronously')
assert(latest_results[1].lnum == 3, 'Python local scan found the wrong reference')
assert(latest_title:match('querying'), 'references picker did not expose query status')
assert(latest_title:match('Ctrl%-Q: cancel'), 'references picker advertised plain q as cancel')
assert(vim.wait(1000, function()
  return request_callbacks['textDocument/references'] ~= nil
    and request_callbacks['textDocument/documentHighlight'] ~= nil
end), 'reference requests were not started')

request_callbacks['textDocument/documentHighlight'][1]({
  [1] = {
    result = {
      { range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 9 } } },
      { range = { start = { line = 2, character = 10 }, ['end'] = { line = 2, character = 15 } } },
    },
  },
})
assert(#latest_results == 1, 'fast document references were not shown incrementally')
assert(latest_results[1].lnum == 3, 'the declaration line was not excluded from references')
assert(latest_title:match('1 results available'), 'partial result status was not shown')

assert(mapped_actions.i.q == nil, 'insert-mode q was consumed by the query picker')
assert(type(mapped_actions.n.q) == 'function', 'normal-mode q did not close the query picker')
assert(type(mapped_actions.i['<C-q>']) == 'function', 'insert-mode Ctrl-Q did not cancel the query')
assert(
  mapped_actions.n['<C-q>'] == nil,
  'normal-mode Ctrl-Q was captured by the query picker'
)
mapped_actions.i['<C-q>']()
assert(close_called, 'Ctrl-Q did not close the query picker')
assert(
  cancelled_methods['textDocument/references'],
  'Ctrl-Q did not cancel the full reference request'
)
assert(
  cancelled_methods['textDocument/documentHighlight'],
  'Ctrl-Q did not cancel the fast document-highlight request'
)

for method in pairs(request_callbacks) do
  request_callbacks[method] = nil
end
latest_results = {}
vim.api.nvim_buf_set_lines(source_buffer, 0, -1, false, {
  'def process_batch_result_prefill():',
  '    pass',
})
vim.api.nvim_win_set_cursor(0, { 1, 4 })
lsp_locations.references()
assert(vim.wait(1000, function()
  return request_callbacks['textDocument/references'] ~= nil
    and request_callbacks['textDocument/documentHighlight'] ~= nil
end), 'function reference requests were not started')

request_callbacks['textDocument/documentHighlight'][1]({
  [1] = {
    err = { code = -32803, message = 'auxiliary query failed' },
  },
})
request_callbacks['textDocument/references'][1]({
  [1] = {
    result = {
      {
        range = {
          start = { line = 0, character = 4 },
          ['end'] = { line = 0, character = 32 },
        },
        uri = vim.uri_from_bufnr(source_buffer),
      },
    },
  },
})
assert(#latest_results == 0, 'the source declaration was not excluded from references')
assert(latest_title:match('no results'), 'an auxiliary error incorrectly failed references')
assert(not latest_title:match('query failed'), 'references exposed the old generic failure')

for method in pairs(request_callbacks) do
  request_callbacks[method] = nil
end
latest_results = {}
lsp_locations.references()
assert(vim.wait(1000, function()
  return request_callbacks['textDocument/references'] ~= nil
    and request_callbacks['textDocument/documentHighlight'] ~= nil
end), 'retryable reference requests were not started')

request_callbacks['textDocument/documentHighlight'][1]({ [1] = { result = {} } })
request_callbacks['textDocument/references'][1]({
  [1] = {
    err = { code = -32800, message = 'Request cancelled' },
  },
})
assert(
  vim.wait(1000, function()
    return #request_callbacks['textDocument/references'] == 2
  end),
  'a cancelled reference request was not retried'
)
assert(latest_title:match('retrying'), 'the reference retry was not visible')
request_callbacks['textDocument/references'][2]({
  [1] = {
    result = {
      {
        range = {
          start = { line = 1, character = 4 },
          ['end'] = { line = 1, character = 8 },
        },
        uri = vim.uri_from_bufnr(source_buffer),
      },
    },
  },
})
assert(#latest_results == 1, 'the retried reference result was not shown')
assert(latest_title:match('1 results'), 'the retried reference query did not finish')

for method in pairs(request_callbacks) do
  request_callbacks[method] = nil
end
lsp_locations.references()
assert(vim.wait(1000, function()
  return request_callbacks['textDocument/references'] ~= nil
    and request_callbacks['textDocument/documentHighlight'] ~= nil
end), 'failing reference requests were not started')

request_callbacks['textDocument/documentHighlight'][1]({ [1] = { result = {} } })
request_callbacks['textDocument/references'][1]({
  [1] = {
    err = { code = -32803, message = 'workspace unavailable' },
  },
})
assert(
  latest_title:match('references failed: workspace unavailable'),
  'the primary LSP error was not exposed in the picker title'
)

package.loaded['telescope.actions'] = original_actions
package.loaded['telescope.config'] = original_config
package.loaded['telescope.finders'] = original_finders
package.loaded['telescope.make_entry'] = original_make_entry
package.loaded['telescope.pickers'] = original_pickers
package.loaded['config.search.query_picker'] = original_query_picker
package.loaded['config.search.lsp_locations'] = original_lsp_locations
rawset(vim.lsp, 'buf_request_all', original_buf_request_all)
rawset(vim.lsp, 'get_client_by_id', original_get_client_by_id)
rawset(vim.lsp, 'get_clients', original_get_clients)
vim.lsp.util.locations_to_items = original_locations_to_items
vim.lsp.util.make_position_params = original_make_position_params
vim.api.nvim_buf_delete(prompt_buffer, { force = true })
vim.api.nvim_buf_delete(source_buffer, { force = true })
