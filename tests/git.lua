local repository = require('config.git.repository')
local git_ui = require('config.git.ui')

assert(repository.max_history_entries == 50, 'Git history cap changed unexpectedly')
assert(repository.max_branch_entries == 100, 'Git branch cap changed unexpectedly')

local branch_output = table.concat({
  '*\trefs/heads/main\tmain\t1111111111111111111111111111111111111111\torigin/main\t2026-08-31\tcurrent work',
  ' \trefs/remotes/origin/main\torigin/main\t1111111111111111111111111111111111111111\t\t2026-08-31\tcurrent work',
  ' \trefs/remotes/origin/feature/topic\torigin/feature/topic\t2222222222222222222222222222222222222222\t\t2026-08-30\tnew topic',
  ' \trefs/remotes/origin/HEAD\torigin/HEAD\t1111111111111111111111111111111111111111\t\t2026-08-31\tremote head',
}, '\n')
local branches = repository.parse_branches(branch_output)
assert(#branches == 3, 'Branch parser retained the remote HEAD pseudo-ref')
assert(
  branches[1].current
    and branches[1].short_name == 'main'
    and branches[1].tip_commit == string.rep('1', 40),
  'Current branch was not identified'
)
assert(
  branches[2].is_remote and branches[2].short_name == 'origin/main',
  'Remote branch lost its read-only remote-tracking ref'
)
assert(
  branches[3].refname == 'refs/remotes/origin/feature/topic',
  'Remote-only branch did not retain its exact review ref'
)
local branch_command = repository.commands.branches()
assert(
  vim.tbl_contains(branch_command, '--count=' .. repository.max_branch_entries),
  'Branch list command did not bound its result count'
)
assert(vim.tbl_contains(branch_command, '--sort=-HEAD'), 'Current branch was not prioritized')

local branch_record = git_ui.branch_record(branches[1])
assert(branch_record.display_text:match('LOCAL'), 'Branch row lost its local/remote kind')
assert(branch_record.display_text:match('main'), 'Branch row lost its short name')
assert(branch_record.ordinal:match('origin/main'), 'Branch search text lost its upstream')
local styled_branch_text, styled_branch_highlights = branch_record.display(branch_record)
assert(
  styled_branch_text == branch_record.display_text and #styled_branch_highlights == 5,
  'Branch row lost its aligned colored display columns'
)

local exact_search_command = repository.commands.search_commits('#3452', {
  kind = 'file',
  location = { relative_path = 'src/master_service.cpp', root = '/work/repository' },
})
assert(
  vim.tbl_contains(exact_search_command, '--grep=#3452([^[:digit:]]|$)')
    and vim.tbl_contains(exact_search_command, '--max-count=50')
    and vim.tbl_contains(exact_search_command, '--branches')
    and vim.tbl_contains(exact_search_command, '--remotes')
    and vim.tbl_contains(exact_search_command, '--source')
    and vim.tbl_contains(exact_search_command, '--follow')
    and exact_search_command[#exact_search_command] == 'src/master_service.cpp',
  'Exact-number search command lost its numeric boundary, cap, or history scope'
)
local parsed_search_commits = repository.parse_commit_search(table.concat({
  table.concat({
    string.rep('a', 40),
    'aaaaaaaa',
    '2026-08-24',
    'A',
    'origin/topic',
    'Fix cache accounting (#3452)',
  }, '\t'),
  table.concat({
    string.rep('b', 40),
    'noise',
    '2026-08-25',
    'B',
    'main',
    '[Store] Shrink metadata maps after eviction cycles (#3576)',
  }, '\t'),
  'diff --git a/src/cache.cpp b/src/cache.cpp',
  '+body patch line mentioning #3452',
}, '\n'), '3452')
assert(
  #parsed_search_commits == 1
    and parsed_search_commits[1].hash == string.rep('a', 40)
    and parsed_search_commits[1].source_ref == 'origin/topic'
    and parsed_search_commits[1].source == 'LOCAL',
  'Subject filtering retained the Mooncake #3576 body-only noise for #3452'
)
local commit_record = git_ui.commit_record(parsed_search_commits[1])
assert(
  commit_record.display_text:match('LOCAL') and commit_record.display_text:match('#3452'),
  'Git-search commit row lost its source tag or subject'
)
local issue_record = git_ui.issue_record({
  author = 'maintainer',
  html_url = 'https://github.com/example/repository/issues/3452',
  kind = 'Issue',
  labels = {},
  number = 3452,
  title = 'Reduce RSS after eviction',
})
assert(
  issue_record.display_text:match('REMOTE') and issue_record.display_text:match('#3452'),
  'Git-search issue row lost its source tag or number'
)
local remote_error_record = git_ui.remote_error_record('GitHub', 'API rate limit exceeded')
local remote_error_preview = git_ui.remote_error_preview(remote_error_record)
assert(
  remote_error_record.display_text:match('REMOTE')
    and remote_error_record.display_text:match('ERROR')
    and table.concat(remote_error_preview.lines, '\n'):match('API rate limit exceeded'),
  'Remote provider failure was not exposed as a renderable search result'
)

local preview_output = table.concat({
  string.char(30) .. table.concat({
    string.rep('c', 40),
    'cccccccc',
    '2026-09-01',
    'Maintainer',
    'Align Git preview columns',
  }, string.char(31)),
  '',
  'M\tlua/config/git/search.lua',
  'R100\told.lua\tnew.lua',
}, '\n')
local preview_commits = repository.parse_commit_preview(preview_output)
assert(
  #preview_commits == 1
    and preview_commits[1].subject == 'Align Git preview columns'
    and #preview_commits[1].files == 2
    and preview_commits[1].files[2].original_path == 'old.lua',
  'Structured Git preview parser lost commit metadata or changed files'
)
local rendered_branch = git_ui.branch_preview(branches[1], preview_commits)
assert(
  rendered_branch.lines[1]:match('LOCAL%s+BRANCH%s+main')
    and rendered_branch.lines[5]:match('cccccccc%s+2026%-09%-01%s+Align Git preview columns')
    and table.concat(rendered_branch.lines, '\n'):match('old.lua → new.lua')
    and rendered_branch.commit_by_line[5] == string.rep('c', 40)
    and #rendered_branch.highlights > 0,
  'Branch preview did not render aligned, colored commit and file levels'
)
local rendered_commit = git_ui.commit_preview(commit_record, preview_commits[1])
assert(
  table.concat(rendered_commit.lines, '\n'):match('CHANGED FILES%s+2')
    and table.concat(rendered_commit.lines, '\n'):match('Align Git preview columns'),
  'Commit preview did not reduce raw Git output to changed-file rows'
)

local picker_options = git_ui.picker_options('/work/repository')
assert(picker_options.cwd == '/work/repository', 'Branch picker lost its repository root')
assert(
  picker_options.layout_config.horizontal.preview_width == git_ui.focus_layout.results_width,
  'Branch picker did not use the shared compact preview width'
)

assert(
  repository.concise_error({ code = 2, stderr = 'first\nsecond' }) == 'first second',
  'Git process errors were not condensed to one readable line'
)

assert(
  vim.deep_equal(repository.commands.resolve_commit('dcedb0b'), {
    'git', 'rev-parse', '--verify', '--end-of-options', 'dcedb0b^{commit}',
  }),
  'Commit overview did not verify the requested object as a commit'
)
assert(
  vim.deep_equal(repository.commands.detach_commit('resolved'), {
    'git', 'switch', '--detach', 'resolved',
  }),
  'Commit overview did not use an explicit detached switch'
)
assert(
  vim.deep_equal(repository.commands.attach_branch('main'), { 'git', 'switch', 'main' }),
  'A detached local branch tip did not use explicit branch attachment'
)
assert(
  vim.deep_equal(repository.commands.commit_is_ancestor('resolved', 'refs/heads/main'), {
    'git', 'merge-base', '--is-ancestor', 'resolved', 'refs/heads/main',
  }),
  'Detached-commit retention did not use an explicit ancestry check'
)
assert(
  repository.parse_commit_source('refs/remotes/origin/topic\n') == 'REMOTE'
    and repository.parse_commit_source('refs/heads/main\nrefs/remotes/origin/main\n') == 'LOCAL',
  'Commit source did not prioritize local-branch reachability over remote refs'
)
local remote_commit_location = repository.parse_commit_location(
  'refs/remotes/origin/topic\n'
)
local local_commit_location = repository.parse_commit_location(
  'refs/remotes/origin/main\nrefs/heads/main\n'
)
assert(
  remote_commit_location.source == 'REMOTE'
    and remote_commit_location.branch_name == 'origin/topic'
    and local_commit_location.source == 'LOCAL'
    and local_commit_location.branch_name == 'main',
  'Commit location did not retain the best containing branch for panel rendering'
)
local clean_head_state = repository.parse_head_state(table.concat({
  '# branch.oid resolved',
  '# branch.head main',
}, '\n'))
assert(
  clean_head_state.commit == 'resolved'
    and clean_head_state.branch_name == 'main'
    and not clean_head_state.detached
    and not clean_head_state.dirty,
  'Clean attached HEAD state was parsed incorrectly'
)
local dirty_detached_state = repository.parse_head_state(table.concat({
  '# branch.oid resolved',
  '# branch.head (detached)',
  '? scratch.txt',
}, '\n'))
assert(
  dirty_detached_state.detached
    and dirty_detached_state.branch_name == nil
    and dirty_detached_state.dirty,
  'Detached or dirty Git workspace state retained a synthetic branch name'
)

local original_git_module = package.loaded['config.git']
local original_diffview_module = package.loaded['config.git.diffview']
local original_search_module = package.loaded['config.git.search']
local original_repository_start = repository.start
local started_commands = {}
local overview_close_calls = 0
local overview_options
local replacement_call
local direct_search_call
local deferred_git_action
local defer_git_search = false
local focus_history_result = false
local focus_history_calls = 0
local anchor_logs = {}
local opened_history_view = { name = 'direct repository history' }
local head_status_output = table.concat({
  '# branch.oid previous',
  '# branch.head main',
}, '\n')
local resolved_commit = string.rep('a', 40)
local ancestor_exit_code = 0
local commit_source_output = 'refs/remotes/origin/topic\n'
package.loaded['config.git.diffview'] = {
  close = function()
    overview_close_calls = overview_close_calls + 1
  end,
  open_file_history = function(options)
    overview_options = options
    if options.render_ready_callback then
      options.render_ready_callback(opened_history_view, true, 'test render ready')
    end
    return opened_history_view
  end,
  is_active = function()
    return false
  end,
  defer_until_settled = function(action_name, action_callback)
    if not defer_git_search then
      return false
    end
    deferred_git_action = {
      callback = action_callback,
      name = action_name,
    }
    return true
  end,
  focus_history_commit = function(parent_view)
    focus_history_calls = focus_history_calls + 1
    if focus_history_result and parent_view.git_render_ready_callback then
      local render_callback = parent_view.git_render_ready_callback
      parent_view.git_render_ready_callback = nil
      render_callback(parent_view, true, 'test focus ready')
    end
    return focus_history_result
  end,
  replace_file_history = function(parent_view, options)
    replacement_call = { options = options, parent_view = parent_view }
    if options.render_ready_callback then
      options.render_ready_callback(parent_view, true, 'test replacement ready')
    end
    return true
  end,
  adapt_history_footer = function() end,
  log_anchor = function(message, level)
    anchor_logs[#anchor_logs + 1] = { level = level, message = message }
  end,
}
package.loaded['config.git.search'] = {
  open = function(root, history_options, parent_view)
    direct_search_call = {
      history_options = history_options,
      parent_view = parent_view,
      root = root,
    }
    return true
  end,
}
repository.start = function(command, root, callback)
  started_commands[#started_commands + 1] = { command = vim.deepcopy(command), root = root }
  if command[2] == 'rev-parse' then
    callback({ code = 0, stderr = '', stdout = resolved_commit .. '\n' })
  elseif command[2] == 'status' then
    callback({ code = 0, stderr = '', stdout = head_status_output })
  elseif command[2] == 'for-each-ref' then
    callback({ code = 0, stderr = '', stdout = commit_source_output })
  elseif command[2] == 'merge-base' then
    callback({ code = ancestor_exit_code, stderr = '', stdout = '' })
  elseif command[2] == 'switch' then
    callback({ code = 0, stderr = '', stdout = '' })
  else
    error('Unexpected Git command in detach test: ' .. table.concat(command, ' '))
  end
  return function() end
end
package.loaded['config.git'] = nil
local git = require('config.git')
assert(
  type(git.on) == 'function'
    and git.supports_event('ready')
    and not git.supports_event('diffview_file_open_post'),
  'Git subsystem did not expose a stable renderer-independent event port'
)
defer_git_search = true
assert(git.search_repository())
assert(
  deferred_git_action
    and deferred_git_action.name == 'repository_search'
    and direct_search_call == nil,
  'Repository search was dropped instead of waiting for Git teardown'
)
defer_git_search = false
deferred_git_action.callback()
assert(direct_search_call, 'Deferred repository search did not resume after Git teardown')
direct_search_call = nil
assert(git.search_repository())
assert(
  direct_search_call
    and direct_search_call.root == vim.fs.normalize(vim.uv.cwd())
    and direct_search_call.history_options.kind == 'repository'
    and direct_search_call.history_options.checked_out_branch == 'main'
    and direct_search_call.history_options.branch_name == 'main'
    and direct_search_call.history_options.history_ref == 'refs/heads/main'
    and direct_search_call.history_options.branch_tip_commit == 'previous'
    and direct_search_call.parent_view == opened_history_view,
  'Direct Git search did not mount repository history beneath its picker'
)

started_commands = {}
direct_search_call = nil
head_status_output = table.concat({
  '# branch.oid ' .. resolved_commit,
  '# branch.head (detached)',
  '? scratch.txt',
}, '\n')
assert(git.search_repository())
assert(
  #started_commands == 3
    and started_commands[1].command[2] == 'status'
    and started_commands[2].command[2] == 'for-each-ref'
    and started_commands[3].command[2] == 'rev-parse'
    and direct_search_call
    and direct_search_call.history_options.branch_name == 'origin/topic'
    and direct_search_call.history_options.history_ref == 'refs/remotes/origin/topic'
    and direct_search_call.history_options.selected_commit == resolved_commit
    and direct_search_call.history_options.detached_head_commit == resolved_commit
    and direct_search_call.history_options.anchor_plan.branch_ref
      == 'refs/remotes/origin/topic'
    and direct_search_call.history_options.anchor_plan.branch_tip_commit == resolved_commit
    and direct_search_call.history_options.unbounded,
  'Dirty detached Git entry did not use a containing local or remote-tracking branch history'
)

started_commands = {}
head_status_output = table.concat({
  '# branch.oid previous',
  '# branch.head main',
}, '\n')
assert(git.detach_commit_overview('/work/repository', 'aaaaaaa'))
assert(
  #started_commands == 3
    and started_commands[3].command[2] == 'switch'
    and overview_close_calls == 1
    and overview_options.selected_commit == resolved_commit
    and overview_options.history_ref == resolved_commit
    and overview_options.detached_head_commit == resolved_commit
    and overview_options.unbounded
    and overview_options.source == 'LOCAL',
  'Context-free commit overview searched branches instead of using the exact commit anchor'
)
assert(
  #anchor_logs >= 5
    and anchor_logs[1].message:match('requested')
    and anchor_logs[#anchor_logs].message:match('review render ready'),
  'Anchor move did not record its staged timing trace in the Diffview log'
)

started_commands = {}
head_status_output = table.concat({
  '# branch.oid ' .. resolved_commit,
  '# branch.head (detached)',
}, '\n')
assert(git.detach_commit_overview('/work/repository', 'aaaaaaa'))
assert(
  #started_commands == 2
    and overview_close_calls == 2
    and overview_options.detached_head_commit == resolved_commit,
  'An already-detached commit performed a duplicate switch'
)

started_commands = {}
head_status_output = table.concat({
  '# branch.oid ' .. resolved_commit,
  '# branch.head main',
}, '\n')
assert(git.detach_commit_overview('/work/repository', 'aaaaaaa'))
assert(
  #started_commands == 2
    and overview_close_calls == 3
    and overview_options.detached_head_commit == nil,
  'A commit already checked out as branch HEAD was detached unnecessarily'
)

started_commands = {}
head_status_output = table.concat({
  '# branch.oid previous',
  '# branch.head main',
  '? scratch.txt',
}, '\n')
assert(git.detach_commit_overview('/work/repository', 'aaaaaaa'))
assert(
  #started_commands == 2 and overview_close_calls == 3,
  'Dirty Git workspace was not rejected before detached checkout'
)

started_commands = {}
head_status_output = table.concat({
  '# branch.oid previous',
  '# branch.head main',
}, '\n')
local parent_view = { name = 'persistent Git view' }
focus_history_result = true
assert(git.detach_commit_overview('/work/repository', 'aaaaaaa', parent_view, {
  anchor_plan = {
    branch_name = 'origin/chosen-topic',
    branch_ref = 'refs/remotes/origin/chosen-topic',
    branch_tip_commit = string.rep('b', 40),
    source = 'REMOTE',
  },
  branch_name = 'origin/chosen-topic',
  source = 'REMOTE',
}))
assert(
  #started_commands == 3
    and started_commands[1].command[2] == 'rev-parse'
    and started_commands[2].command[2] == 'status'
    and started_commands[3].command[2] == 'switch'
    and overview_close_calls == 3
    and focus_history_calls == 0
    and replacement_call
    and replacement_call.parent_view == parent_view
    and replacement_call.options.selected_commit == resolved_commit
    and replacement_call.options.history_ref == 'refs/remotes/origin/chosen-topic'
    and replacement_call.options.unbounded
    and replacement_call.options.branch_name == 'origin/chosen-topic'
    and replacement_call.options.branch_tip_commit == string.rep('b', 40)
    and replacement_call.options.checked_out_branch == nil
    and replacement_call.options.detached_head_commit == resolved_commit
    and replacement_call.options.source == 'REMOTE',
  'In-mode commit detach reused stale branch decorations instead of refreshing history'
)

started_commands = {}
replacement_call = nil
commit_source_output = 'refs/heads/main\n'
head_status_output = table.concat({
  '# branch.oid ' .. resolved_commit,
  '# branch.head (detached)',
}, '\n')
assert(git.detach_commit_overview('/work/repository', 'aaaaaaa', parent_view, {
  anchor_plan = {
    branch_name = 'main',
    branch_ref = 'refs/heads/main',
    branch_tip_commit = resolved_commit,
    source = 'LOCAL',
  },
  branch_name = 'main',
  source = 'LOCAL',
}))
assert(
  #started_commands == 4
    and started_commands[3].command[2] == 'rev-parse'
    and started_commands[4].command[2] == 'switch'
    and vim.deep_equal(started_commands[4].command, { 'git', 'switch', 'main' })
    and replacement_call
    and replacement_call.options.branch_name == 'main'
    and replacement_call.options.history_ref == 'refs/heads/main'
    and replacement_call.options.checked_out_branch == 'main'
    and replacement_call.options.detached_head_commit == nil,
  'Detached HEAD at a local branch tip was not reattached by the explicit anchor action'
)

started_commands = {}
replacement_call = nil
focus_history_result = false
commit_source_output = 'refs/remotes/origin/topic\n'
head_status_output = table.concat({
  '# branch.oid ' .. resolved_commit,
  '# branch.head (detached)',
  '? scratch.txt',
}, '\n')
git.review_branch('/work/repository', branches[1], parent_view)
assert(
  #started_commands == 2
    and started_commands[1].command[2] == 'status'
    and started_commands[2].command[2] == 'merge-base'
    and overview_close_calls == 3
    and replacement_call
    and replacement_call.parent_view == parent_view
    and replacement_call.options.kind == 'repository'
    and replacement_call.options.anchor_plan.branch_ref == 'refs/heads/main'
    and replacement_call.options.anchor_plan.branch_tip_commit == string.rep('1', 40)
    and replacement_call.options.location.root == '/work/repository'
    and replacement_call.options.branch_name == 'main'
    and replacement_call.options.history_ref == 'refs/heads/main'
    and replacement_call.options.detached_head_commit == resolved_commit
    and replacement_call.options.selected_commit == resolved_commit
    and replacement_call.options.review_only
    and replacement_call.options.unbounded,
  'Dirty read-only branch review did not retain a contained detached HEAD commit'
)

started_commands = {}
replacement_call = nil
ancestor_exit_code = 1
git.review_branch('/work/repository', branches[3], parent_view)
assert(
  #started_commands == 2
    and not vim.tbl_contains(started_commands[1].command, 'switch')
    and not vim.tbl_contains(started_commands[2].command, 'switch')
    and replacement_call
    and replacement_call.options.history_ref == 'refs/remotes/origin/feature/topic'
    and replacement_call.options.source == 'REMOTE'
    and replacement_call.options.detached_head_commit == resolved_commit
    and replacement_call.options.selected_commit == nil
    and not replacement_call.options.unbounded,
  'Branch review changed HEAD or retained a detached commit outside the selected ref'
)
repository.start = original_repository_start
package.loaded['config.git.diffview'] = original_diffview_module
package.loaded['config.git.search'] = original_search_module
package.loaded['config.git'] = original_git_module
