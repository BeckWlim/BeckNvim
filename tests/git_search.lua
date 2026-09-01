local replaced_modules = {
  'config.git',
  'config.git.diffview',
  'config.git.github',
  'config.git.issue',
  'config.git.repository',
  'config.git.search',
  'config.search.telescope',
  'telescope.actions',
  'telescope.actions.state',
  'telescope.pickers',
  'telescope.previewers',
  'telescope.previewers.utils',
  'telescope.sorters',
}
local original_modules = {}
for _, module_name in ipairs(replaced_modules) do
  original_modules[module_name] = package.loaded[module_name]
end

local commit_callback
local branch_callback
local picker_close_calls = 0
local detach_call
local exit_calls = 0
local issue_callback
local issue_open
local mapped_actions = {}
local picker
local picker_options
local picker_spec
local selected_entry
local select_action
local jump_call
local branch_switch_call
local searched_query
local preview_buffer = vim.api.nvim_create_buf(false, true)
local preview_window = vim.api.nvim_open_win(preview_buffer, false, {
  col = 0,
  height = 2,
  relative = 'editor',
  row = 0,
  width = 20,
})

package.loaded['config.git.repository'] = {
  commands = {
    branches = function()
      return { 'git', 'branches' }
    end,
    search_commits = function(query, history_options)
      searched_query = query
      return { 'git', 'log', query, history_options.kind }
    end,
    branch_preview = function()
      return { 'git', 'branch-preview' }
    end,
    commit_preview = function()
      return { 'git', 'commit-preview' }
    end,
  },
  concise_error = function(process)
    return process.stderr
  end,
  parse_commit_search = function()
    return {
      {
        abbreviated_hash = 'exact',
        author = 'A',
        date = '2026-09-01',
        hash = string.rep('a', 40),
        source = 'LOCAL',
        source_ref = searched_query == 'remote-match' and 'origin/topic' or 'main',
        subject = 'Fix cache accounting (#3452)',
      },
    }
  end,
  parse_branches = function()
    return {
      {
        current = true,
        date = '2026-09-01',
        is_remote = false,
        local_name = 'main',
        refname = 'refs/heads/main',
        short_name = 'main',
        subject = 'Current work',
        track_remote = false,
        upstream = 'origin/main',
      },
      {
        current = false,
        date = '2026-08-31',
        is_remote = true,
        local_name = 'topic',
        refname = 'refs/remotes/origin/topic',
        short_name = 'origin/topic',
        subject = 'Remote work',
        track_remote = true,
        upstream = '',
      },
    }
  end,
  parse_commit_preview = function()
    return {
      {
        abbreviated_hash = 'aaaaaaaa',
        author = 'A',
        date = '2026-09-01',
        files = { { path = 'lua/example.lua', status = 'M' } },
        hash = string.rep('a', 40),
        subject = 'Fix cache accounting (#3452)',
      },
    }
  end,
  start = function(command, _, callback)
    if command[2] == 'branches' then
      branch_callback = callback
    else
      commit_callback = callback
    end
    return function() end
  end,
}
package.loaded['config.git.github'] = {
  fetch_issue = function(_, _, callback)
    issue_callback = callback
    return function() end
  end,
}
package.loaded['config.git.issue'] = {
  open_file = function(root, issue, options)
    issue_open = { issue = issue, options = options, root = root }
  end,
  render_buffer = function() end,
}
package.loaded['config.git.diffview'] = {
  close = function()
    exit_calls = exit_calls + 1
  end,
  jump_to_search_commit = function(parent_view, history_options, commit)
    jump_call = {
      commit = commit,
      history_options = history_options,
      parent_view = parent_view,
    }
  end,
}
package.loaded['config.git'] = {
  detach_commit_overview = function(root, commit_id, parent_view, commit_context)
    detach_call = {
      commit_context = commit_context,
      commit_id = commit_id,
      parent_view = parent_view,
      root = root,
    }
  end,
  switch_to_branch = function(root, branch, parent_view)
    branch_switch_call = { branch = branch, parent_view = parent_view, root = root }
  end,
}
package.loaded['config.search.telescope'] = { focus_preview = function() end }
local select_default_action = setmetatable({
  replace = function(_, callback)
    select_action = callback
  end,
}, {
  __call = function(_, active_prompt_buffer)
    select_action(active_prompt_buffer)
  end,
})
package.loaded['telescope.actions'] = {
  close = function()
    picker_close_calls = picker_close_calls + 1
  end,
  select_default = select_default_action,
}
package.loaded['telescope.actions.state'] = {
  get_current_picker = function()
    return picker
  end,
  get_selected_entry = function()
    return selected_entry
  end,
}
package.loaded['telescope.pickers'] = {
  new = function(options, specification)
    picker_options = options
    picker_spec = specification
    picker = {
      find = function() end,
    }
    specification.attach_mappings(41, function(_, lhs, callback)
      mapped_actions[lhs] = callback
    end)
    return picker
  end,
}
package.loaded['telescope.previewers'] = {
  new_buffer_previewer = function(options)
    return options
  end,
}
package.loaded['telescope.previewers.utils'] = {
  highlighter = function() end,
  job_maker = function() end,
}
package.loaded['telescope.sorters'] = { empty = function() return {} end }
package.loaded['config.git.search'] = nil

local parent_view = { tabpage = vim.api.nvim_get_current_tabpage() }
local history_options = { kind = 'repository', location = { root = '/work/repository' } }
local search = require('config.git.search')
assert(search.open('/work/repository', history_options, parent_view))
assert(
  picker_spec
    and picker_spec.prompt_title == 'Git Search · Enter: open'
    and picker_spec.previewer.title == 'Git Result Preview'
    and picker_options.default_text == nil,
  'Git search did not open directly as a Telescope list with preview and prompt'
)

local emitted_records = {}
local finder_completed = false
picker_spec.finder('#3452', function(record)
  emitted_records[#emitted_records + 1] = record
end, function()
  finder_completed = true
end)
assert(vim.wait(300, function()
  return branch_callback ~= nil and commit_callback ~= nil and issue_callback ~= nil
end, 10), 'Live Telescope query did not dispatch scoped Git and GitHub requests')
issue_callback({
  author = 'maintainer',
  body = 'Issue body',
  comments = 0,
  created_at = '2026-09-01T00:00:00Z',
  html_url = 'https://github.com/example/repository/issues/3452',
  kind = 'Issue',
  labels = {},
  number = 3452,
  state = 'open',
  title = 'Reduce RSS',
  updated_at = '2026-09-01T00:00:00Z',
})
assert(#emitted_records == 0, 'Early issue result appeared before ordered commit results')
branch_callback({ code = 0, stderr = '', stdout = 'ignored by mock' })
commit_callback({ code = 0, stderr = '', stdout = 'ignored by mock' })
assert(
  finder_completed
    and #emitted_records == 3
    and emitted_records[1].kind == 'branch'
    and emitted_records[1].display_text:match('LOCAL')
    and emitted_records[2].kind == 'commit'
    and emitted_records[2].level == 1
    and emitted_records[3].kind == 'issue'
    and emitted_records[3].display_text:match('REMOTE'),
  'Live number search did not render branch, commit child, and issue hierarchy'
)
assert(
  mapped_actions['<C-q>'] and mapped_actions['<Tab>'] and picker.ctrl_q_action,
  'Live Git search lost layered close or actionable preview navigation'
)
mapped_actions['<C-q>'](41)
assert(
  picker_close_calls == 1 and exit_calls == 0,
  'Git-search Ctrl-Q did not pop only the active search panel'
)

selected_entry = emitted_records[1]
select_action(41)
assert(
  branch_switch_call
    and branch_switch_call.root == '/work/repository'
    and branch_switch_call.parent_view == parent_view
    and branch_switch_call.branch.short_name == 'main',
  'Selecting a branch root did not dispatch in-mode guarded branch checkout'
)
vim.api.nvim_buf_set_lines(preview_buffer, 0, -1, false, {
  'branch header',
  ' file.lua | 2 +-',
})
vim.b[preview_buffer].git_search_commit_by_line = {
  false,
  string.rep('a', 40),
}
picker.previewer = { state = { winid = preview_window } }
branch_switch_call = nil
jump_call = nil
detach_call = nil
local close_calls_before_unmapped_preview = picker_close_calls
vim.api.nvim_win_set_cursor(preview_window, { 1, 0 })
picker.preview_enter_action(41)
assert(
  not branch_switch_call
    and not jump_call
    and not detach_call
    and picker_close_calls == close_calls_before_unmapped_preview,
  'An unmapped branch-preview line fell through to branch checkout'
)
vim.api.nvim_win_set_cursor(preview_window, { 2, 0 })
picker.preview_enter_action(41)
assert(
  jump_call
    and jump_call.parent_view == parent_view
    and jump_call.commit.hash == string.rep('a', 40)
    and jump_call.commit.branch_name == 'main'
    and jump_call.commit.source == 'LOCAL'
    and not detach_call,
  'A commit line in the branch preview did not open read-only review at that exact commit'
)
vim.api.nvim_win_close(preview_window, true)
selected_entry = emitted_records[2]
detach_call = nil
jump_call = nil
select_action(41)
assert(
  jump_call
    and jump_call.parent_view == parent_view
    and jump_call.commit.hash == string.rep('a', 40)
    and jump_call.commit.branch_name == 'main'
    and not detach_call,
  'Selecting a commit did not dispatch read-only review to the exact revision'
)
selected_entry = emitted_records[3]
picker.preview_enter_action(41)
assert(
  issue_open
    and issue_open.issue.number == 3452
    and type(issue_open.options.return_to_results) == 'function',
  'Pressing Enter on an issue preview did not preserve its owning search list'
)
local later_query_records = {}
picker_spec.finder('dcedb0b', function(record)
  later_query_records[#later_query_records + 1] = record
end, function() end)
assert(#later_query_records == 1, 'Query-state mutation fixture did not execute')
issue_open.options.return_to_results()
assert(
  picker_options.default_text == '#3452',
  'Returning from issue detail did not restore the query captured at dispatch time'
)

local commit_id_records = {}
local commit_id_complete = false
picker_spec.finder('dcedb0b', function(record)
  commit_id_records[#commit_id_records + 1] = record
end, function()
  commit_id_complete = true
end)
assert(
  commit_id_complete
    and #commit_id_records == 1
    and commit_id_records[1].kind == 'commit_id',
  'Commit ID did not become an immediate Telescope dispatch choice'
)
selected_entry = commit_id_records[1]
detach_call = nil
jump_call = nil
select_action(41)
assert(
  jump_call
    and jump_call.parent_view == parent_view
    and jump_call.commit.hash == 'dcedb0b'
    and not detach_call,
  'Commit-ID choice did not open a read-only in-mode commit review'
)

assert(
  picker_close_calls == 6 and exit_calls == 0,
  'Git-search selections did not close their picker before dispatch'
)

branch_callback = nil
commit_callback = nil
local remote_records = {}
local remote_complete = false
picker_spec.finder('remote-match', function(record)
  remote_records[#remote_records + 1] = record
end, function()
  remote_complete = true
end)
assert(vim.wait(300, function()
  return branch_callback ~= nil and commit_callback ~= nil
end, 10), 'Remote-ref Git query did not start')
branch_callback({ code = 0, stderr = '', stdout = 'ignored by mock' })
commit_callback({ code = 0, stderr = '', stdout = 'ignored by mock' })
assert(
  remote_complete
    and #remote_records == 2
    and remote_records[1].kind == 'branch'
    and remote_records[1].branch.short_name == 'origin/topic'
    and remote_records[2].kind == 'commit'
    and remote_records[2].commit.source == 'REMOTE',
  'Git search did not group a matched commit beneath its remote source branch'
)

for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
