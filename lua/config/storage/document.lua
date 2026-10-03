-- Versioned JSON validation shared by the storage API and legacy import.
local M = {}

function M.decode(store, source)
  if not source then return nil end
  if #source > store.max_bytes then return nil, 'saved state exceeds the size limit' end
  local succeeded, document = pcall(vim.json.decode, source)
  if not succeeded or type(document) ~= 'table' or vim.islist(document) then
    return nil, 'saved state is not a JSON object'
  end
  if document.version ~= store.version
      and not (document.version == nil and store.accept_unversioned) then
    return nil, 'unsupported saved state version'
  end
  return document
end

function M.encode(store, document)
  if type(document) ~= 'table' or (vim.islist(document) and next(document) ~= nil) then
    return nil, 'state must be an object'
  end
  local saved_document = vim.deepcopy(document)
  saved_document.version = store.version
  local succeeded, source = pcall(vim.json.encode, saved_document)
  if not succeeded then return nil, 'state is not JSON serializable' end
  if #source > store.max_bytes then return nil, 'state exceeds the size limit' end
  return source
end

return M
