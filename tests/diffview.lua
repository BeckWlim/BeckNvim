local replaced_modules = {
  'config.git',
  'config.git.diffview',
  'config.git.footer_loader',
  'config.git.issue',
  'config.git.search',
  'config.search.workspace_symbols',
  'config.syntax.treesitter',
  'config.syntax.treesitter_context',
  'config.ui.statusline',
  'diffview',
  'diffview.actions',
  'diffview.async',
  'diffview.lib',
  'diffview.vcs.utils',
}
local original_modules = {}
for _, module_name in ipairs(replaced_modules) do
  original_modules[module_name] = package.loaded[module_name]
end

local configured_options
local current_view
local history_calls = {}
local opened_views = {}
local search_calls = {}
local commit_detail_calls = 0
local disposed_views = {}
local checkout_call
local native_history_selection
local enclosing_structure_line
local enclosing_structure_result
local statusline_branch_refreshes = 0
local branch_info_visible = true
local full_file_list_calls = {}
local syntax_highlight_buffers = {}
local queued_full_file_dictionary
local pending_full_file_list_callback
local defer_full_file_list = false
local defer_footer_detail = false
local footer_detail_requests = 0
local pending_footer_detail
local footer_attach_handlers
local previous_editing_tabpage

package.loaded['config.git'] = {
  branches = function() end,
  detach_commit_overview = function(root, commit_hash, parent_view, commit_context)
    checkout_call = {
      commit_context = commit_context,
      commit_hash = commit_hash,
      parent_view = parent_view,
      root = root,
    }
    return true
  end,
}
package.loaded['config.git.issue'] = {
  close = function() end,
  is_active = function()
    return false
  end,
}
package.loaded['config.git.search'] = {
  open = function(root, history_options, parent_view)
    search_calls[#search_calls + 1] = {
      history_options = history_options,
      parent_view = parent_view,
      root = root,
    }
    return true
  end,
}
package.loaded['config.git.footer_loader'] = {
  attach = function(view, history_options, handlers)
    footer_attach_handlers = handlers
    if history_options.history_ref and not history_options.unbounded then
      view.git_footer_loader = { list_ready = true }
      return true
    end
    return false
  end,
  detach = function(view)
    if view then
      view.git_footer_loader = nil
    end
    return true
  end,
  initial_limit = function(history_options)
    return history_options.unbounded and 100000 or 1
  end,
  initial_ref = function(history_options)
    return history_options.history_ref
  end,
  list_is_ready = function()
    return true
  end,
  window_is_settled = function()
    return true
  end,
  on_cursor = function() end,
  ensure_entry = function(_, entry, callback)
    footer_detail_requests = footer_detail_requests + 1
    if defer_footer_detail then
      pending_footer_detail = { callback = callback, entry = entry }
      return true
    end
    callback(entry ~= nil)
    return entry ~= nil
  end,
  prepare_selected = function(_, history_options, callback)
    local prepared_options = vim.deepcopy(history_options)
    prepared_options.window_start_offset = 0
    callback(prepared_options)
    return function() end
  end,
}
package.loaded['diffview.actions'] = {
  open_commit_log = function()
    commit_detail_calls = commit_detail_calls + 1
  end,
  select_entry = function()
    if native_history_selection then
      native_history_selection()
    end
  end,
}
package.loaded['diffview.async'] = {
  await = function(waitable)
    if type(waitable) == 'function' then
      return waitable()
    end
    return waitable
  end,
  void = function(callback)
    return function(...)
      callback(...)
    end
  end,
}
package.loaded['config.search.workspace_symbols'] = {
  definition = function(_, source_line)
    local function_name = source_line:match('^%s*local%s+function%s+([%a_][%w_]*)')
    return function_name and { kind = 'Function', name = function_name } or nil
  end,
  open_buffer = function() end,
}
package.loaded['config.syntax.treesitter_context'] = {
  enclosing_structure = function()
    return enclosing_structure_result
      or (enclosing_structure_line and { first_line = enclosing_structure_line } or nil)
  end,
}
package.loaded['config.syntax.treesitter'] = {
  ensure_highlighting = function(buffer)
    syntax_highlight_buffers[#syntax_highlight_buffers + 1] = buffer
  end,
}
package.loaded['config.ui.statusline'] = {
  refresh_git_branch = function()
    statusline_branch_refreshes = statusline_branch_refreshes + 1
    branch_info_visible = true
  end,
}
package.loaded.diffview = {
  setup = function(options)
    configured_options = options
  end,
}
package.loaded['diffview.lib'] = {
  dispose_view = function(view)
    disposed_views[#disposed_views + 1] = view
  end,
  file_history = function(range, arguments)
    history_calls[#history_calls + 1] = {
      arguments = vim.deepcopy(arguments),
      range = range and vim.deepcopy(range) or nil,
    }
    local view
    view = {
      events = {},
      emitter = {
        on = function(_, event_name, callback)
          view.events[event_name] = callback
        end,
      },
      open = function(self)
        self.tabpage = vim.api.nvim_get_current_tabpage()
        opened_views[#opened_views + 1] = self
        current_view = self
      end,
      close = function(self)
        self.closed = true
      end,
    }
    return view
  end,
  get_current_view = function()
    return current_view
  end,
  get_prev_non_view_tabpage = function()
    return previous_editing_tabpage
  end,
}
package.loaded['diffview.vcs.utils'] = {
  diff_file_list = function(adapter, left, right, path_args, options, layouts, callback)
    full_file_list_calls[#full_file_list_calls + 1] = {
      adapter = adapter,
      layouts = layouts,
      left = left,
      options = options,
      path_args = vim.deepcopy(path_args),
      right = right,
    }
    if defer_full_file_list then
      pending_full_file_list_callback = callback
    else
      callback(nil, queued_full_file_dictionary)
    end
  end,
}
package.loaded['config.git.diffview'] = nil

local diffview = require('config.git.diffview')
local panel = require('config.git.panel')
panel.reset()
diffview.setup()
assert(configured_options, 'Shared Diffview module did not configure the renderer')
local original_diffview_global = rawget(_G, 'DiffviewGlobal')
local logged_anchor_message
_G.DiffviewGlobal = {
  logger = {
    info = function(_, message)
      logged_anchor_message = message
    end,
  },
}
diffview.log_anchor('test anchor stage', 'info')
_G.DiffviewGlobal = original_diffview_global
assert(
  logged_anchor_message == '[Git anchor] test anchor stage',
  'Anchor diagnostics did not reach the Diffview log'
)
assert(
  configured_options.view.file_history.layout == 'diff2_horizontal',
  'Git history did not preserve the split Diffview layout'
)
assert(
  configured_options.file_history_panel.win_config.position == 'bottom'
    and configured_options.file_history_panel.win_config.height == 10,
  'Git history panel lost its compact bottom placement'
)

local function find_mapping(context, lhs)
  for _, mapping in ipairs(configured_options.keymaps[context]) do
    if mapping[2] == lhs then
      return mapping
    end
  end
end

for _, context in ipairs({ 'view', 'file_panel', 'file_history_panel' }) do
  assert(find_mapping(context, '<C-q>'), 'Ctrl-Q is missing from Diffview context: ' .. context)
  assert(not find_mapping(context, '<Space>o'), 'Git mode overrode the global jump-back key')
  assert(not find_mapping(context, '<Space>fw'), 'Git mode overrode project definition search')
  assert(find_mapping(context, '<Space>de'), 'Git search is missing from Diffview context: ' .. context)
  assert(not find_mapping(context, '<Space>df'), 'Git mode retained the overloaded file-history binding')
  assert(not find_mapping(context, '<C-b>'), 'Git mode retained the obsolete branch-picker binding')
  assert(find_mapping(context, '<Space>dp'), 'History-panel toggle is missing: ' .. context)
  assert(find_mapping(context, '<Tab>'), 'Pane traversal is missing: ' .. context)
  assert(not find_mapping(context, '<Space>dc'), 'Obsolete commit-checkout key remains: ' .. context)
  assert(
    (context == 'file_history_panel') == (find_mapping(context, '<Space>dn') ~= nil),
    'Commit details escaped the Git history footer scope: ' .. context
  )
  local ignored_search_repeat_mapping = find_mapping(context, '<Space>n')
  assert(
    ignored_search_repeat_mapping and ignored_search_repeat_mapping[3] == '<Nop>',
    'Unassigned leader-n can fall through to search repeat in Diffview context: ' .. context
  )
end
assert(
  find_mapping('file_history_panel', '<Space>dm'),
  'Git history list lacks guarded checkout for its selected commit'
)
assert(
  not find_mapping('view', '<Space>dm') and not find_mapping('file_panel', '<Space>dm'),
  'Commit checkout escaped the Git history list scope'
)

local detached_head_commit = string.rep('f', 40)
local detached_footer_renders = 0
local detached_footer_redraws = 0
local detached_entry = {
  commit = {
    hash = detached_head_commit,
    ref_names = 'HEAD, release-tag',
  },
  folded = false,
  single_file = false,
}
local detached_footer_view = {
  git_detached_head_commit = detached_head_commit,
  git_footer_tree = false,
  git_history_options = { kind = 'repository' },
  git_result_source = 'LOCAL',
  panel = {
    cur_item = { detached_entry },
    entries = { detached_entry },
    render = function()
      detached_footer_renders = detached_footer_renders + 1
    end,
    redraw = function()
      detached_footer_redraws = detached_footer_redraws + 1
    end,
    winid = vim.api.nvim_get_current_win(),
  },
}
assert(diffview.adapt_history_footer(detached_footer_view))
assert(
  detached_entry.commit.ref_names == 'release-tag, DETACHED HEAD',
  'Current detached commit retained the ambiguous HEAD decoration or lost its detached tag'
)
assert(
  vim.wo[detached_footer_view.panel.winid].winbar:match('CURRENT · DETACHED')
    and vim.wo[detached_footer_view.panel.winid].winbar:match(detached_head_commit:sub(1, 12)),
  'Detached history footer retained an attached-branch presentation'
)
assert(
  not diffview.adapt_history_footer(detached_footer_view)
    and detached_footer_renders == 1
    and detached_footer_redraws == 1
    and detached_entry.commit.ref_names == 'release-tag, DETACHED HEAD',
  'Detached HEAD marker duplicated or caused an unnecessary footer render'
)
detached_footer_view.git_anchor_waiting = 'HEAD moved; rendering ffffffffffff'
diffview.adapt_history_footer(detached_footer_view)
assert(
  vim.wo[detached_footer_view.panel.winid].winbar:match('ANCHOR')
    and vim.wo[detached_footer_view.panel.winid].winbar:match('rendering ffffffffffff'),
  'Anchor transition did not expose its render stage in the footer'
)
detached_footer_view.git_anchor_waiting = nil

local preview_commit = string.rep('e', 40)
local preview_subject = 'Selected commit stays collapsed'
local preview_entry = {
  commit = {
    hash = preview_commit,
    ref_names = 'HEAD, release-tag',
    subject = preview_subject,
  },
  folded = true,
}
local preview_buffer = vim.api.nvim_create_buf(false, true)
local preview_line = 'M  2 files | 30  19 | eeeeeeee ' .. preview_subject
vim.api.nvim_buf_set_lines(preview_buffer, 0, -1, false, { preview_line })
local previous_preview_buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_buf(0, preview_buffer)
local preview_footer_view = {
  git_branch_name = 'main',
  git_checked_out_branch = 'main',
  git_footer_tree = false,
  git_history_options = { kind = 'repository', review_only = true },
  git_result_source = 'LOCAL',
  git_review_tip_commit = string.rep('a', 40),
  panel = {
    bufid = preview_buffer,
    entries = { preview_entry },
    components = {
      log = {
        entries = {
          {
            comp = { context = preview_entry },
            commit = { comp = { lstart = 0 } },
          },
        },
      },
    },
    render = function() end,
    redraw = function() end,
    winid = vim.api.nvim_get_current_win(),
  },
}
assert(not diffview.adapt_history_footer(preview_footer_view))
assert(vim.wait(100, function()
  return preview_footer_view.git_footer_render_pending == nil
end, 5), 'Footer render policy did not settle')
assert(
  preview_entry.commit.ref_names == 'HEAD, release-tag' and preview_entry.folded,
  'Searched commit handling rewrote Git refs or expanded the target row'
)
vim.api.nvim_win_set_buf(0, previous_preview_buffer)
vim.api.nvim_buf_delete(preview_buffer, { force = true })

for _, scoped_kind in ipairs({ 'file', 'symbol' }) do
  local scoped_detached_entry = {
    commit = { hash = detached_head_commit, ref_names = 'HEAD' },
  }
  local scoped_detached_view = {
    git_detached_head_commit = detached_head_commit,
    git_footer_tree = false,
    git_history_options = { kind = scoped_kind },
    panel = {
      entries = { scoped_detached_entry },
      winid = vim.api.nvim_get_current_win(),
    },
  }
  assert(
    diffview.adapt_history_footer(scoped_detached_view)
      and scoped_detached_entry.commit.ref_names == 'DETACHED HEAD'
      and vim.wo[scoped_detached_view.panel.winid].winbar:match('CURRENT · DETACHED'),
    ('Detached %s history lost its commit row or HEAD pointer'):format(scoped_kind)
  )
end

local detached_branch_review_view = {
  git_branch_name = 'origin/main',
  git_detached_head_commit = detached_head_commit,
  git_footer_tree = false,
  git_history_options = { kind = 'repository', review_only = true },
  git_result_source = 'REMOTE',
  panel = {
    cur_item = {},
    entries = {},
    winid = vim.api.nvim_get_current_win(),
  },
}
diffview.adapt_history_footer(detached_branch_review_view)
assert(
  vim.wo[detached_branch_review_view.panel.winid].winbar:match('CURRENT · DETACHED')
    and vim.wo[detached_branch_review_view.panel.winid].winbar:match(
      detached_head_commit:sub(1, 12)
    )
    and not vim.wo[detached_branch_review_view.panel.winid].winbar:match('BRANCH REVIEW'),
  'Detached footer did not reserve its short pinned line for current checkout state'
)

local attached_branch_review_view = {
  git_branch_name = 'feature/topic',
  git_checked_out_branch = 'main',
  git_footer_tree = false,
  git_history_options = { kind = 'repository', review_only = true },
  git_result_source = 'LOCAL',
  panel = {
    cur_item = {},
    entries = {},
    winid = vim.api.nvim_get_current_win(),
  },
}
diffview.adapt_history_footer(attached_branch_review_view)
assert(
  vim.wo[attached_branch_review_view.panel.winid].winbar:match('CURRENT BRANCH · main')
    and not vim.wo[attached_branch_review_view.panel.winid].winbar:match('BRANCH REVIEW'),
  'Attached footer did not reserve its short pinned line for current checkout state'
)

local panel_toggle_calls = 0
current_view = {
  git_repository_root = '/work/repository',
  panel = {
    toggle = function(_, focus_panel)
      assert(focus_panel, 'History-panel toggle did not request focus on restore')
      panel_toggle_calls = panel_toggle_calls + 1
    end,
  },
}
assert(diffview.toggle_commit_list() and panel_toggle_calls == 1, 'Git panel did not toggle')

local root_history_view = current_view
local footer_render_calls = 0
local footer_redraw_calls = 0
local filtered_entry = {
  files = { { path = 'lua/example.lua' } },
  folded = true,
  git_target_file = { path = 'lua/example.lua' },
  single_file = true,
}
local filtered_view = {
  git_footer_tree = true,
  git_history_options = {
    kind = 'symbol',
    location = {
      relative_path = 'lua/example.lua',
      structure = {
        first_line = 10,
        label = 'Example › run',
        last_line = 20,
      },
    },
  },
  panel = {
    entries = { filtered_entry },
    render = function()
      footer_render_calls = footer_render_calls + 1
    end,
    redraw = function()
      footer_redraw_calls = footer_redraw_calls + 1
    end,
    single_file = true,
    winid = vim.api.nvim_get_current_win(),
  },
}
assert(diffview.adapt_history_footer(filtered_view), 'Filtered footer was not adapted')
assert(
  not filtered_entry.single_file
    and filtered_view.panel.single_file
    and filtered_entry.folded
    and footer_render_calls == 1
    and footer_redraw_calls == 1,
  'Footer adaptation changed filter semantics or bypassed the owned renderer'
)
assert(
  vim.wo[filtered_view.panel.winid].winbar:match('GIT HISTORY · LOCAL')
    and not vim.wo[filtered_view.panel.winid].winbar:match('lua/example.lua'),
  'Symbol footer did not move its long scope metadata off the short pinned line'
)

local previous_footer_buffer = vim.api.nvim_get_current_buf()
local annotated_footer_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(annotated_footer_buffer, 0, -1, false, {
  'File History (2)',
  'commit one',
  '│   M README.md',
  '└   M lua/example.lua',
  'commit two',
  '│   M lua/example.lua',
  '└   M docs/guide.md',
})
local filler_lines = {}
for filler_index = 1, 30 do
  filler_lines[filler_index] = ('filler %02d'):format(filler_index)
end
vim.api.nvim_buf_set_lines(annotated_footer_buffer, -1, -1, false, filler_lines)
vim.api.nvim_win_set_buf(0, annotated_footer_buffer)
local first_target_file = { path = 'lua/example.lua' }
local first_annotated_entry = {
  commit = { ref_names = 'HEAD -> main, origin/main' },
  files = { { path = 'README.md' }, first_target_file },
  folded = false,
  git_target_file = first_target_file,
}
local second_target_file = { path = 'lua/example.lua' }
local second_annotated_entry = {
  commit = { ref_names = 'feature/topic' },
  files = { second_target_file, { path = 'docs/guide.md' } },
  folded = false,
  git_target_file = second_target_file,
}
local annotated_footer_view = {
  git_branch_name = 'main',
  git_checked_out_branch = 'main',
  git_history_kind = 'file',
  git_history_options = {
    kind = 'file',
    location = { relative_path = 'lua/example.lua' },
  },
  git_result_source = 'LOCAL',
  panel = {
    bufid = annotated_footer_buffer,
    entries = { first_annotated_entry, second_annotated_entry },
    winid = vim.api.nvim_get_current_win(),
    components = {
      log = {
        entries = {
          {
            comp = { context = first_annotated_entry },
            commit = { comp = { lstart = 1 } },
            files = { comp = { lstart = 2 } },
          },
          {
            comp = { context = second_annotated_entry },
            commit = { comp = { lstart = 4 } },
            files = { comp = { lstart = 5 } },
          },
        },
      },
    },
  },
}
vim.api.nvim_win_set_cursor(0, { 2, 0 })
assert(diffview.decorate_history_footer(annotated_footer_view))
local target_match_tags = 0
local branch_separator_tags = 0
local initial_metadata_line
local initial_metadata_highlights = {}
for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(
  annotated_footer_buffer,
  -1,
  0,
  -1,
  { details = true }
)) do
  local details = extmark[4]
  local virtual_text = details.virt_text and details.virt_text[1]
    and details.virt_text[1][1]
  local virtual_line_chunks = details.virt_lines and details.virt_lines[1]
  local virtual_line = ''
  for _, chunk in ipairs(virtual_line_chunks or {}) do
    virtual_line = virtual_line .. chunk[1]
    if chunk[2] then
      initial_metadata_highlights[chunk[2]] = true
    end
  end
  if virtual_text and virtual_text:match('MATCH · FILE') then
    target_match_tags = target_match_tags + 1
    assert(details.hl_group == nil, 'Scoped target filename retained custom highlighting')
  end
  if virtual_line:match('^── BRANCH') then
    branch_separator_tags = branch_separator_tags + 1
  end
  if virtual_line:match('REVIEW') and virtual_line:match('SCOPE') then
    initial_metadata_line = virtual_line
  end
end
assert(
  target_match_tags == 2
    and branch_separator_tags == 2
    and first_annotated_entry.git_branch_segment == 'main · origin/main'
    and second_annotated_entry.git_branch_segment == 'feature/topic'
    and initial_metadata_line
    and initial_metadata_line:match('REVIEW · LOCAL · BRANCH')
    and initial_metadata_line:match('SCOPE · FILE · lua/example.lua')
    and initial_metadata_highlights.Normal,
  'Scoped footer did not tag every target file and split its branch segments'
)
assert(
  vim.wo[annotated_footer_view.panel.winid].winbar:match('CURRENT BRANCH · main')
    and vim.wo[annotated_footer_view.panel.winid].winbar:match('%%#Normal#')
    and vim.wo[annotated_footer_view.panel.winid].winbar:match(
      'PINNED BRANCH · main · origin/main'
    ),
  'Footer current-checkout line did not retain its selected branch segment'
)
vim.api.nvim_win_set_cursor(0, { 5, 0 })
assert(diffview.decorate_history_footer(annotated_footer_view))
local retained_metadata_line
for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(
  annotated_footer_buffer,
  -1,
  0,
  -1,
  { details = true }
)) do
  local details = extmark[4]
  local virtual_line_chunks = details.virt_lines and details.virt_lines[1]
  local virtual_line = ''
  for _, chunk in ipairs(virtual_line_chunks or {}) do
    virtual_line = virtual_line .. chunk[1]
  end
  if virtual_line:match('REVIEW') and virtual_line:match('SCOPE') then
    retained_metadata_line = virtual_line
  end
end
assert(
  vim.wo[annotated_footer_view.panel.winid].winbar:match(
    'PINNED BRANCH · feature/topic'
  )
    and retained_metadata_line
    and retained_metadata_line:match('SCOPE · FILE · lua/example.lua'),
  'Second branch segment did not reach the stable winbar or displaced scope metadata'
)
vim.api.nvim_win_set_buf(0, previous_footer_buffer)
vim.api.nvim_buf_delete(annotated_footer_buffer, { force = true })

current_view = root_history_view

local seed_destroyed = false
local warmed_revision_buffers = 0
local seed_revision_files = {
  {
    create_buffer = function()
      return function()
        warmed_revision_buffers = warmed_revision_buffers + 1
      end
    end,
    is_valid = function()
      return false
    end,
    nulled = false,
  },
  {
    create_buffer = function()
      return function()
        warmed_revision_buffers = warmed_revision_buffers + 1
      end
    end,
    is_valid = function()
      return false
    end,
    nulled = false,
  },
}
local seed_file = {
  destroy = function()
    seed_destroyed = true
  end,
  layout = {
    files = function()
      return seed_revision_files
    end,
  },
  path = 'lua/example.lua',
  opened = true,
  revs = { a = 'parent-revision', b = 'commit-revision' },
  set_active = function() end,
}
local unrelated_file = {
  path = 'README.md',
  set_active = function(self, active)
    self.active = active
  end,
}
local target_file = {
  oldpath = 'lua/old-example.lua',
  path = 'lua/example.lua',
  set_active = function(self, active)
    self.active = active
  end,
}
queued_full_file_dictionary = { working = { unrelated_file, target_file } }
local lazy_status_updates = 0
local lazy_stats_updates = 0
local lazy_seed_file = {
  layout = {
    files = function()
      return {}
    end,
  },
  path = 'lua/example.lua',
  revs = { a = 'lazy-parent-revision', b = 'lazy-commit-revision' },
  set_active = function() end,
}
local lazy_entry = {
  commit = { hash = string.rep('b', 40) },
  files = { lazy_seed_file },
  folded = true,
  single_file = true,
  update_stats = function()
    lazy_stats_updates = lazy_stats_updates + 1
  end,
  update_status = function()
    lazy_status_updates = lazy_status_updates + 1
  end,
}
local entry_status_updates = 0
local entry_stats_updates = 0
local expanded_entry = {
  commit = { hash = string.rep('a', 40) },
  files = { seed_file },
  folded = true,
  single_file = true,
  update_stats = function()
    entry_stats_updates = entry_stats_updates + 1
  end,
  update_status = function()
    entry_status_updates = entry_status_updates + 1
  end,
}
local expanded_render_calls = 0
local expanded_redraw_calls = 0
local expanded_component_updates = 0
local selected_expanded_file
local highlighted_expanded_item
local expanded_view = {
  adapter = { name = 'mock Git adapter' },
  cur_entry = seed_file,
  get_default_layout = function()
    return 'history-layout'
  end,
  get_default_merge_layout = function()
    return 'merge-layout'
  end,
  git_footer_enriching = true,
  git_footer_tree = true,
  git_history_options = {
    kind = 'symbol',
    location = { relative_path = 'lua/example.lua' },
  },
  panel = {
    cur_item = { expanded_entry, seed_file },
    entries = { expanded_entry, lazy_entry },
    render = function()
      expanded_render_calls = expanded_render_calls + 1
    end,
    redraw = function()
      expanded_redraw_calls = expanded_redraw_calls + 1
    end,
    set_cur_item = function(self, item)
      self.cur_item = item
      if item[2] then
        item[2]:set_active(true)
      end
    end,
    set_entry_fold = function(_, entry, open)
      if open == entry.folded then
        entry.folded = not open
      end
    end,
    update_components = function()
      expanded_component_updates = expanded_component_updates + 1
    end,
    highlight_item = function(_, item)
      highlighted_expanded_item = item
    end,
    get_item_at_cursor = function()
      return expanded_entry
    end,
    is_focused = function()
      return true
    end,
    winid = vim.api.nvim_get_current_win(),
  },
  set_file = function(view, file)
    selected_expanded_file = file
    file.opened = true
    view.cur_entry = file
    view.panel:set_cur_item({ expanded_entry, file })
    view.panel:highlight_item(file)
  end,
  tabpage = vim.api.nvim_get_current_tabpage(),
}
local expanded_lifecycle = require('config.git.lifecycle')
expanded_lifecycle.attach(expanded_view, 'symbol')
expanded_lifecycle.transition(expanded_view, 'listing', 'test scoped history')
expanded_lifecycle.mark_list_ready(expanded_view, 2)
local initial_full_file_list_count = #full_file_list_calls
assert(diffview.enrich_history_footer(expanded_view), 'Scoped history enrichment did not start')
assert(vim.wait(200, function()
  return not expanded_view.git_footer_enriching
    and expanded_view.git_diff_opened == false
end, 10), 'Scoped history did not settle its lazy footer')
assert(
  #full_file_list_calls == initial_full_file_list_count,
  'Scoped footer settlement eagerly loaded commit children'
)
assert(
  diffview.enrich_history_footer_entry(expanded_view, expanded_entry),
  'The shared detail-window hook did not start commit child loading'
)
assert(vim.wait(200, function()
  return expanded_entry.git_files_enriched == true
end, 10), 'The selected detail entry did not finish loading')
local detail_file_list_call = full_file_list_calls[#full_file_list_calls]
assert(
  vim.deep_equal(detail_file_list_call.path_args, {})
    and detail_file_list_call.left == 'parent-revision'
    and detail_file_list_call.right == 'commit-revision'
    and detail_file_list_call.options.show_untracked == false,
  'Detail loading did not use the unfiltered parent-to-commit file loader'
)
assert(
  #expanded_entry.files == 2
    and expanded_entry.files[1] == unrelated_file
    and expanded_entry.files[2] == seed_file
    and expanded_entry.git_target_file == seed_file
    and expanded_entry.git_files_enriched == true
    and entry_status_updates == 1
    and entry_stats_updates == 1,
  'Detail loading did not install the selected commit complete file list'
)
assert(
  lazy_entry.git_files_enriched == false
    and #lazy_entry.files == 1
    and lazy_entry.files[1] == lazy_seed_file
    and lazy_entry.git_target_file == lazy_seed_file,
  'Older matched commits did not stay lazy behind the explicit loader'
)
assert(
  selected_expanded_file == nil
    and expanded_view.cur_entry == nil
    and expanded_view.panel.cur_item[2] == nil
    and expanded_view.git_diff_opened == false,
  'Scoped history did not stay idle while proactively loading recent commits'
)
assert(
  not expanded_entry.single_file
    and expanded_entry.folded
    and expanded_view.panel.single_file == false
    and highlighted_expanded_item == nil,
  'Scoped history expanded or moved its selection while rebuilding the commit-only footer'
)
assert(not seed_destroyed, 'Active filtered file was destroyed before Diffview selected its replacement')
assert(
  warmed_revision_buffers == 0,
  'Scoped history warmed code buffers before an explicit file open'
)

current_view = expanded_view
native_history_selection = function()
  expanded_entry.folded = not expanded_entry.folded
end
for _, scoped_kind in ipairs({ 'file', 'symbol' }) do
  expanded_entry.folded = true
  expanded_view.git_history_kind = scoped_kind
  expanded_view.git_history_options.kind = scoped_kind
  selected_expanded_file = nil
  highlighted_expanded_item = nil
  expanded_view.panel.cur_item = { expanded_entry, nil }
  local calls_before_expand = #full_file_list_calls
  find_mapping('file_history_panel', '<cr>')[3]()
  vim.wait(20)
  assert(
    #full_file_list_calls == calls_before_expand,
    ('Expanded %s commit loaded file lists instead of only highlighting its matched file'):format(
      scoped_kind
    )
  )
  assert(
    highlighted_expanded_item == nil
      and selected_expanded_file == nil
      and expanded_view.git_diff_opened == false
      and expanded_view.panel.cur_item[1] == expanded_entry
      and expanded_view.panel.cur_item[2] == nil,
    ('Expanded %s commit performed an automatic child jump'):format(scoped_kind)
  )
  find_mapping('file_history_panel', '<cr>')[3]()
  assert(
    expanded_entry.folded and expanded_view.panel.cur_item[2] == nil,
    ('Expanded %s commit did not collapse from its own title row'):format(scoped_kind)
  )
end
expanded_view.panel.get_item_at_cursor = function()
  return lazy_entry
end
assert(
  not find_mapping('file_history_panel', '<Space>dl'),
  'Redundant Git child-list keybinding was not removed'
)
expanded_view.panel.get_item_at_cursor = function()
  return seed_file
end
native_history_selection = function()
  expanded_view:set_file(seed_file)
end
find_mapping('file_history_panel', '<cr>')[3]()
assert(
  selected_expanded_file == seed_file and expanded_view.git_diff_opened,
  'Explicit Enter on the highlighted scoped file did not open its code panes'
)
native_history_selection = nil
current_view = root_history_view

local ordinary_file = { path = 'lua/ordinary.lua' }
local ordinary_entry = { commit = { hash = string.rep('6', 40) }, files = { ordinary_file } }
local ordinary_selected_file
local ordinary_view = {
  git_diff_opened = false,
  git_footer_tree = false,
  panel = {
    cur_item = { ordinary_entry, nil },
    entries = { ordinary_entry },
    get_item_at_cursor = function()
      return ordinary_file
    end,
    is_focused = function()
      return true
    end,
  },
  set_file = function(_, file)
    ordinary_selected_file = file
  end,
  tabpage = vim.api.nvim_get_current_tabpage(),
}
current_view = ordinary_view
native_history_selection = function()
  ordinary_entry.folded = false
end
ordinary_view.panel.get_item_at_cursor = function()
  return ordinary_entry
end
find_mapping('file_history_panel', '<cr>')[3]()
assert(
  ordinary_selected_file == nil and ordinary_view.git_diff_opened == false,
  'Opening an ordinary commit folder rendered a file without an explicit file-row open'
)
ordinary_view.panel.get_item_at_cursor = function()
  return ordinary_file
end
native_history_selection = function()
  ordinary_view:set_file(ordinary_file)
end
find_mapping('file_history_panel', '<cr>')[3]()
assert(
  ordinary_selected_file == ordinary_file and ordinary_view.git_diff_opened,
  'Ordinary history did not render the explicitly opened file row'
)
native_history_selection = nil
current_view = root_history_view

local history_options = {
  kind = 'file',
  location = { relative_path = 'lua/example.lua', root = '/work/repository' },
}
current_view.git_history_options = history_options
current_view.panel.updating = true
find_mapping('view', '<Space>de')[3]()
assert(
  #search_calls == 1
    and search_calls[1].root == '/work/repository'
    and search_calls[1].history_options == history_options
    and search_calls[1].parent_view == current_view,
  'Git search did not remain available while branch history was rendering'
)
current_view.panel.updating = false

local mounting_search_view = {
  git_history_options = history_options,
  git_repository_root = '/work/repository',
}
current_view = mounting_search_view
find_mapping('view', '<Space>de')[3]()
assert(
  #search_calls == 2
    and search_calls[2].root == '/work/repository'
    and search_calls[2].history_options == history_options
    and search_calls[2].parent_view == mounting_search_view,
  'Git search rejected Space-de before the initial history panel was created'
)
table.remove(search_calls)
current_view = root_history_view

local list_commit_hash = string.rep('d', 40)
local rendered_history_file = {
  opened = true,
  path = 'lua/rendered.lua',
}
local rendered_history_entry = {
  commit = { hash = list_commit_hash },
  files = { rendered_history_file },
}
current_view.panel.cur_item = { rendered_history_entry, rendered_history_file }
current_view.panel.get_log_entry_at_cursor = function()
  return rendered_history_entry
end
current_view.cur_entry = rendered_history_file
current_view.git_branch_name = 'main'
current_view.git_anchor_plan = {
  branch_name = 'main',
  branch_ref = 'refs/heads/main',
  branch_tip_commit = list_commit_hash,
  source = 'LOCAL',
}
current_view.git_result_source = 'LOCAL'
find_mapping('file_history_panel', '<Space>dm')[3]()
assert(
  checkout_call
    and checkout_call.root == '/work/repository'
    and checkout_call.commit_hash == list_commit_hash
    and checkout_call.parent_view == current_view
    and checkout_call.commit_context.branch_name == 'main'
    and checkout_call.commit_context.anchor_plan == current_view.git_anchor_plan,
  'History-list checkout did not target its selected commit and owning Git view'
)
find_mapping('file_history_panel', '<Space>dn')[3]()
assert(
  commit_detail_calls == 1,
  'History-list commit details did not invoke Diffview\'s native selected-commit panel'
)

local location = {
  relative_path = 'lua/example.lua',
  root = '/work/repository',
}
diffview.open_file_history({ kind = 'file', location = location })
local branch_view = opened_views[1]
assert(
  vim.deep_equal(history_calls[1].arguments, {
    '-C/work/repository',
    '--max-count=1',
    '--follow',
    'lua/example.lua',
  }),
  'File history arguments lost their cap, path, or rename tracking'
)
assert(
  branch_view.git_history_options.kind == 'file'
    and branch_view.git_history_options.location.root == '/work/repository',
  'Branch Diffview did not retain the specification needed by temporary search'
)
assert(panel.level() == 'git', 'Opening branch history did not enter the Git panel layer')

local rendered_window = vim.api.nvim_get_current_win()
local rendered_buffer = vim.api.nvim_create_buf(false, true)
local rendered_left_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(rendered_window, rendered_buffer)
vim.api.nvim_buf_set_lines(rendered_buffer, 0, -1, false, {
  'local function changed_scope()',
  '  local value = 1',
  '  if value then',
  '    value = value + 1',
  '  end',
  'end',
})
vim.api.nvim_buf_set_lines(rendered_left_buffer, 0, -1, false, {
  'local function previous_scope()',
  '  return 0',
  'end',
})
vim.wo[rendered_window].foldmethod = 'manual'
vim.api.nvim_win_set_cursor(rendered_window, { 3, 0 })
vim.cmd('2,5fold')
vim.cmd('normal! zc')
enclosing_structure_line = 1
branch_view.cur_layout = {
  a = {
    file = {
      bufnr = rendered_left_buffer,
      path = 'lua/example.lua',
      rev = { commit = string.rep('1', 40) },
    },
    id = rendered_window,
  },
  b = {
    file = {
      bufnr = rendered_buffer,
      path = 'lua/example.lua',
      rev = { commit = string.rep('2', 40) },
    },
    id = rendered_window,
  },
}
local rendered_event_file = { opened = true, path = 'lua/example.lua' }
local rendered_event_entry = {
  commit = { hash = string.rep('2', 40) },
  files = { rendered_event_file },
  get_diff = function()
    return {
      hunks = {
        {
          new_content = { { 1, 'modified' } },
          new_row = 4,
          new_size = 1,
          old_content = { { 1, 'original' } },
          old_row = 4,
        },
      },
    }
  end,
}
branch_view.panel = {
  cur_item = { rendered_event_entry, rendered_event_file },
  entries = { rendered_event_entry },
}
branch_view.cur_entry = rendered_event_file
local history_lifecycle = require('config.git.lifecycle')
history_lifecycle.mark_list_ready(branch_view, 1)
history_lifecycle.mark_enrichment_ready(
  branch_view,
  rendered_event_entry.commit.hash,
  rendered_event_file.path
)
branch_view.git_diff_opened = true
branch_view.events.file_open_pre(nil, rendered_event_file)
branch_view.events.file_open_post(nil, rendered_event_file)
vim.wait(100, function()
  return history_lifecycle.is_ready(branch_view)
end, 5)
assert(
  vim.list_contains(syntax_highlight_buffers, rendered_left_buffer)
    and vim.list_contains(syntax_highlight_buffers, rendered_buffer),
  'Diffview render completion did not start syntax highlighting in both diff panes'
)
assert(
  vim.wo[rendered_window].cursorline and vim.wo[rendered_window].cursorlineopt == 'line',
  'Diffview code pane did not reduce its cursor hint to one whole-line background'
)
assert(
  vim.fn.foldclosed(2) == 2 and vim.api.nvim_win_get_cursor(rendered_window)[1] == 3,
  'History render performed an automatic fold or cursor alignment on the input path'
)
local already_rendered_completion
branch_view.git_render_ready_callback = function(_, render_succeeded, detail)
  already_rendered_completion = {
    detail = detail,
    succeeded = render_succeeded,
  }
end
assert(
  diffview.focus_history_commit(branch_view, rendered_event_entry.commit.hash)
    and already_rendered_completion
    and already_rendered_completion.succeeded
    and already_rendered_completion.detail == 'selected commit already rendered',
  'Already-rendered commit focus waited for a lifecycle event that had already completed'
)
enclosing_structure_line = nil

local initial_render_file = { opened = false, path = 'lua/initial.lua' }
local selected_after_initial_file = { path = 'lua/selected.lua' }
local selected_after_initial_hash = string.rep('9', 40)
local selected_after_initial_render
local initial_render_view = {
  cur_entry = initial_render_file,
  panel = {
    cur_item = {
      { commit = { hash = string.rep('8', 40) }, files = { initial_render_file } },
      initial_render_file,
    },
    entries = {
      {
        commit = { hash = selected_after_initial_hash },
        files = { selected_after_initial_file },
      },
    },
    updating = false,
  },
  set_file = function(_, file)
    selected_after_initial_render = file
  end,
}
assert(
  not diffview.focus_history_commit(initial_render_view, selected_after_initial_hash)
    and selected_after_initial_render == nil,
  'Selected commit render raced the replacement view initial diff render'
)
initial_render_file.opened = true
assert(
  diffview.focus_history_commit(initial_render_view, selected_after_initial_hash)
    and selected_after_initial_render == selected_after_initial_file,
  'Selected commit render did not resume after the replacement initial diff was ready'
)

do
  local lazy_selected_hash = string.rep('7', 40)
  local lazy_placeholder_file = { path = '[loading]' }
  local lazy_selected_entry = {
    commit = { hash = lazy_selected_hash },
    files = { lazy_placeholder_file },
    git_details_loaded = false,
  }
  local lazy_selected_file = { path = 'lua/lazy-selected.lua' }
  local lazy_selected_render
  local lazy_selected_view = {
    panel = {
      cur_item = {},
      entries = { lazy_selected_entry },
      updating = false,
    },
    set_file = function(_, file)
      lazy_selected_render = file
    end,
  }
  defer_footer_detail = true
  local detail_requests_before_focus = footer_detail_requests
  assert(diffview.focus_history_commit(lazy_selected_view, lazy_selected_hash))
  assert(diffview.focus_history_commit(lazy_selected_view, lazy_selected_hash))
  assert(
    lazy_selected_render == nil
      and footer_detail_requests == detail_requests_before_focus + 1
      and pending_footer_detail
      and pending_footer_detail.entry == lazy_selected_entry,
    'First-choice rendering used a placeholder or duplicated its prioritized detail request'
  )
  lazy_selected_entry.files = { lazy_selected_file }
  lazy_selected_entry.git_target_file = lazy_selected_file
  lazy_selected_entry.git_details_loaded = true
  local complete_footer_detail = pending_footer_detail.callback
  pending_footer_detail = nil
  defer_footer_detail = false
  complete_footer_detail(true)
  assert(
    lazy_selected_render == lazy_selected_file
      and lazy_selected_view.git_review_hydration == nil,
    'First-choice rendering did not resume with the hydrated commit file'
  )
end

local existing_commit_hash = string.rep('e', 40)
local existing_file = { path = 'lua/existing.lua' }
local existing_target_file = { path = 'lua/example.lua' }
local selected_history_file
branch_view.set_file = function(_, file)
  selected_history_file = file
end
branch_view.panel = {
  cur_item = {},
  entries = {
    {
      commit = { hash = existing_commit_hash },
      files = { existing_file, existing_target_file },
      git_target_file = existing_target_file,
    },
  },
  log_options = {},
  updating = false,
}
assert(diffview.open_search_commit(
  branch_view,
  branch_view.git_history_options,
  { hash = existing_commit_hash, source = 'LOCAL' }
))
assert(
  #history_calls == 1
    and selected_history_file == nil
    and branch_view.panel.cur_item[1].commit.hash == existing_commit_hash
    and branch_view.panel.cur_item[2] == nil
    and branch_view.git_diff_opened == false,
  'Search review replaced history, expanded the target, or rendered a file before final focus'
)

local loaded_commit = {
  branch_name = 'main',
  hash = string.rep('b', 40),
  history_ref = 'refs/heads/main',
  source = 'LOCAL',
}
branch_view.git_checked_out_branch = nil
branch_view.git_detached_head_commit = detached_head_commit
branch_view.panel.entries = {}
assert(
  diffview.jump_to_search_commit(branch_view, branch_view.git_history_options, loaded_commit)
    and #history_calls == 2,
  'An unmounted commit did not open its complete owning-branch history'
)
local loaded_commit_view = opened_views[2]
assert(
  vim.deep_equal(history_calls[2].arguments, {
    '-C/work/repository',
    '--max-count=1',
    '--range=refs/heads/main',
  })
    and not loaded_commit_view.git_parent_view
    and loaded_commit_view.git_branch_name == 'main'
    and loaded_commit_view.git_detached_head_commit == detached_head_commit
    and loaded_commit_view.git_history_options.review_only
    and loaded_commit_view.git_search_options.kind == 'repository'
    and loaded_commit_view.git_search_options.detached_head_commit == detached_head_commit
    and loaded_commit_view.git_search_options.revision == nil
    and loaded_commit_view.git_search_options.history_ref == nil
    and loaded_commit_view.git_search_options.selected_commit == nil
    and loaded_commit_view.git_search_options.unbounded == nil
    and panel.level() == 'git',
  'A selected commit lost its full branch history or repository-wide dispatcher scope'
)
current_view = loaded_commit_view
loaded_commit_view.panel = {
  cur_item = {},
  entries = {},
  log_options = {},
  updating = true,
}
assert(diffview.search())
assert(
  #search_calls == 2
    and search_calls[2].parent_view == loaded_commit_view
    and search_calls[2].history_options.kind == 'repository'
    and search_calls[2].history_options.revision == nil,
  'Selected commit history could not immediately search newer branch revisions'
)
loaded_commit_view.panel.updating = false
assert(
  not branch_view.closed and type(loaded_commit_view.git_render_ready_callback) == 'function',
  'Previous history was disposed before its replacement finished rendering'
)
local loaded_render_callback = loaded_commit_view.git_render_ready_callback
loaded_commit_view.git_render_ready_callback = nil
loaded_render_callback(loaded_commit_view, true, 'test selected commit rendered')
assert(vim.wait(100, function()
  return branch_view.closed and disposed_views[1] == branch_view
end, 10), 'Commit transition did not dispose the replaced history after mounting its successor')

local selected_commit = {
  branch_name = 'main',
  hash = string.rep('c', 40),
  history_ref = 'refs/heads/main',
  source = 'LOCAL',
}
loaded_commit_view.panel = {
  cur_item = {},
  entries = {},
  log_options = {},
  updating = false,
}
assert(diffview.open_search_commit(
  loaded_commit_view,
  loaded_commit_view.git_history_options,
  selected_commit
))
local selected_commit_view = opened_views[3]
assert(
  vim.deep_equal(history_calls[3].arguments, {
    '-C/work/repository',
    '--max-count=1',
    '--range=refs/heads/main',
  })
    and not selected_commit_view.git_parent_view,
  'Commit selection did not keep its owning branch list at the ordinary Git layer'
)
assert(
  selected_commit_view.git_branch_name == 'main',
  'Commit history did not retain its source branch for the list header'
)
assert(
  not loaded_commit_view.closed
    and type(selected_commit_view.git_render_ready_callback) == 'function',
  'Second history was disposed during replacement diff-buffer creation'
)
local selected_render_callback = selected_commit_view.git_render_ready_callback
selected_commit_view.git_render_ready_callback = nil
selected_render_callback(selected_commit_view, true, 'test selected commit rendered')
assert(vim.wait(100, function()
  return loaded_commit_view.closed and disposed_views[2] == loaded_commit_view
end, 10), 'Second commit transition did not retire its previous Git history')
assert(panel.level() == 'git', 'Commit selection exited the ordinary Git panel layer')

selected_commit_view.nulled = true
selected_commit_view.panel = { cur_item = nil, log_options = {}, updating = false }
history_lifecycle.mark_empty_ready(selected_commit_view, 'test empty commit rendered')
current_view = selected_commit_view
find_mapping('view', '<C-q>')[3]()
assert(vim.wait(100, function()
  return selected_commit_view.closed
    and disposed_views[#disposed_views] == selected_commit_view
end, 10), 'An empty commit diff prevented Git history from closing cleanly')
assert(panel.level() == 'editor', 'Closing branch history did not restore the editor layer')

local performance_seed_file = {
  path = 'lua/example.lua',
  revs = { a = 'performance-parent', b = 'performance-commit' },
}
local performance_entry = {
  commit = { hash = string.rep('8', 40) },
  files = { performance_seed_file },
  folded = true,
}
local performance_entries = { performance_entry }
for performance_index = 2, 50 do
  performance_entries[#performance_entries + 1] = {
    commit = { hash = ('%040d'):format(performance_index) },
    files = {
      {
        path = 'lua/example.lua',
        revs = {
          a = 'performance-parent-' .. performance_index,
          b = 'performance-commit-' .. performance_index,
        },
      },
    },
    folded = true,
  }
end
defer_full_file_list = true
pending_full_file_list_callback = nil
local performance_call_count = #full_file_list_calls
diffview.open_file_history({ kind = 'file', location = location })
local performance_view = opened_views[#opened_views]
performance_view.adapter = { name = 'performance adapter' }
performance_view.get_default_layout = function()
  return 'performance-layout'
end
performance_view.get_default_merge_layout = function()
  return 'performance-layout'
end
performance_view.panel = {
  cur_item = nil,
  entries = performance_entries,
  log_options = {},
  updating = false,
  winid = vim.api.nvim_get_current_win(),
}
assert(vim.wait(200, function()
  return not performance_view.git_footer_enriching
end, 10), 'Scoped footer did not become ready without eager file-list expansion')
assert(
  #full_file_list_calls == performance_call_count
    and pending_full_file_list_callback == nil,
  'Scoped footer settlement loaded details outside the shared footer loader'
)
local old_entry = performance_entries[30]
assert(
  diffview.enrich_history_footer_entry(performance_view, old_entry)
    and #full_file_list_calls == performance_call_count + 1
    and pending_full_file_list_callback ~= nil,
  'Selected older scoped commit did not expose its lazy in-flight diff request'
)
current_view = performance_view
assert(
  diffview.handle_ctrl_q(),
  'Ctrl-Q did not cancel Git history during initial scoped enrichment'
)
assert(
  not performance_entry.git_files_enriching
    and not old_entry.git_files_enriching,
  'Git exit retained selected-entry footer enrichment'
)
assert(vim.wait(100, function()
  return performance_view.closed
    and history_lifecycle.phase(performance_view) == 'disposed'
end, 10), 'Initial scoped enrichment delayed Git exit')
local stale_file_destroyed = false
local stale_file = {
  destroy = function()
    stale_file_destroyed = true
  end,
}
pending_full_file_list_callback(nil, { working = { stale_file } })
assert(vim.wait(100, function()
  return stale_file_destroyed
end, 10), 'Cancelled footer enrichment leaked its in-flight file results')
assert(
  #full_file_list_calls == performance_call_count + 1,
  'Cancelled lazy footer enrichment launched duplicate commit diff requests'
)
defer_full_file_list = false
pending_full_file_list_callback = nil
statusline_branch_refreshes = 0

local initializing_exit_view = {
  close = function(self)
    self.closed = true
  end,
  cur_entry = nil,
  git_result_source = 'LOCAL',
  panel = {
    cur_item = nil,
    entries = {},
    log_options = {},
    updating = true,
    winid = vim.api.nvim_get_current_win(),
  },
  tabpage = vim.api.nvim_get_current_tabpage(),
}
history_lifecycle.attach(initializing_exit_view, 'repository')
history_lifecycle.transition(initializing_exit_view, 'listing', 'test initial history')
current_view = initializing_exit_view
panel.enter_git(initializing_exit_view, function()
  diffview.return_to_editor_line()
end)
assert(
  diffview.handle_ctrl_q(),
  'Ctrl-Q did not accept an exit while Git history was initializing'
)
assert(vim.wait(100, function()
  return initializing_exit_view.closed
end, 10), 'Early Git exit did not dispose the initializing view')
assert(
  panel.level() == 'editor'
    and history_lifecycle.phase(initializing_exit_view) == 'disposed',
  'Early Git exit retained the Git panel layer'
)
statusline_branch_refreshes = 0

local waiting_view = {
  close = function(self)
    self.closed = true
  end,
  cur_entry = nil,
  git_result_source = 'REMOTE',
  panel = {
    cur_item = { {}, {} },
    log_options = {},
    updating = false,
    winid = vim.api.nvim_get_current_win(),
  },
  tabpage = vim.api.nvim_get_current_tabpage(),
}
current_view = waiting_view
panel.enter_git(waiting_view, function()
  diffview.return_to_editor_line()
end)
assert(diffview.handle_ctrl_q(), 'Unready Ctrl-Q return did not exit Git mode immediately')
assert(vim.wait(100, function()
  return panel.level() == 'editor' and waiting_view.closed
end, 10), 'Unready Git history remained mounted after its editor handoff')
statusline_branch_refreshes = 0

local editor_tabpage = vim.api.nvim_get_current_tabpage()
vim.cmd({ cmd = 'edit', args = { 'README.md' } })
vim.keymap.set('n', '<Space>fw', function() end, { desc = 'Project workspace symbols' })
vim.keymap.set('n', '<Space>de', function() end, {
  desc = 'Search Git branches, commits, and issues',
})
local return_editor_window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(return_editor_window, { 1, 0 })
vim.cmd('tabnew')
local git_tabpage = vim.api.nvim_get_current_tabpage()
local historical_window = vim.api.nvim_get_current_win()
local historical_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(historical_window, historical_buffer)
vim.api.nvim_buf_set_lines(historical_buffer, 0, -1, false, {
  'local function open_picker(changed_signature)',
  '  return true',
  'end',
})
vim.api.nvim_win_set_cursor(historical_window, { 2, 4 })
vim.cmd('belowright split')
local footer_window = vim.api.nvim_get_current_win()
local footer_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(footer_window, footer_buffer)
vim.api.nvim_buf_set_lines(footer_buffer, 0, -1, false, {
  'unrelated commit',
  'unrelated file',
  'footer bottom',
})
vim.api.nvim_win_set_cursor(footer_window, { 3, 0 })
local editor_target_path = vim.fs.normalize(
  vim.fn.getcwd() .. '/tests/fixtures/symbol_project/example.lua'
)
local editor_target_file = { absolute_path = editor_target_path, opened = true }
local return_view = {
  close = function(self)
    self.closed = true
    branch_info_visible = false
  end,
  cur_entry = editor_target_file,
  cur_layout = {
    b = { id = historical_window },
    windows = { { id = historical_window } },
  },
  panel = {
    cur_item = { {}, { absolute_path = '/work/random-file.lua' } },
    log_options = {},
    updating = false,
    winid = footer_window,
  },
  tabpage = git_tabpage,
}
previous_editing_tabpage = editor_tabpage
current_view = return_view
enclosing_structure_result = {
  first_line = 1,
  label = 'open_picker',
  node_type = 'function_declaration',
}
panel.enter_git(return_view, function()
  diffview.return_to_editor_line()
end)
local original_schedule = vim.schedule
local original_cmd = vim.cmd
local original_return_defer = vim.defer_fn
local original_set_editor_buffer = vim.api.nvim_win_set_buf
local scheduled_editor_apply
local pending_return_close
local return_phase_order = {}
vim.cmd = function(command)
  if command == 'redraw' and vim.api.nvim_get_current_tabpage() == editor_tabpage then
    return_phase_order[#return_phase_order + 1] = 'render'
  end
  return original_cmd(command)
end
vim.schedule = function(callback)
  return_phase_order[#return_phase_order + 1] = 'jump'
  scheduled_editor_apply = callback
end
vim.defer_fn = function(callback, delay)
  if delay == 0 then
    pending_return_close = callback
    return
  end
  return original_return_defer(callback, delay)
end
vim.api.nvim_win_set_buf = function(window, buffer)
  local set_result = original_set_editor_buffer(window, buffer)
  if window == return_editor_window
      and vim.fs.normalize(vim.api.nvim_buf_get_name(buffer)) == editor_target_path then
    vim.keymap.set('n', '<Space>de', function() end, {
      buffer = buffer,
      desc = 'Search Git commits and issues',
    })
    vim.keymap.set('n', '<Space>dx', function() end, {
      buffer = buffer,
      desc = 'Editor-specific action',
    })
  end
  return set_result
end
assert(diffview.handle_ctrl_q(), 'Ctrl-Q did not invoke the Git line return callback')
-- Git mode exits immediately; the restored editor only displays the existing file.
assert(
  vim.api.nvim_get_current_tabpage() == editor_tabpage,
  'Footer Ctrl-Q did not return to the editor tab immediately'
)
local return_message_buffer = vim.fn.bufnr(editor_target_path)
assert(return_message_buffer > 0, 'Git exit did not address a target buffer')
assert(vim.b[return_message_buffer].git_return_cursor == nil,
  'Git exit retained an automatic cursor message')
assert(
  scheduled_editor_apply and vim.deep_equal(return_phase_order, { 'jump' }),
  'Git exit performed render work itself instead of handing it to the editor'
)
scheduled_editor_apply()
vim.api.nvim_win_set_buf = original_set_editor_buffer
vim.schedule = original_schedule
vim.defer_fn = original_return_defer
vim.cmd = original_cmd
assert(
  vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == editor_target_path
    and vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 0 })
    and vim.b[return_message_buffer].git_return_cursor == nil,
  'The editor return changed the cursor instead of only displaying the file'
)
assert(
  vim.deep_equal(return_phase_order, { 'jump', 'render' }),
  'The editor did not redraw after displaying the return file'
)
local restored_workspace_mapping = vim.fn.maparg('<Space>fw', 'n', false, true)
assert(
  restored_workspace_mapping.buffer == 0
    and restored_workspace_mapping.desc == 'Project workspace symbols',
  'Git return did not preserve the global project-definition mapping'
)
local restored_git_search_mapping = vim.fn.maparg('<Space>de', 'n', false, true)
assert(
  restored_git_search_mapping.buffer == 0
    and restored_git_search_mapping.desc == 'Search Git branches, commits, and issues',
  'Git return retained a buffer-local search mapping that cannot re-enter Git mode'
)
local preserved_editor_mapping = vim.fn.maparg('<Space>dx', 'n', false, true)
assert(
  preserved_editor_mapping.buffer == 1
    and preserved_editor_mapping.desc == 'Editor-specific action',
  'Git return removed an editor-owned buffer-local mapping'
)
assert(
  vim.wo[footer_window].winbar:match('RETURN')
    and vim.wo[footer_window].winbar:match('restoring editor'),
  'Git footer did not log the immediate editor restore'
)
local settled_reentry_calls = 0
assert(diffview.defer_until_settled('repository_search', function()
  settled_reentry_calls = settled_reentry_calls + 1
end), 'Git return did not accept an immediate editor re-entry action')
assert(diffview.defer_until_settled('repository_search', function()
  settled_reentry_calls = settled_reentry_calls + 1
end), 'Git return did not coalesce its immediate editor re-entry action')
assert(pending_return_close, 'Git return did not schedule Diffview teardown')
pending_return_close()
assert(vim.wait(100, function()
  return return_view.closed
    and settled_reentry_calls == 1
    and vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 0 })
end, 10), 'Git teardown did not preserve the already interactive editor target')
assert(
  branch_info_visible and statusline_branch_refreshes == 2,
  'Diffview teardown erased restored branch state'
)
assert(
  vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 0 }),
  'Editor handoff moved the cursor while opening the historical file'
)
enclosing_structure_result = nil

vim.api.nvim_set_current_tabpage(git_tabpage)
vim.api.nvim_buf_set_lines(historical_buffer, 0, 1, false, {
  'local function missing_from_worktree()',
})
local fallback_view = {
  close = function(self)
    self.closed = true
  end,
  cur_entry = editor_target_file,
  cur_layout = {
    b = { id = historical_window },
    windows = { { id = historical_window } },
  },
  panel = {
    cur_item = { {}, editor_target_file },
    log_options = {},
    updating = false,
    winid = footer_window,
  },
  tabpage = git_tabpage,
}
previous_editing_tabpage = editor_tabpage
current_view = fallback_view
enclosing_structure_result = {
  first_line = 1,
  label = 'missing_from_worktree',
  node_type = 'function_declaration',
}
panel.enter_git(fallback_view, function()
  diffview.return_to_editor_line()
end)
assert(diffview.handle_ctrl_q(), 'Direct editor routing did not close Git mode')
assert(
  vim.api.nvim_get_current_tabpage() == editor_tabpage,
  'Fallback return did not hand back to the editor tab immediately'
)
assert(
  vim.wait(100, function()
    return vim.api.nvim_get_current_tabpage() == editor_tabpage
      and vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == editor_target_path
  end, 5),
  'Fallback return did not restore the working-tree editor buffer first'
)
assert(
  vim.wait(100, function()
    return vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 0 })
  end, 5),
  'Direct editor routing moved the cursor while opening the AFTER file'
)
enclosing_structure_result = nil
assert(vim.wait(100, function()
  return fallback_view.closed
end, 10), 'Fallback Git return did not dispose its history view')
assert(statusline_branch_refreshes == 4, 'Fallback Git teardown erased branch statusline state')

vim.api.nvim_set_current_tabpage(git_tabpage)
local render_failure_view = {
  close = function(self)
    self.closed = true
  end,
  cur_entry = editor_target_file,
  cur_layout = {
    b = { id = historical_window },
    windows = { { id = historical_window } },
  },
  panel = {
    cur_item = { {}, editor_target_file },
    log_options = {},
    updating = false,
    winid = footer_window,
  },
  tabpage = git_tabpage,
}
previous_editing_tabpage = editor_tabpage
current_view = render_failure_view
panel.enter_git(render_failure_view, function()
  diffview.return_to_editor_line()
end)
local render_failure_notified = false
local original_notify = vim.notify
vim.cmd = function(command)
  if command == 'redraw' and vim.api.nvim_get_current_tabpage() == editor_tabpage then
    error('forced editor render failure')
  end
  return original_cmd(command)
end
vim.notify = function(message)
  if tostring(message):match('forced editor render failure') then
    render_failure_notified = true
  end
end
assert(diffview.handle_ctrl_q(), 'Editor render failure prevented Git mode teardown')
assert(vim.wait(200, function()
  return render_failure_notified
end, 10), 'Editor render failure was not reported')
vim.notify = original_notify
vim.cmd = original_cmd
assert(vim.wait(100, function()
  return render_failure_view.closed
end, 10), 'Render-failure Git return did not dispose its history view')
if vim.api.nvim_tabpage_is_valid(git_tabpage) then
  vim.api.nvim_set_current_tabpage(git_tabpage)
  vim.cmd('tabclose')
end

local preserved_editor_tabpage = vim.api.nvim_get_current_tabpage()
local preserved_editor_window = vim.api.nvim_get_current_win()
local restored_editor_buffer = vim.api.nvim_get_current_buf()
local preserved_editor_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_win_set_buf(preserved_editor_window, preserved_editor_buffer)
vim.api.nvim_buf_set_lines(preserved_editor_buffer, 0, -1, false, {
  'unsaved editor state',
  'must remain untouched',
})
vim.api.nvim_win_set_cursor(preserved_editor_window, { 2, 5 })
vim.cmd('tabnew')
local idle_git_tabpage = vim.api.nvim_get_current_tabpage()
local idle_after_window = vim.api.nvim_get_current_win()
local idle_view = {
  close = function(self)
    self.closed = true
  end,
  cur_entry = editor_target_file,
  cur_layout = { b = { id = idle_after_window } },
  git_diff_opened = false,
  panel = { cur_item = nil, log_options = {}, updating = false },
  tabpage = idle_git_tabpage,
}
previous_editing_tabpage = preserved_editor_tabpage
current_view = idle_view
panel.enter_git(idle_view, function()
  diffview.return_to_editor_line()
end)
assert(diffview.handle_ctrl_q(), 'Idle Git history did not exit Git mode')
assert(
  vim.api.nvim_get_current_tabpage() == preserved_editor_tabpage
    and vim.api.nvim_get_current_win() == preserved_editor_window
    and vim.api.nvim_get_current_buf() == preserved_editor_buffer
    and vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 5 })
    and vim.deep_equal(
      vim.api.nvim_buf_get_lines(preserved_editor_buffer, 0, -1, false),
      { 'unsaved editor state', 'must remain untouched' }
    ),
  'Idle Git history changed the editor state preserved before entry'
)
assert(vim.wait(100, function()
  return idle_view.closed
end, 10), 'Idle Git view was not disposed')
assert(
  statusline_branch_refreshes == 7,
  'Idle Git return did not restore branch statusline state'
)
if vim.api.nvim_tabpage_is_valid(idle_git_tabpage) then
  vim.api.nvim_set_current_tabpage(idle_git_tabpage)
  vim.cmd('tabclose')
end
vim.api.nvim_win_set_buf(preserved_editor_window, restored_editor_buffer)
vim.api.nvim_buf_delete(preserved_editor_buffer, { force = true })
previous_editing_tabpage = nil

local symbol_view = diffview.open_file_history({
  kind = 'symbol',
  location = {
    relative_path = 'lua/example.lua',
    root = '/work/repository',
    structure = { first_line = 1, label = 'changed_scope', last_line = 6 },
  },
  range = { 1, 6 },
  cursor_target = {
    line = 1,
    path = 'lua/example.lua',
    structure = { first_line = 1, label = 'changed_scope', last_line = 6 },
  },
})
local symbol_window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(symbol_window, rendered_buffer)
vim.api.nvim_win_set_cursor(symbol_window, { 3, 0 })
vim.wo[symbol_window].foldmethod = 'manual'
vim.cmd('2,5fold')
vim.cmd('normal! zc')
local symbol_file = {
  bufnr = rendered_buffer,
  custom_folds = { type = 'diff_patch', { 2, 5 } },
  opened = true,
  path = 'lua/example.lua',
  rev = { commit = string.rep('3', 40) },
}
local symbol_entry = {
  commit = { hash = string.rep('3', 40) },
  files = { symbol_file },
  folded = false,
  get_diff = function()
    return {
      hunks = {
        {
          new_content = { { 1, 'modified' } },
          new_row = 4,
          new_size = 1,
          old_content = { { 1, 'original' } },
          old_row = 4,
        },
      },
    }
  end,
}
local highlighted_symbol_file
symbol_view.cur_layout = {
  a = { file = symbol_file, id = symbol_window },
  b = { file = symbol_file, id = symbol_window },
}
symbol_view.cur_entry = symbol_file
symbol_view.panel = {
  cur_item = { symbol_entry, symbol_file },
  entries = { symbol_entry },
  find_entry = function()
    return symbol_entry
  end,
  highlight_item = function(_, file)
    highlighted_symbol_file = file
  end,
  log_options = {},
  updating = false,
  winid = symbol_window,
}
symbol_view.git_footer_enriching = false
enclosing_structure_line = 1
history_lifecycle.mark_list_ready(symbol_view, 1)
history_lifecycle.mark_enrichment_ready(
  symbol_view,
  symbol_entry.commit.hash,
  symbol_file.path
)
symbol_view.git_diff_opened = true
local symbol_file_open_pre = assert(symbol_view.events.file_open_pre)
local symbol_file_open_post = assert(symbol_view.events.file_open_post)
symbol_file_open_pre(nil, symbol_file)
symbol_file_open_post(nil, symbol_file)
vim.wait(100, function()
  return history_lifecycle.is_ready(symbol_view)
end, 5)
assert(
  vim.wo[symbol_window].foldmethod == 'diff'
    and symbol_file.custom_folds == nil
    and highlighted_symbol_file == symbol_file
    and vim.api.nvim_win_get_cursor(symbol_window)[1] == 1,
  'Symbol history did not use ordinary folds and jump to the traced declaration on open'
)
enclosing_structure_line = nil

local file_target_view = diffview.open_file_history({
  kind = 'file',
  location = {
    relative_path = 'lua/example.lua',
    root = '/work/repository',
  },
  cursor_target = { line = 2, path = 'lua/example.lua' },
})
local file_target_window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(file_target_window, rendered_buffer)
vim.wo[file_target_window].foldmethod = 'manual'
vim.api.nvim_win_set_cursor(file_target_window, { 4, 0 })
local file_target_file = {
  bufnr = rendered_buffer,
  opened = true,
  path = 'lua/example.lua',
  rev = { commit = string.rep('5', 40) },
}
local file_target_entry = {
  commit = { hash = string.rep('5', 40) },
  files = { file_target_file },
  folded = false,
  get_diff = function()
    return { hunks = {} }
  end,
}
file_target_view.cur_layout = {
  a = { file = file_target_file, id = file_target_window },
  b = { file = file_target_file, id = file_target_window },
}
file_target_view.cur_entry = file_target_file
file_target_view.panel = {
  cur_item = { file_target_entry, file_target_file },
  entries = { file_target_entry },
  find_entry = function()
    return file_target_entry
  end,
  log_options = {},
  updating = false,
  winid = file_target_window,
}
file_target_view.git_footer_enriching = false
history_lifecycle.mark_list_ready(file_target_view, 1)
history_lifecycle.mark_enrichment_ready(
  file_target_view,
  file_target_entry.commit.hash,
  file_target_file.path
)
file_target_view.git_diff_opened = true
file_target_view.events.file_open_pre(nil, file_target_file)
file_target_view.events.file_open_post(nil, file_target_file)
vim.wait(100, function()
  return history_lifecycle.is_ready(file_target_view)
end, 5)
assert(
  vim.api.nvim_win_get_cursor(file_target_window)[1] == 2,
  'File history explicit open did not land on the cursor-target line'
)
assert(
  vim.wo[file_target_window].foldmethod == 'manual',
  'File history without a line range rewrote the code pane fold method'
)

do
  local native_seed_hash = string.rep('3', 40)
  local native_seed_file = { path = 'lua/first-only.lua' }
  local native_seed_entry = {
    commit = { hash = native_seed_hash, ref_names = '' },
    files = { native_seed_file },
  }
  local native_seed_view = diffview.open_file_history({
    history_ref = 'refs/heads/main',
    kind = 'repository',
    location = { root = '/work/repository' },
    preview_commit = native_seed_hash,
    selected_commit = native_seed_hash,
  })
  native_seed_view.panel = {
    bufid = vim.api.nvim_get_current_buf(),
    cur_item = { native_seed_entry, nil },
    entries = { native_seed_entry },
    log_options = {},
    render = function() end,
    redraw = function() end,
    update_components = function() end,
    updating = false,
  }
  local native_seed_installed = false
  footer_attach_handlers.install_rows(native_seed_view, {
    {
      author = 'Author',
      hash = native_seed_hash,
      parent_hashes = { string.rep('2', 40) },
      ref_names = '',
      reflog_selector = '',
      rel_date = 'now',
      subject = 'Native seed is incomplete',
      time = 1,
      time_offset = '+0000',
    },
  }, 'initial', function(installed)
    native_seed_installed = installed
  end)
  assert(
    native_seed_installed
      and native_seed_view.panel.entries[1] == native_seed_entry
      and native_seed_entry.git_details_loaded == false
      and native_seed_entry.folded == true,
    'A reused native seed was treated as complete or expanded during metadata install'
  )
end

local exact_detached_commit = string.rep('4', 40)
local exact_detached_view = diffview.open_file_history({
  detached_head_commit = exact_detached_commit,
  kind = 'repository',
  location = { root = '/work/repository' },
  revision = exact_detached_commit,
  unbounded = true,
})
assert(
  vim.deep_equal(history_calls[#history_calls].arguments, {
    '-C/work/repository',
    '--max-count=100000',
    '--range=' .. exact_detached_commit .. '^!',
  })
    and exact_detached_view.git_search_options.detached_head_commit == exact_detached_commit
    and exact_detached_view.git_search_options.revision == nil,
  'Fresh detached history did not mount one exact commit and preserve its dispatcher anchor'
)

local standalone_commit_hash = string.rep('6', 40)
local standalone_history_count = #history_calls
assert(diffview.open_search_commit(nil, {
  checked_out_branch = 'main',
  detached_head_commit = exact_detached_commit,
  kind = 'repository',
  location = { root = '/work/repository' },
}, {
  branch_name = 'main',
  hash = standalone_commit_hash,
  history_ref = 'refs/heads/main',
  source = 'REMOTE',
}))
local standalone_commit_view = opened_views[#opened_views]
standalone_commit_view.panel = {
  cur_item = {},
  entries = {},
  log_options = {},
  updating = false,
}
assert(
  #history_calls == standalone_history_count + 1
    and vim.deep_equal(history_calls[#history_calls].arguments, {
      '-C/work/repository',
      '--max-count=1',
      '--range=refs/heads/main',
    })
    and standalone_commit_view.git_checked_out_branch == 'main'
    and standalone_commit_view.git_detached_head_commit == exact_detached_commit
    and standalone_commit_view.git_history_options.selected_commit == standalone_commit_hash
    and panel.level() == 'git',
  'Standalone commit selection did not open Git mode at the requested revision'
)
assert(
  not vim.wait(100, function()
    return #history_calls > standalone_history_count + 1
  end, 5),
  'Missing preview commit remounted the complete branch instead of staying bounded'
)

local implicit_history_view = diffview.open_file_history({
  kind = 'repository',
  location = { root = '/work/repository' },
})
local implicit_file_activations = {}
local implicit_revision_disposals = 0
local implicit_revision_files = {
  {
    dispose_buffer = function(self)
      implicit_revision_disposals = implicit_revision_disposals + 1
      self.bufnr = nil
    end,
    nulled = false,
  },
  {
    dispose_buffer = function(self)
      implicit_revision_disposals = implicit_revision_disposals + 1
      self.bufnr = nil
    end,
    nulled = true,
  },
}
local implicit_history_file = {
  layout = {
    files = function()
      return implicit_revision_files
    end,
  },
  opened = false,
  path = 'lua/implicit.lua',
  set_active = function(_, active)
    implicit_file_activations[#implicit_file_activations + 1] = active
  end,
}
local implicit_history_entry = {
  commit = { hash = string.rep('7', 40) },
  files = { implicit_history_file },
}
local implicit_null_opens = 0
implicit_history_view.cur_layout = {
  detach_files = function() end,
  open_null = function()
    implicit_null_opens = implicit_null_opens + 1
  end,
}
implicit_history_view.panel = {
  cur_item = { implicit_history_entry, implicit_history_file },
  entries = { implicit_history_entry },
  set_cur_item = function(self, current_item)
    self.cur_item = current_item
  end,
  updating = false,
}
implicit_history_view.events.file_open_pre(nil, implicit_history_file)
assert(
  implicit_revision_files[1].nulled and implicit_revision_files[2].nulled,
  'History initialization did not suppress its implicit historical blob load'
)
implicit_history_view.cur_entry = implicit_history_file
implicit_history_view.events.file_open_post(nil, implicit_history_file)
implicit_history_file.opened = true
assert(
  implicit_file_activations[1] == false,
  'History initialization did not deactivate Diffview\'s implicit first file before loading'
)
assert(vim.wait(200, function()
  return implicit_history_view.cur_entry == nil
end, 5), 'History initialization retained Diffview\'s implicit first file')
assert(
  implicit_null_opens > 0
    and implicit_history_view.panel.cur_item[1] == implicit_history_entry
    and implicit_history_view.panel.cur_item[2] == nil
    and implicit_history_view.git_diff_opened == false,
  'History initialization did not settle directly onto its native null layout'
)
assert(
  not implicit_revision_files[1].nulled
    and implicit_revision_files[2].nulled
    and implicit_revision_disposals == 2,
  'History initialization did not restore reusable revision files after its null warm-up'
)

-- Diffview fires one more auto-open from its trailing throttled stream render after
-- the list has settled; a ready history must retire it instead of rendering code.
local trailing_view = diffview.open_file_history({
  kind = 'file',
  location = { relative_path = 'lua/implicit.lua', root = '/work/repository' },
})
local trailing_activations = {}
local trailing_revision_files = {
  { dispose_buffer = function(self) self.bufnr = nil end, nulled = false },
  { dispose_buffer = function(self) self.bufnr = nil end, nulled = false },
}
local trailing_file = {
  layout = {
    files = function()
      return trailing_revision_files
    end,
  },
  opened = false,
  path = 'lua/implicit.lua',
  set_active = function(_, active)
    trailing_activations[#trailing_activations + 1] = active
  end,
}
local trailing_entry = {
  commit = { hash = string.rep('8', 40) },
  files = { trailing_file },
  folded = true,
}
local trailing_null_opens = 0
trailing_view.cur_layout = {
  detach_files = function() end,
  open_null = function()
    trailing_null_opens = trailing_null_opens + 1
  end,
}
trailing_view.panel = {
  cur_item = { trailing_entry, nil },
  entries = { trailing_entry },
  set_cur_item = function(self, current_item)
    self.cur_item = current_item
  end,
  updating = false,
}
history_lifecycle.mark_idle_ready(trailing_view, 'test scoped idle readiness')
assert(
  history_lifecycle.is_ready(trailing_view),
  'Scoped test view did not reach its idle ready state'
)
trailing_view.panel.cur_item = { trailing_entry, trailing_file }
trailing_view.events.file_open_pre(nil, trailing_file)
trailing_view.cur_entry = trailing_file
trailing_view.events.file_open_post(nil, trailing_file)
assert(
  trailing_activations[1] == false,
  'A ready scoped history did not deactivate Diffview\'s trailing auto-open'
)
assert(vim.wait(200, function()
  return trailing_view.cur_entry == nil
end, 5), 'A ready scoped history did not retire its trailing auto-open')
assert(
  trailing_null_opens > 0
    and trailing_view.panel.cur_item[1] == trailing_entry
    and trailing_view.panel.cur_item[2] == nil
    and trailing_view.git_diff_opened == false
    and history_lifecycle.phase(trailing_view) == 'ready',
  'A ready scoped history rendered Diffview\'s trailing auto-open instead of retiring it'
)

vim.api.nvim_buf_delete(rendered_left_buffer, { force = true })
vim.api.nvim_buf_delete(rendered_buffer, { force = true })

vim.keymap.del('n', '<Space>fw')
vim.keymap.del('c', '<CR>')
vim.api.nvim_del_augroup_by_name('ConfigGitDiffviewProtection')
for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
