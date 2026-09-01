local replaced_modules = {
  'config.git',
  'config.git.diffview',
  'config.git.issue',
  'config.git.search',
  'config.search.workspace_symbols',
  'config.syntax.treesitter_context',
  'diffview',
  'diffview.lib',
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
local disposed_views = {}
local checkout_call
local enclosing_structure_line

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
package.loaded['config.search.workspace_symbols'] = { open_buffer = function() end }
package.loaded['config.syntax.treesitter_context'] = {
  enclosing_structure = function()
    return enclosing_structure_line and { first_line = enclosing_structure_line } or nil
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
}
package.loaded['config.git.diffview'] = nil

local diffview = require('config.git.diffview')
local panel = require('config.git.panel')
panel.reset()
diffview.setup()
assert(configured_options, 'Shared Diffview module did not configure the renderer')
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
  assert(find_mapping(context, '<Space>de'), 'Git search is missing from Diffview context: ' .. context)
  assert(not find_mapping(context, '<Space>df'), 'Git mode retained the overloaded file-history binding')
  assert(not find_mapping(context, '<C-b>'), 'Git mode retained the obsolete branch-picker binding')
  assert(find_mapping(context, '<Space>dp'), 'History-panel toggle is missing: ' .. context)
  assert(find_mapping(context, '<Tab>'), 'Pane traversal is missing: ' .. context)
  assert(not find_mapping(context, '<Space>dc'), 'Obsolete commit-checkout key remains: ' .. context)
end
assert(
  find_mapping('file_history_panel', '<Space>dm'),
  'Git history list lacks guarded checkout for its selected commit'
)
assert(
  not find_mapping('view', '<Space>dm') and not find_mapping('file_panel', '<Space>dm'),
  'Commit checkout escaped the Git history list scope'
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
    and footer_render_calls == 1
    and footer_redraw_calls == 1,
  'Footer adaptation changed filter semantics or bypassed the owned renderer'
)
assert(
  vim.wo[filtered_view.panel.winid].winbar:match('SYMBOL')
    and vim.wo[filtered_view.panel.winid].winbar:match('lua/example.lua')
    and vim.wo[filtered_view.panel.winid].winbar:match(':10%-20'),
  'Symbol footer metadata lost its scope label, path, or line range'
)

filtered_entry.folded = true
filtered_view.panel.get_item_at_cursor = function()
  return filtered_entry
end
current_view = filtered_view
find_mapping('file_history_panel', '<cr>')[3]()
assert(
  not filtered_entry.folded and footer_render_calls == 2 and footer_redraw_calls == 2,
  'Filtered commit row did not reuse the footer hierarchy toggle'
)
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
current_view.panel.get_log_entry_at_cursor = function()
  return { commit = { hash = list_commit_hash } }
end
current_view.git_branch_name = 'main'
current_view.git_result_source = 'LOCAL'
find_mapping('file_history_panel', '<Space>dm')[3]()
assert(
  checkout_call
    and checkout_call.root == '/work/repository'
    and checkout_call.commit_hash == list_commit_hash
    and checkout_call.parent_view == current_view
    and checkout_call.commit_context.branch_name == 'main',
  'History-list checkout did not target its selected commit and owning Git view'
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
branch_view.panel = {
  cur_item = {
    {
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
    },
  },
}
branch_view.events.file_open_post(nil, {})
assert(
  vim.wo[rendered_window].cursorline and vim.wo[rendered_window].cursorlineopt == 'line',
  'Diffview code pane did not reduce its cursor hint to one whole-line background'
)
assert(
  vim.fn.foldclosed(2) == -1 and vim.api.nvim_win_get_cursor(rendered_window)[1] == 4,
  'Selected diff hunk did not reveal its enclosing definition while retaining the changed line'
)
enclosing_structure_line = nil

local existing_commit_hash = string.rep('e', 40)
local existing_file = { path = 'lua/existing.lua' }
local selected_history_file
branch_view.set_file = function(_, file)
  selected_history_file = file
end
branch_view.panel = {
  cur_item = {},
  entries = {
    {
      commit = { hash = existing_commit_hash },
      files = { existing_file },
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
  #history_calls == 1 and selected_history_file == existing_file,
  'Search review replaced history instead of selecting a commit already in the mounted list'
)

local loaded_commit = {
  branch_name = 'main',
  hash = string.rep('b', 40),
  history_ref = 'refs/heads/main',
  source = 'LOCAL',
}
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
assert(vim.wait(100, function()
  return loaded_commit_view.closed and disposed_views[2] == loaded_commit_view
end, 10), 'Second commit transition did not retire its previous Git history')
assert(panel.level() == 'git', 'Commit selection exited the ordinary Git panel layer')

selected_commit_view.panel = { cur_item = nil, log_options = {}, updating = false }
current_view = selected_commit_view
find_mapping('view', '<C-q>')[3]()
assert(vim.wait(100, function()
  return selected_commit_view.closed
    and disposed_views[#disposed_views] == selected_commit_view
end, 10), 'An empty commit diff prevented Git history from closing cleanly')
assert(panel.level() == 'editor', 'Closing branch history did not restore the editor layer')

vim.api.nvim_buf_delete(rendered_buffer, { force = true })

vim.keymap.del('c', '<CR>')
vim.api.nvim_del_augroup_by_name('ConfigGitDiffviewProtection')
for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
