-- Type hierarchy and implementation pickers. This module only dispatches:
-- Python buffers query the background AST index first (config.type_hierarchy
-- .python) with live LSP requests as fallback (config.type_hierarchy.lsp);
-- other languages go straight to the LSP paths. Shared picker plumbing lives
-- in config.type_hierarchy.core.
local core = require('config.type_hierarchy.core')
local lsp = require('config.type_hierarchy.lsp')
local python = require('config.type_hierarchy.python')

local M = {}

local function is_python(context)
  return vim.bo[context.bufnr].filetype == 'python'
end

local function supports_type_hierarchy(context)
  local clients = vim.lsp.get_clients({
    bufnr = context.bufnr,
    method = 'textDocument/prepareTypeHierarchy',
  })
  return #clients > 0
end

function M.open_subtypes()
  local context = core.current_query_context()
  local session = core.new_location_picker(
    'Derived Classes',
    core.hierarchy_entry(context.root, 'subtypes')
  )
  if is_python(context) then
    python.open_indexed_hierarchy('subtypes', function()
      lsp.open_implementation_subtypes(session, context)
    end, session, context)
    return
  end
  if supports_type_hierarchy(context) then
    lsp.open_hierarchy('subtypes', session, context)
  else
    lsp.open_implementation_subtypes(session, context)
  end
end

function M.open_supertypes()
  local context = core.current_query_context()
  local session = core.new_location_picker(
    'Base Classes',
    core.hierarchy_entry(context.root, 'supertypes')
  )
  if is_python(context) then
    python.open_indexed_hierarchy('supertypes', function()
      python.open_supertypes(session, context)
    end, session, context)
    return
  end
  if supports_type_hierarchy(context) then
    lsp.open_hierarchy('supertypes', session, context)
  else
    session:fail('unsupported by active LSP')
  end
end

function M.open_implementations()
  local context = core.current_query_context()
  local session = core.new_location_picker(
    'Implementations',
    core.implementation_entry(context.root)
  )
  if is_python(context) then
    python.open_indexed_implementations(function()
      lsp.open_implementations(session, context)
    end, session, context)
    return
  end
  lsp.open_implementations(session, context)
end

return M
