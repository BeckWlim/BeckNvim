-- Search the retained history model, including children absent from the rendered buffer.
local M = {}

function M.targets(entries)
  local targets = {}
  for _, entry in ipairs(entries) do
    local commit = entry.commit or {}
    targets[#targets + 1] = {
      entry = entry,
      item = entry,
      text = table.concat({ commit.hash or '', commit.subject or '', commit.author or '' }, ' '),
    }
    for _, file in ipairs(entry.files or {}) do
      targets[#targets + 1] = {
        entry = entry,
        item = file,
        text = (file.path or '') .. ' ' .. (file.oldpath or ''),
      }
    end
  end
  return targets
end

M.find = require('config.ui.tree_search').find

function M.attach(view, highlight_commit)
  local panel = view.panel
  local buffer = panel.bufid
  local generation = 0
  local direction = 1
  local temporary_entry
  view.git_search_manual_expansion = function() temporary_entry = nil end
  vim.api.nvim_create_autocmd({ 'BufLeave', 'BufWipeout' }, {
    buffer = buffer,
    callback = function() generation = generation + 1 end,
  })
  local function current_item()
    return panel:get_item_at_cursor()
  end
  local function release_expansion(next_entry)
    if temporary_entry and temporary_entry ~= next_entry then
      -- Window replacement can retire entries while a search is active.
      if vim.tbl_contains(panel.entries or {}, temporary_entry) then
        panel:set_entry_fold(temporary_entry, false)
      end
      temporary_entry = nil
    end
  end
  local function reveal(target)
    release_expansion(target.entry)
    if target.entry.folded then
      temporary_entry = target.entry
    end
    view.git_footer_cursor_hash = target.entry.commit and target.entry.commit.hash
    panel:set_entry_fold(target.entry, true)
    if target.item == target.entry then
      highlight_commit(target.entry)
    else
      panel:highlight_item(target.item)
    end
  end
  local function search(pattern, step, count, origin, preview)
    generation = generation + 1
    local token = generation
    local deadline = vim.uv.hrtime() + 10 * 1e9
    local entries = vim.list_extend({}, panel.entries or {})
    local function valid()
      if token == generation and vim.uv.hrtime() > deadline then
        generation = generation + 1
        if not preview then
          vim.notify('Git history search timed out; retry after file details load', vim.log.levels.INFO)
        end
      end
      return token == generation and vim.api.nvim_buf_is_valid(buffer)
        and vim.api.nvim_win_is_valid(panel.winid)
        and vim.api.nvim_get_current_win() == panel.winid
    end
    local function finish()
      if not valid() then
        return
      end
      -- Pending detail redraws restore their previous commit cursor. Let that
      -- shared boundary settle before applying the search selection.
      if view.git_footer_detail_render_token then
        if not preview then
          vim.defer_fn(finish, 20)
        end
        return
      end
      local target, err = M.find(M.targets(panel.entries or {}), origin, pattern, step, count, vim.o.wrapscan)
      if target then
        reveal(target)
      elseif not preview then
        vim.notify(err, vim.log.levels.INFO)
      end
    end
    local function hydrate(index)
      if not valid() then
        return
      end
      for entry_index = index, #entries do
        local entry = entries[entry_index]
        if entry.git_details_loaded == false then
          require('config.git.footer_loader').ensure_entry(view, entry, function(loaded)
            vim.schedule(function()
              if valid() and not loaded then
                generation = generation + 1
                vim.notify('Could not load Git file details; retry the search', vim.log.levels.WARN)
              elseif valid() then
                hydrate(entry_index + 1)
              end
            end)
          end)
          return
        end
      end
      finish()
    end
    if preview then
      finish()
    else
      hydrate(1)
    end
  end
  local function prompt(step)
    local origin = current_item()
    local previous_temporary_entry = temporary_entry
    local count = vim.v.count1
    local saved_search = vim.fn.getreg('/')
    local change = vim.api.nvim_create_autocmd('CmdlineChanged', {
      callback = function()
        local pattern = vim.fn.getcmdline()
        if vim.o.incsearch and pattern ~= '' then
          search(pattern, step, count, origin, true)
        end
      end,
    })
    local ok, result = pcall(vim.fn.input, {
      prompt = step == 1 and '/' or '?',
      cancelreturn = '\27',
    })
    vim.api.nvim_del_autocmd(change)
    generation = generation + 1
    if not ok or result == '\27' then
      release_expansion(previous_temporary_entry)
      if previous_temporary_entry
          and vim.tbl_contains(panel.entries or {}, previous_temporary_entry) then
        panel:set_entry_fold(previous_temporary_entry, true)
        temporary_entry = previous_temporary_entry
      end
      if origin then
        if origin.files then
          highlight_commit(origin)
        else
          panel:highlight_item(origin)
        end
      end
      return
    end
    local pattern = result ~= '' and result or saved_search
    if pattern == '' then
      return
    end
    direction = step
    vim.fn.setreg('/', pattern)
    vim.fn.histadd('search', pattern)
    vim.v.searchforward = step == 1 and 1 or 0
    search(pattern, step, count, origin, false)
  end
  local function repeat_search(factor)
    local pattern = vim.fn.getreg('/')
    if pattern ~= '' then
      search(pattern, direction * factor, vim.v.count1, current_item(), false)
    end
  end
  require('config.keybindings').attach('tree', buffer, {
    search_forward = function() prompt(1) end,
    search_backward = function() prompt(-1) end,
    next_match = function() repeat_search(1) end,
    previous_match = function() repeat_search(-1) end,
  })
end

return M
