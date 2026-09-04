local replaced_modules = {
  'config.git.footer_loader',
  'config.git.repository',
}
local original_modules = {}
for _, module_name in ipairs(replaced_modules) do
  original_modules[module_name] = package.loaded[module_name]
end

local started_commands = {}
local ancestor_result = { code = 0, stderr = '', stdout = '' }
local position_result = { code = 0, stderr = '', stdout = '142\n' }
local list_pages = {}

local repository = {
  footer_detail_batch_entries = 2,
  footer_detail_worker_count = 4,
  footer_list_batch_entries = 200,
  footer_list_margin_entries = 30,
  footer_list_max_entries = 600,
  footer_preview_headroom_entries = 60,
  footer_request_timeout_ms = 10000,
  unbounded_history_entries = 100000,
  commands = {
    commit_is_ancestor = function(commit_hash, refname)
      return { 'ancestor', commit_hash, refname }
    end,
    commit_position = function(commit_hash, refname)
      return { 'position', commit_hash, refname }
    end,
    history_rows = function(_, skip_count, row_count)
      return { 'rows', tostring(skip_count), tostring(row_count) }
    end,
  },
  concise_error = function(process)
    return process.stderr
  end,
  parse_count = function(output)
    return tonumber(vim.trim(output or ''))
  end,
  parse_history_rows = function(output)
    return vim.deepcopy(list_pages[output] or {})
  end,
  start = function(command, _, callback)
    started_commands[#started_commands + 1] = vim.deepcopy(command)
    if command[1] == 'ancestor' then
      callback(ancestor_result)
    elseif command[1] == 'position' then
      callback(position_result)
    else
      local page_key = ('page:%s:%s'):format(command[2], command[3])
      callback({ code = 0, stderr = '', stdout = page_key })
    end
    return function() end
  end,
}
package.loaded['config.git.repository'] = repository
package.loaded['config.git.footer_loader'] = nil

local loader = require('config.git.footer_loader')
local selected_commit = string.rep('a', 40)
list_pages['page:3:200'] = {
  { hash = selected_commit },
}
local prepared_options
loader.prepare_selected('/work/repository', {
  checked_out_branch = 'main',
  preview_commit = selected_commit,
  selected_commit = selected_commit,
}, function(history_options)
  prepared_options = history_options
end)
assert(
  prepared_options
    and prepared_options.branch_name == 'main'
    and prepared_options.history_ref == 'refs/heads/main'
    and prepared_options.source == 'LOCAL'
    and prepared_options.window_start_offset == 3
    and prepared_options.preloaded_history_count == 200
    and prepared_options.preloaded_history_output == 'page:3:200'
    and prepared_options.preview_commit == selected_commit,
  'Selected commit did not preload a top-priority metadata batch around itself'
)
assert(
  vim.deep_equal(started_commands, {
    { 'ancestor', selected_commit, 'refs/heads/main' },
    { 'position', selected_commit, 'refs/heads/main' },
    { 'rows', '3', '200' },
  }),
  'Selected commit window did not preload metadata after resolving its position'
)

list_pages['page:3:200'] = nil
local missing_window_options
loader.prepare_selected('/work/repository', {
  branch_name = 'main',
  checked_out_branch = 'main',
  history_ref = 'refs/heads/main',
  selected_commit = selected_commit,
}, function(history_options)
  missing_window_options = history_options
end)
assert(
  missing_window_options
    and missing_window_options.history_ref == nil
    and missing_window_options.branch_name == nil
    and missing_window_options.revision == selected_commit
    and missing_window_options.preloaded_history_output == nil,
  'A branch metadata window missing its jump target did not fall back to the exact object'
)

ancestor_result = { code = 1, stderr = '', stdout = '' }
list_pages['page:0:1'] = { { hash = selected_commit } }
list_pages['page:0:200'] = { { hash = string.rep('b', 40) } }
local unrelated_options
loader.prepare_selected('/work/repository', {
  anchor_plan = {
    branch_name = 'origin/topic',
    branch_ref = 'refs/remotes/origin/topic',
  },
  branch_name = 'origin/topic',
  checked_out_branch = 'main',
  history_ref = 'refs/remotes/origin/topic',
  preloaded_history_count = 600,
  preloaded_history_output = 'stale metadata',
  preview_commit = selected_commit,
  review_only = true,
  selected_commit = selected_commit,
}, function(history_options)
  unrelated_options = history_options
end)
assert(
  unrelated_options
    and unrelated_options.anchor_plan == nil
    and unrelated_options.branch_name == 'main'
    and unrelated_options.history_ref == 'refs/heads/main'
    and unrelated_options.revision == nil
    and unrelated_options.independent_preview_commit == selected_commit
    and unrelated_options.preloaded_history_count == 200
    and unrelated_options.preloaded_history_output == 'page:0:1page:0:200'
    and unrelated_options.preview_commit == selected_commit,
  'A commit outside the current branch did not become an independent footer preview'
)
assert(
  vim.deep_equal(vim.list_slice(started_commands, #started_commands - 2), {
    { 'ancestor', selected_commit, 'refs/heads/main' },
    { 'rows', '0', '1' },
    { 'rows', '0', '200' },
  }),
  'Search-selected commit containment trusted its owning ref instead of current HEAD'
)

local commands_before_missing_branch = #started_commands
local missing_branch_options
loader.prepare_selected('/work/repository', {
  branch_name = 'origin/topic',
  history_ref = 'refs/remotes/origin/topic',
  require_checked_out_containment = true,
  selected_commit = selected_commit,
}, function(history_options)
  missing_branch_options = history_options
end)
assert(
  missing_branch_options
    and missing_branch_options.branch_name == nil
    and missing_branch_options.history_ref == nil
    and missing_branch_options.revision == selected_commit
    and #started_commands == commands_before_missing_branch,
  'Commit search without a settled current branch trusted the result owning ref'
)

assert(loader.initial_limit({}) == 1, 'Ordinary history should mount one native seed entry')
assert(
  loader.initial_limit({ unbounded = true }) == 100000,
  'Explicit mutation rendering lost its exceptional full-history ceiling'
)
assert(
  loader.initial_ref({ selected_commit = selected_commit, history_ref = 'refs/heads/main' })
    == 'refs/heads/main',
  'A searched commit displaced the recent branch tip as the native seed'
)
local filling_view = {
  git_footer_loader = {
    list_installing = false,
    list_loading = 'older',
    list_ready = true,
  },
}
assert(
  loader.list_is_ready(filling_view) and not loader.window_is_settled(filling_view),
  'The first metadata batch did not become interactive before background window fill'
)
assert(
  loader.cursor_direction({ list_ready = true, newer_complete = false }, 30, 200) == 'newer'
    and loader.cursor_direction({ list_ready = true, newer_complete = true }, 171, 200) == 'older'
    and loader.cursor_direction({ list_ready = true, newer_complete = true }, 100, 200) == nil,
  'List-window margin detection did not support direct cursor jumps'
)
assert(
  loader.boundary_load_count({ rows = vim.fn.range(1, 200) }) == 400
    and loader.boundary_load_count({ rows = vim.fn.range(1, 600) }) == 200,
  'Boundary loading did not fill unused metadata capacity in one request'
)

local function make_row(index)
  return {
    author = 'Author',
    hash = ('%040d'):format(index),
    parent_hashes = { ('%040d'):format(math.max(0, index - 1)) },
    ref_names = '',
    reflog_selector = '',
    rel_date = 'now',
    subject = 'Commit ' .. index,
    time = index,
    time_offset = '+0000',
  }
end

local existing_rows = {}
for row_index = 1, 500 do
  existing_rows[#existing_rows + 1] = make_row(row_index)
end
local older_rows = {}
for row_index = 501, 700 do
  older_rows[#older_rows + 1] = make_row(row_index)
end
local merged_rows, added_count, trimmed_count = loader.merge_rows(
  existing_rows,
  older_rows,
  'older',
  600
)
assert(
  #merged_rows == 600
    and added_count == 200
    and trimmed_count == 100
    and merged_rows[1].hash == make_row(101).hash
    and merged_rows[600].hash == make_row(700).hash,
  'The larger commit-list window did not trim from the opposite edge'
)

local initial_rows = {}
for row_index = 4, 203 do
  initial_rows[#initial_rows + 1] = make_row(row_index)
end
list_pages['page:3:200'] = initial_rows
local window_fill_rows = {}
for row_index = 204, 603 do
  window_fill_rows[#window_fill_rows + 1] = make_row(row_index)
end
list_pages['page:203:400'] = window_fill_rows
local older_page = {}
for row_index = 604, 803 do
  older_page[#older_page + 1] = make_row(row_index)
end
list_pages['page:603:200'] = older_page

local panel = { entries = {}, cur_item = {} }
local view = {
  git_repository_root = '/work/repository',
  panel = panel,
}
local hydrated_hashes = {}
local released_count = 0
local selected_entry
local commands_before_attach = #started_commands
local function install_rows(_, rows, _, completion_callback)
  local current_entry = panel.cur_item and panel.cur_item[1]
  local current_hash = current_entry and current_entry.commit.hash
  local existing_entries = {}
  for _, entry in ipairs(panel.entries) do
    existing_entries[entry.commit.hash] = entry
  end
  local entries = {}
  local retained_cursor_entry
  for _, row in ipairs(rows) do
    local entry = existing_entries[row.hash] or {
        commit = { hash = row.hash },
        files = { {} },
        git_details_loaded = false,
        git_details_loading = false,
      }
    entries[#entries + 1] = entry
    if row.hash == make_row(143).hash then
      selected_entry = entry
    end
    if row.hash == current_hash then
      retained_cursor_entry = entry
    end
  end
  panel.entries = entries
  retained_cursor_entry = retained_cursor_entry or entries[1]
  panel.cur_item = { retained_cursor_entry }
  completion_callback(true, retained_cursor_entry)
end
local attached = loader.attach(view, {
  history_ref = 'refs/heads/main',
  location = { root = '/work/repository' },
  selected_commit = make_row(143).hash,
  preloaded_history_count = 200,
  preloaded_history_output = 'page:3:200',
  window_start_offset = 3,
}, {
  hydrate_entry = function(_, entry, completion_callback)
    hydrated_hashes[#hydrated_hashes + 1] = entry.commit.hash
    completion_callback(true)
    return function() end
  end,
  install_rows = install_rows,
  release_entries = function(_, entries)
    released_count = released_count + #entries
    for _, entry in ipairs(entries) do
      entry.git_details_loaded = false
    end
  end,
})
assert(attached, 'The shared footer loader did not attach')
assert(vim.wait(200, function()
  return loader.list_is_ready(view) and #panel.entries == 600
end, 10), 'The asynchronous metadata window did not settle')
assert(
  #started_commands == commands_before_attach + 1
    and vim.deep_equal(started_commands[#started_commands], { 'rows', '203', '400' })
    and #panel.entries == 600
    and #hydrated_hashes == 600
    and hydrated_hashes[1] == make_row(4).hash
    and hydrated_hashes[600] == make_row(603).hash
    and panel.cur_item[1] ~= selected_entry,
  'Metadata did not fill before top-first asynchronous detail loading'
)

local jumped_entry = panel.entries[100]
panel.cur_item = { jumped_entry }
loader.on_cursor(view, jumped_entry)
assert(
  #hydrated_hashes == 600 and released_count == 0,
  'A direct cursor jump rebuilt or released the persistent detail queue'
)

local bottom_entry = panel.entries[580]
panel.cur_item = { bottom_entry }
loader.on_cursor(view, bottom_entry)
assert(
  #panel.entries == 600
    and view.git_footer_loader.start_offset == 203
    and panel.entries[1].commit.hash == make_row(204).hash
    and panel.entries[600].commit.hash == make_row(803).hash
    and #hydrated_hashes == 800
    and hydrated_hashes[601] == make_row(604).hash
    and hydrated_hashes[800] == make_row(803).hash,
  'A bottom-margin jump did not append the next lightweight commit batch'
)

loader.detach(view)
assert(view.git_footer_loader == nil, 'Footer loader detach left live state behind')

local worker_rows = {}
for row_index = 1, 6 do
  worker_rows[#worker_rows + 1] = make_row(row_index)
end
list_pages['worker-page'] = worker_rows
local worker_panel = { entries = {}, cur_item = {} }
local worker_view = {
  git_repository_root = '/work/repository',
  panel = worker_panel,
}
local active_requests = 0
local maximum_active_requests = 0
local pending_requests = {}
local prioritized_completion = false
loader.attach(worker_view, {
  history_ref = 'refs/heads/main',
  preloaded_history_count = 200,
  preloaded_history_output = 'worker-page',
  window_start_offset = 0,
}, {
  hydrate_entry = function(_, entry, completion_callback)
    active_requests = active_requests + 1
    maximum_active_requests = math.max(maximum_active_requests, active_requests)
    pending_requests[#pending_requests + 1] = {
      callback = completion_callback,
      entry = entry,
    }
    return function() end
  end,
  install_rows = function(_, rows, _, completion_callback)
    local installed_entries = {}
    for _, row in ipairs(rows) do
      installed_entries[#installed_entries + 1] = {
        commit = { hash = row.hash },
        git_details_loaded = false,
        git_details_loading = false,
      }
    end
    worker_panel.entries = installed_entries
    worker_panel.cur_item = { installed_entries[1] }
    completion_callback(true, installed_entries[1])
  end,
})
assert(vim.wait(200, function()
  return #pending_requests == 3
end, 10), 'The detail worker pool did not start its top-order background preload')
for request_index = 1, 3 do
  assert(
    pending_requests[request_index].entry == worker_panel.entries[request_index],
    'The detail worker pool did not preserve top-to-bottom priority'
  )
end
loader.ensure_entry(worker_view, worker_panel.entries[6], function(succeeded)
  prioritized_completion = succeeded
end)
assert(
  #pending_requests == 4
    and pending_requests[4].entry == worker_panel.entries[6]
    and maximum_active_requests == 4,
  'An explicit commit action did not take the reserved detail worker'
)
local completion_index = 1
while completion_index <= #pending_requests do
  active_requests = active_requests - 1
  pending_requests[completion_index].callback(true)
  completion_index = completion_index + 1
end
assert(
  prioritized_completion
    and #pending_requests == 6
    and pending_requests[5].entry == worker_panel.entries[4]
    and pending_requests[6].entry == worker_panel.entries[5]
    and active_requests == 0,
  'The bounded detail queue did not finish after its explicit priority override'
)
loader.detach(worker_view)

local batch_panel = { entries = {}, cur_item = {} }
local batch_view = {
  git_repository_root = '/work/repository',
  panel = batch_panel,
}
local detail_batches = {}
local active_batch_completion = false
loader.attach(batch_view, {
  history_ref = 'refs/heads/main',
  preloaded_history_count = 200,
  preloaded_history_output = 'worker-page',
  window_start_offset = 0,
}, {
  hydrate_entries = function(_, entries, completion_callback)
    detail_batches[#detail_batches + 1] = {
      callback = completion_callback,
      entries = entries,
    }
    return function() end
  end,
  hydrate_entry = function()
    error('Top-order background preload unexpectedly used a single-entry request')
  end,
  install_rows = function(_, rows, _, completion_callback)
    local installed_entries = {}
    for _, row in ipairs(rows) do
      installed_entries[#installed_entries + 1] = {
        commit = { hash = row.hash },
        git_details_loaded = false,
        git_details_loading = false,
      }
    end
    batch_panel.entries = installed_entries
    batch_panel.cur_item = { installed_entries[1] }
    completion_callback(true, installed_entries[1])
  end,
})
assert(vim.wait(200, function()
  return #detail_batches == 3
end, 10), 'Background detail workers did not claim configured commit batches')
assert(
  #detail_batches[1].entries == 2
    and detail_batches[1].entries[1].commit.hash == make_row(1).hash
    and detail_batches[1].entries[2].commit.hash == make_row(2).hash
    and detail_batches[2].entries[1].commit.hash == make_row(3).hash
    and detail_batches[3].entries[2].commit.hash == make_row(6).hash,
  'Commit detail batches did not preserve strict top-to-bottom order'
)
loader.ensure_entry(batch_view, batch_panel.entries[1], function(succeeded)
  active_batch_completion = succeeded
end)
for _, detail_batch in ipairs(detail_batches) do
  local results = {}
  for _, entry in ipairs(detail_batch.entries) do
    results[entry] = true
  end
  detail_batch.callback(results)
end
assert(
  active_batch_completion
    and batch_view.git_footer_loader.detail_active == 0
    and #batch_view.git_footer_loader.detail_queue == 0,
  'An explicit waiter attached to an active detail batch did not complete'
)
loader.detach(batch_view)

for module_name, original_module in pairs(original_modules) do
  package.loaded[module_name] = original_module
end
