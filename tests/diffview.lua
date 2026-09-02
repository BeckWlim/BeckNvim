local replaced_modules = {
  'config.git',
  'config.git.diffview',
  'config.git.issue',
  'config.git.search',
  'config.search.workspace_symbols',
  'config.syntax.treesitter_context',
  'config.ui.statusline',
  'diffview',
  'diffview.actions',
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
local queued_full_file_dictionary
local pending_full_file_list_callback
local defer_full_file_list = false
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
    assert(details.hl_group == 'DiffviewReference', 'Scoped target filename was not highlighted')
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
    and initial_metadata_highlights.GitHistorySectionDivider
    and initial_metadata_highlights.GitHistoryScopeTag,
  'Scoped footer did not tag every target file and split its branch segments'
)
assert(
  vim.wo[annotated_footer_view.panel.winid].winbar:match('CURRENT BRANCH · main')
    and vim.wo[annotated_footer_view.panel.winid].winbar:match('GitHistoryCurrentTag')
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
local seed_file = {
  destroy = function()
    seed_destroyed = true
  end,
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
    entries = { expanded_entry },
    render = function()
      expanded_render_calls = expanded_render_calls + 1
    end,
    redraw = function()
      expanded_redraw_calls = expanded_redraw_calls + 1
    end,
    set_cur_item = function(self, item)
      self.cur_item = item
      item[2]:set_active(true)
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
    view.panel:set_cur_item({ expanded_entry, file })
    view.panel:highlight_item(file)
  end,
  tabpage = vim.api.nvim_get_current_tabpage(),
}
assert(diffview.enrich_history_footer(expanded_view), 'Scoped history enrichment did not start')
assert(vim.wait(100, function()
  return not expanded_view.git_footer_enriching
end, 10), 'Scoped history enrichment did not finish')
assert(
  #full_file_list_calls == 1
    and vim.deep_equal(full_file_list_calls[1].path_args, {})
    and full_file_list_calls[1].left == 'parent-revision'
    and full_file_list_calls[1].right == 'commit-revision'
    and full_file_list_calls[1].options.show_untracked == false,
  'Scoped history did not request the complete parent-to-commit file list'
)
assert(
  #expanded_entry.files == 2
    and expanded_entry.files[1] == unrelated_file
    and expanded_entry.files[2] == seed_file
    and expanded_entry.git_target_file == seed_file
    and selected_expanded_file == nil,
  'Scoped history did not retain the rendered target while adding the commit file list'
)
assert(
  not expanded_entry.single_file
    and expanded_entry.folded
    and expanded_view.panel.single_file == false
    and highlighted_expanded_item == expanded_entry
    and expanded_component_updates == 1
    and expanded_render_calls == 1
    and expanded_redraw_calls == 1
    and entry_status_updates == 1
    and entry_stats_updates == 1,
  'Scoped history did not rebuild a collapsed commit-only footer through its owned renderer'
)
assert(not seed_destroyed, 'Active filtered file was destroyed before Diffview selected its replacement')

current_view = expanded_view
native_history_selection = function()
  expanded_entry.folded = false
end
for _, scoped_kind in ipairs({ 'file', 'symbol' }) do
  expanded_entry.folded = true
  expanded_view.git_history_kind = scoped_kind
  expanded_view.git_history_options.kind = scoped_kind
  selected_expanded_file = nil
  highlighted_expanded_item = nil
  find_mapping('file_history_panel', '<cr>')[3]()
  assert(vim.wait(100, function()
    return selected_expanded_file == seed_file
  end, 5), ('Expanded %s commit did not open its target file'):format(scoped_kind))
  assert(
    highlighted_expanded_item == seed_file
      and expanded_view.panel.cur_item[1] == expanded_entry
      and expanded_view.panel.cur_item[2] == seed_file,
    ('Expanded %s commit did not highlight its target child row'):format(scoped_kind)
  )
end
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
    '--max-count=50',
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
vim.api.nvim_win_set_buf(rendered_window, rendered_buffer)
vim.api.nvim_buf_set_lines(rendered_buffer, 0, -1, false, {
  'local function changed_scope()',
  '  local value = 1',
  '  if value then',
  '    value = value + 1',
  '  end',
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
      bufnr = rendered_buffer,
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
branch_view.events.file_open_pre(nil, rendered_event_file)
branch_view.events.file_open_post(nil, rendered_event_file)
vim.wait(100, function()
  return history_lifecycle.is_ready(branch_view)
end, 5)
assert(
  vim.wo[rendered_window].cursorline and vim.wo[rendered_window].cursorlineopt == 'line',
  'Diffview code pane did not reduce its cursor hint to one whole-line background'
)
assert(
  vim.fn.foldclosed(2) == -1 and vim.api.nvim_win_get_cursor(rendered_window)[1] == 4,
  'Selected diff hunk did not reveal its enclosing definition while retaining the changed line'
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
  #history_calls == 1 and selected_history_file == existing_target_file,
  'Search review replaced history or missed the scoped file in the mounted list'
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
    '--range=refs/heads/main',
  })
    and not loaded_commit_view.git_parent_view
    and loaded_commit_view.git_branch_name == 'main'
    and loaded_commit_view.git_detached_head_commit == detached_head_commit
    and loaded_commit_view.git_history_options.review_only
    and loaded_commit_view.git_search_options.kind == 'repository'
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
  files = { performance_seed_file },
  folded = true,
}
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
  entries = { performance_entry },
  log_options = {},
  updating = false,
  winid = vim.api.nvim_get_current_win(),
}
assert(vim.wait(200, function()
  return pending_full_file_list_callback ~= nil
end, 10), 'Scoped footer enrichment did not expose its in-flight diff request')
current_view = performance_view
assert(
  not diffview.handle_ctrl_q(),
  'Ctrl-Q exited while required scoped enrichment was still running'
)
assert(
  performance_view.git_footer_enriching
    and performance_view.git_footer_enrichment_token ~= nil
    and history_lifecycle.phase(performance_view) == 'enriching',
  'Pending Git exit cancelled the work required to reach a stable render boundary'
)
performance_view.panel.updating = true
assert(diffview.close(), 'Rendering Git history refused an exit request')
assert(
  not performance_view.git_footer_enriching,
  'Git exit retained configuration-owned footer enrichment'
)
assert(vim.wait(100, function()
  return performance_view.closed
end, 10), 'Plugin-owned history loading unnecessarily delayed Git exit')
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
  'Cancelled footer enrichment continued launching commit diff requests'
)
defer_full_file_list = false
pending_full_file_list_callback = nil
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
assert(not diffview.handle_ctrl_q(), 'Unready Ctrl-Q return incorrectly exited Git mode')
assert(
  panel.level() == 'git'
    and not waiting_view.closed
    and waiting_view.git_return_requested
    and vim.wo[waiting_view.panel.winid].winbar:match('REMOTE · RETURN')
    and vim.wo[waiting_view.panel.winid].winbar:match('waiting for the rendered AFTER file'),
  'Unready Ctrl-Q return did not remain in Git mode with a footer explanation'
)

local editor_tabpage = vim.api.nvim_get_current_tabpage()
vim.cmd({ cmd = 'edit', args = { 'README.md' } })
vim.keymap.set('n', '<Space>fw', function() end, { desc = 'Project workspace symbols' })
vim.keymap.set('n', '<Space>de', function() end, { desc = 'Enter Git mode and search repository' })
local return_editor_window = vim.api.nvim_get_current_win()
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
local original_set_current_tabpage = vim.api.nvim_set_current_tabpage
local original_set_editor_buffer = vim.api.nvim_win_set_buf
local scheduled_declaration_jump
local pending_return_close
local editor_buffer_at_focus
local branch_refreshes_at_focus
local return_phase_order = {}
vim.cmd = function(command)
  if command == 'redraw' and vim.api.nvim_get_current_tabpage() == editor_tabpage then
    return_phase_order[#return_phase_order + 1] = 'render'
  end
  return original_cmd(command)
end
vim.schedule = function(callback)
  return_phase_order[#return_phase_order + 1] = 'jump'
  scheduled_declaration_jump = callback
end
vim.defer_fn = function(callback, delay)
  if delay == 0 then
    pending_return_close = callback
    return
  end
  return original_return_defer(callback, delay)
end
vim.api.nvim_set_current_tabpage = function(tabpage)
  if tabpage == editor_tabpage then
    local editor_window = vim.api.nvim_tabpage_get_win(editor_tabpage)
    editor_buffer_at_focus = vim.api.nvim_win_get_buf(editor_window)
    branch_refreshes_at_focus = statusline_branch_refreshes
  end
  return original_set_current_tabpage(tabpage)
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
vim.api.nvim_win_set_buf = original_set_editor_buffer
vim.api.nvim_set_current_tabpage = original_set_current_tabpage
vim.schedule = original_schedule
vim.defer_fn = original_return_defer
vim.cmd = original_cmd
assert(
  vim.api.nvim_get_current_tabpage() == editor_tabpage
    and vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == editor_target_path,
  'Footer Ctrl-Q did not prioritize restoring the working-tree editor buffer'
)
assert(
  editor_buffer_at_focus
    and vim.fs.normalize(vim.api.nvim_buf_get_name(editor_buffer_at_focus)) == editor_target_path,
  'Git return exposed an intermediate editor buffer before the Diffview file'
)
assert(
  branch_refreshes_at_focus == 1,
  'Git return did not prepare branch state before the first editor frame'
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
    and restored_git_search_mapping.desc == 'Enter Git mode and search repository',
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
    and vim.wo[footer_window].winbar:match('cursor alignment follows render'),
  'Git footer did not log the pending render-gated cursor alignment'
)
assert(
  not scheduled_declaration_jump and vim.deep_equal(return_phase_order, { 'render' }),
  'Git return scheduled cursor alignment before Diffview teardown'
)
local settled_reentry_calls = 0
assert(diffview.defer_until_settled('repository_search', function()
  settled_reentry_calls = settled_reentry_calls + 1
end), 'Git return did not accept an immediate editor re-entry action')
assert(diffview.defer_until_settled('repository_search', function()
  settled_reentry_calls = settled_reentry_calls + 1
end), 'Git return did not coalesce its immediate editor re-entry action')
local alignment_notification
local original_alignment_notify = vim.notify
local original_alignment_defer = vim.defer_fn
local original_alignment_cmd = vim.cmd
local original_alignment_set_cursor = vim.api.nvim_win_set_cursor
local restored_editor_window = vim.api.nvim_get_current_win()
local alignment_cursor_at_notification
local alignment_cursor_updates = {}
local alignment_redraws = 0
local transient_clear_callback
local transient_clear_delay
vim.notify = function(message, level)
  alignment_notification = { level = level, message = message }
  alignment_cursor_at_notification = vim.api.nvim_win_get_cursor(restored_editor_window)
end
vim.defer_fn = function(callback, delay)
  transient_clear_callback = callback
  transient_clear_delay = delay
end
vim.cmd = function(command)
  if command == 'redraw' then
    alignment_redraws = alignment_redraws + 1
  end
  return original_alignment_cmd(command)
end
vim.api.nvim_win_set_cursor = function(window, cursor)
  if window == restored_editor_window then
    alignment_cursor_updates[#alignment_cursor_updates + 1] = vim.deepcopy(cursor)
  end
  return original_alignment_set_cursor(window, cursor)
end
assert(pending_return_close, 'Git return did not schedule Diffview teardown')
pending_return_close()
assert(vim.wait(100, function()
  return return_view.closed
    and settled_reentry_calls == 1
    and alignment_notification ~= nil
    and vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 4 })
end, 10), 'Git teardown did not release the async cursor alignment task')
vim.api.nvim_win_set_cursor = original_alignment_set_cursor
vim.cmd = original_alignment_cmd
vim.defer_fn = original_alignment_defer
vim.notify = original_alignment_notify
assert(
  branch_info_visible and statusline_branch_refreshes == 2,
  'Diffview teardown erased branch state before cursor alignment'
)
assert(
  alignment_notification
    and alignment_notification.level == vim.log.levels.INFO
    and alignment_notification.message == 'Git return: editor cursor aligned',
  'Editor-side cursor alignment did not log completion in the ordinary message area'
)
assert(
  vim.deep_equal(alignment_cursor_at_notification, { 2, 4 }) and alignment_redraws == 1,
  'Git return logged completion before the final aligned editor frame'
)
assert(
  #alignment_cursor_updates == 1
    and vim.deep_equal(alignment_cursor_updates[1], { 2, 4 }),
  'Git return rendered intermediate cursor positions during alignment'
)
assert(
  type(transient_clear_callback) == 'function' and transient_clear_delay == 1200,
  'Git return completion notice did not receive a bounded transient lifespan'
)
local original_alignment_echo = vim.api.nvim_echo
local transient_clear_call
vim.api.nvim_echo = function(chunks, history, options)
  transient_clear_call = {
    chunks = vim.deepcopy(chunks),
    history = history,
    options = vim.deepcopy(options),
  }
end
transient_clear_callback()
vim.api.nvim_echo = original_alignment_echo
assert(
  transient_clear_call
    and vim.deep_equal(transient_clear_call.chunks, {})
    and transient_clear_call.history == false
    and vim.deep_equal(transient_clear_call.options, {}),
  'Git return completion notice did not clear the ordinary message area'
)
assert(
  vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 4 }),
  'Rendered editor did not preserve the cursor distance from the matched declaration'
)
assert(statusline_branch_refreshes == 2, 'Cursor alignment erased restored branch statusline state')
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
assert(diffview.handle_ctrl_q(), 'Unmatched declaration prevented Git mode from closing')
assert(
  vim.api.nvim_get_current_tabpage() == editor_tabpage
    and vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == editor_target_path,
  'Fallback return did not restore the working-tree editor buffer first'
)
assert(
  vim.wait(100, function()
    return vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 4 })
  end, 5),
  'Async unmatched declaration did not fall back to the rendered AFTER file line'
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
local render_failure_scheduled_jump = false
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
vim.schedule = function()
  render_failure_scheduled_jump = true
end
assert(diffview.handle_ctrl_q(), 'Editor render failure prevented Git mode teardown')
vim.schedule = original_schedule
vim.notify = original_notify
vim.cmd = original_cmd
assert(render_failure_notified, 'Editor render failure was not reported')
assert(vim.wait(100, function()
  return render_failure_view.closed
end, 10), 'Render-failure Git return did not dispose its history view')
assert(
  not render_failure_scheduled_jump,
  'Git return scheduled a cursor jump after the editor render failed'
)
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
local absent_git_tabpage = vim.api.nvim_get_current_tabpage()
local absent_after_window = vim.api.nvim_get_current_win()
local absent_view = {
  close = function(self)
    self.closed = true
  end,
  cur_entry = { absolute_path = '/work/missing-from-working-tree.lua', opened = true },
  cur_layout = { b = { id = absent_after_window } },
  panel = { cur_item = nil, log_options = {}, updating = false },
  tabpage = absent_git_tabpage,
}
previous_editing_tabpage = preserved_editor_tabpage
current_view = absent_view
panel.enter_git(absent_view, function()
  diffview.return_to_editor_line()
end)
assert(diffview.handle_ctrl_q(), 'Absent working-tree target did not exit Git mode')
assert(
  vim.api.nvim_get_current_tabpage() == preserved_editor_tabpage
    and vim.api.nvim_get_current_win() == preserved_editor_window
    and vim.api.nvim_get_current_buf() == preserved_editor_buffer
    and vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 5 })
    and vim.deep_equal(
      vim.api.nvim_buf_get_lines(preserved_editor_buffer, 0, -1, false),
      { 'unsaved editor state', 'must remain untouched' }
    ),
  'Absent working-tree target changed the preserved editor state'
)
assert(vim.wait(100, function()
  return absent_view.closed
end, 10), 'Absent-target Git view was not disposed')
assert(
  statusline_branch_refreshes == 7,
  'Absent-target Git return did not restore branch statusline state'
)
if vim.api.nvim_tabpage_is_valid(absent_git_tabpage) then
  vim.api.nvim_set_current_tabpage(absent_git_tabpage)
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
})
local symbol_window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(symbol_window, rendered_buffer)
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
  'Symbol history did not use ordinary full-file folds, highlight its opened target, and jump'
)
enclosing_structure_line = nil

vim.api.nvim_buf_delete(rendered_buffer, { force = true })

vim.keymap.del('n', '<Space>fw')
vim.keymap.del('c', '<CR>')
vim.api.nvim_del_augroup_by_name('ConfigGitDiffviewProtection')
for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
