local original_buf_request_all = vim.lsp.buf_request_all
local original_get_client_by_id = vim.lsp.get_client_by_id
local original_get_clients = vim.lsp.get_clients
local original_locations_to_items = vim.lsp.util.locations_to_items
local original_make_position_params = vim.lsp.util.make_position_params
local original_show_document = vim.lsp.util.show_document
local original_get_string_parser = vim.treesitter.get_string_parser
local original_get_language = vim.treesitter.language.get_lang
local original_get_query = vim.treesitter.query.get
local original_type_information = package.loaded['config.type_information']

local source_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(source_buffer)
vim.api.nvim_buf_set_name(source_buffer, vim.fs.joinpath(vim.fn.getcwd(), 'type_info_test.py'))
vim.api.nvim_buf_set_lines(source_buffer, 0, -1, false, { 'value = make_widget()' })
vim.bo[source_buffer].filetype = 'python'

local request_callbacks = {}
local cancelled_methods = {}
local shown_location
local shown_encoding
local shown_options
local active_client = { id = 17, name = 'basedpyright', offset_encoding = 'utf-16' }

rawset(vim.lsp, 'get_clients', function(options)
  if options and (options.method == 'textDocument/hover'
    or options.method == 'textDocument/typeDefinition'
  ) then
    return { active_client }
  end
  return {}
end)
rawset(vim.lsp, 'get_client_by_id', function(client_id)
  return client_id == active_client.id and active_client or nil
end)
rawset(vim.lsp, 'buf_request_all', function(bufnr, method, params, callback)
  assert(bufnr == source_buffer, 'type information queried the floating buffer')
  assert(type(params) == 'function', 'type information did not create client-aware params')
  request_callbacks[method] = callback
  return function()
    cancelled_methods[method] = true
  end
end)
rawset(vim.lsp.util, 'make_position_params', function(window, offset_encoding)
  assert(vim.api.nvim_win_is_valid(window), 'type information lost its source window')
  assert(offset_encoding == active_client.offset_encoding, 'type information used wrong encoding')
  return { textDocument = {}, position = {} }
end)
rawset(vim.lsp.util, 'locations_to_items', function(locations, offset_encoding)
  assert(offset_encoding == active_client.offset_encoding, 'definition used wrong encoding')
  return vim.tbl_map(function(_location)
    return {
      filename = vim.fs.joinpath(vim.fn.getcwd(), 'widget.py'),
      lnum = 8,
      col = 1,
      text = 'class Widget:',
      user_data = _location,
    }
  end, locations)
end)
rawset(vim.lsp.util, 'show_document', function(location, offset_encoding, options)
  shown_location = location
  shown_encoding = offset_encoding
  shown_options = options
  return true
end)
rawset(vim.treesitter.language, 'get_lang', function(filetype)
  return filetype
end)
local highlight_query = {
  captures = { 'type' },
  iter_captures = function()
    local capture_returned = false
    return function()
      if capture_returned then
        return nil
      end
      capture_returned = true
      return 1, {
        range = function()
          return 0, 0, 0, 4
        end,
      }
    end
  end,
}
rawset(vim.treesitter.query, 'get', function()
  return highlight_query
end)
rawset(vim.treesitter, 'get_string_parser', function(_source, language)
  return {
    parse = function() end,
    for_each_tree = function(_, callback)
      callback(
        { root = function() return {} end },
        { lang = function() return language end }
      )
    end,
  }
end)

package.loaded['config.type_information'] = nil
local type_information = require('config.type_information')
type_information.toggle()

local float_window = vim.api.nvim_get_current_win()
local float_buffer = vim.api.nvim_get_current_buf()
assert(float_buffer ~= source_buffer, 'type information did not focus its floating window')
assert(vim.bo[float_buffer].filetype == 'text', 'type information float is not plain text')
assert(vim.wo[float_window].linebreak, 'type information did not enable word-aware wrapping')
assert(vim.wo[float_window].showbreak == '↳ ', 'wrapped type information has no continuation mark')
assert(vim.wo[float_window].cursorline, 'type-definition selection has no cursor line')
assert(request_callbacks['textDocument/hover'], 'type information did not request hover')
assert(
  request_callbacks['textDocument/typeDefinition'],
  'type information did not request type definitions'
)

request_callbacks['textDocument/hover']({
  [active_client.id] = {
    result = {
      contents = {
        kind = 'markdown',
        value = table.concat({
          '```python',
          '(variable) value: Widget',
          '```',
          '---',
          'Parameters for dec\\_lock\\_ref operation.',
        }, '\n'),
      },
    },
  },
})
request_callbacks['textDocument/typeDefinition']({
  [active_client.id] = {
    result = {
      {
        uri = 'file:///unused/widget.py',
        range = {
          start = { line = 7, character = 0 },
          ['end'] = { line = 7, character = 6 },
        },
      },
    },
  },
})

local python_content = table.concat(
  vim.api.nvim_buf_get_lines(float_buffer, 0, -1, false),
  '\n'
)
assert(python_content:find('value: Widget', 1, true), 'inferred Python type was not rendered')
assert(python_content:find('widget.py:8:1', 1, true), 'Python type location was not rendered')
assert(python_content:find('class Widget:', 1, true), 'Python definition preview was not rendered')
assert(not python_content:find('```', 1, true), 'type information retained Markdown fences')
assert(
  python_content:find('dec_lock_ref operation', 1, true),
  'hover text retained Markdown escapes'
)
assert(not python_content:find('\n  ---\n', 1, true), 'hover text retained a Markdown separator')
local type_namespace = vim.api.nvim_get_namespaces().type_information
local type_extmarks = vim.api.nvim_buf_get_extmarks(
  float_buffer,
  type_namespace,
  0,
  -1,
  { details = true }
)
local treesitter_highlight_found = vim.iter(type_extmarks):any(function(extmark)
  return extmark[4].hl_group == '@type.python'
end)
assert(treesitter_highlight_found, 'Python code did not receive Treesitter captures')
local location_highlight_found = vim.iter(type_extmarks):any(function(extmark)
  return extmark[4].hl_group == 'TypeInformationLocation'
end)
local preview_highlight_found = vim.iter(type_extmarks):any(function(extmark)
  return extmark[4].hl_group == 'TypeInformationPreview'
end)
assert(location_highlight_found, 'type-definition path did not receive list styling')
assert(preview_highlight_found, 'type-definition source did not receive preview styling')

local jump_mapping = vim.fn.maparg('<CR>', 'n', false, true)
assert(type(jump_mapping.callback) == 'function', 'type float has no direct-jump mapping')
jump_mapping.callback()
assert(not vim.api.nvim_win_is_valid(float_window), '<CR> did not close type information')
assert(shown_location and shown_location.uri, '<CR> did not pass the selected LSP location')
assert(shown_encoding == 'utf-16', '<CR> did not preserve the Python position encoding')
assert(shown_options.focus and shown_options.reuse_win, '<CR> did not focus the definition')
assert(cancelled_methods['textDocument/hover'], 'closing did not cancel the hover request')
assert(
  cancelled_methods['textDocument/typeDefinition'],
  'closing did not cancel the type-definition request'
)

vim.api.nvim_set_current_buf(source_buffer)
vim.bo[source_buffer].filetype = 'cpp'
active_client = { id = 23, name = 'clangd', offset_encoding = 'utf-8' }
request_callbacks = {}
cancelled_methods = {}
shown_location = nil
shown_encoding = nil
shown_options = nil
type_information.toggle()
local cpp_float_window = vim.api.nvim_get_current_win()
local cpp_float_buffer = vim.api.nvim_get_current_buf()
request_callbacks['textDocument/hover']({
  [active_client.id] = {
    result = { contents = { kind = 'markdown', value = '```cpp\nWidget *value\n```' } },
  },
})
request_callbacks['textDocument/typeDefinition']({
  [active_client.id] = {
    result = {
      {
        targetUri = 'file:///unused/widget.hpp',
        targetRange = {
          start = { line = 3, character = 0 },
          ['end'] = { line = 3, character = 6 },
        },
        targetSelectionRange = {
          start = { line = 3, character = 6 },
          ['end'] = { line = 3, character = 12 },
        },
      },
    },
  },
})
local cpp_content = table.concat(
  vim.api.nvim_buf_get_lines(cpp_float_buffer, 0, -1, false),
  '\n'
)
assert(cpp_content:find('Widget *value', 1, true), 'clangd hover was not rendered')
assert(not cpp_content:find('```', 1, true), 'C++ result retained Markdown fences')
local cpp_jump_mapping = vim.fn.maparg('<CR>', 'n', false, true)
cpp_jump_mapping.callback()
assert(not vim.api.nvim_win_is_valid(cpp_float_window), '<CR> did not close C++ type info')
assert(shown_location and shown_location.targetUri, '<CR> lost the clangd LocationLink')
assert(shown_encoding == 'utf-8', '<CR> did not preserve the clangd position encoding')

vim.api.nvim_set_current_buf(source_buffer)
request_callbacks = {}
cancelled_methods = {}
type_information.toggle()
local closable_float_window = vim.api.nvim_get_current_win()
local close_mapping = vim.fn.maparg('<Space>k', 'n', false, true)
assert(type(close_mapping.callback) == 'function', 'type float has no <Space>k close mapping')
close_mapping.callback()
assert(
  not vim.api.nvim_win_is_valid(closable_float_window),
  '<Space>k did not close C++ type info'
)

package.loaded['config.type_information'] = original_type_information
rawset(vim.lsp, 'buf_request_all', original_buf_request_all)
rawset(vim.lsp, 'get_client_by_id', original_get_client_by_id)
rawset(vim.lsp, 'get_clients', original_get_clients)
rawset(vim.lsp.util, 'locations_to_items', original_locations_to_items)
rawset(vim.lsp.util, 'make_position_params', original_make_position_params)
rawset(vim.lsp.util, 'show_document', original_show_document)
rawset(vim.treesitter, 'get_string_parser', original_get_string_parser)
rawset(vim.treesitter.language, 'get_lang', original_get_language)
rawset(vim.treesitter.query, 'get', original_get_query)
