local original_dashboard = package.loaded['config.dashboard']
package.loaded['config.dashboard'] = nil

local dashboard = require('config.dashboard')
local temporary_root = vim.fn.tempname()
local first_root = vim.fs.joinpath(temporary_root, 'alpha')
local second_root = vim.fs.joinpath(temporary_root, 'beta')
local first_file = vim.fs.joinpath(first_root, 'src', 'main.py')
local second_file = vim.fs.joinpath(first_root, 'README.md')
local third_file = vim.fs.joinpath(second_root, 'lua', 'init.lua')
local center_root = vim.fs.joinpath(temporary_root, 'gamma')
local center_file = vim.fs.joinpath(center_root, 'doc', 'guide.md')

vim.fn.mkdir(vim.fs.joinpath(first_root, '.git'), 'p')
vim.fn.mkdir(vim.fs.dirname(first_file), 'p')
vim.fn.mkdir(vim.fs.joinpath(second_root, '.git'), 'p')
vim.fn.mkdir(vim.fs.dirname(third_file), 'p')
vim.fn.mkdir(vim.fs.joinpath(center_root, '.git'), 'p')
vim.fn.mkdir(vim.fs.dirname(center_file), 'p')
vim.fn.writefile({ 'print("alpha")' }, first_file)
vim.fn.writefile({ '# Alpha' }, second_file)
vim.fn.writefile({ 'return {}' }, third_file)
vim.fn.writefile({ '# Guide' }, center_file)
vim.fn.writefile({
  '[remote "origin"]',
  '  url = git@github.com:example/alpha.git',
}, vim.fs.joinpath(first_root, '.git', 'config'))
vim.fn.writefile({
  '[remote "origin"]',
  '  url = https://gitlab.com/example/beta.git',
}, vim.fs.joinpath(second_root, '.git', 'config'))

local projects = dashboard.collect({ first_file, second_file, third_file, first_file }, first_root)
assert(#projects == 2, 'dashboard did not group recent files by project')
assert(projects.current_index == 1, 'launch-directory project was not initially selected')
assert(projects[1].root == first_root, 'dashboard changed recent-project order')
assert(projects[1].icon == '', 'dashboard omitted the GitHub project icon')
assert(projects[2].icon == '', 'dashboard omitted the GitLab project icon')
assert(#projects[1].files == 2, 'dashboard retained duplicate recent files')
assert(
  projects[1].files[1].relative_path == 'src/main.py',
  'dashboard file path was not relative to its project'
)

local prioritized_projects = dashboard.collect({ first_file, third_file, center_file }, center_root)
assert(prioritized_projects.current_index == 1, 'launch-directory project was not selected first')
assert(
  prioritized_projects[1].root == center_root,
  'dashboard did not place the launch-directory project at the left edge'
)

local options = dashboard.options()
assert(options.theme == 'project', 'dashboard did not select the compact project theme')

local original_buffer = vim.api.nvim_get_current_buf()
local dashboard_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, dashboard_buffer)
local dashboard_window = vim.api.nvim_get_current_win()
local original_global_number = vim.go.number
local original_global_relativenumber = vim.go.relativenumber
local original_global_signcolumn = vim.go.signcolumn
vim.go.number = true
vim.go.relativenumber = true
vim.go.signcolumn = 'auto'
dashboard.attach(dashboard_buffer, dashboard_window, projects, {
  root = first_root,
  file_path = first_file,
})
assert(
  vim.wait(1000, function()
    return not vim.bo[dashboard_buffer].modifiable
  end),
  'dashboard did not complete its scheduled initial render'
)
assert(not vim.wo[dashboard_window].number, 'dashboard retained the code line-number gutter')
assert(not vim.wo[dashboard_window].relativenumber, 'dashboard retained relative line numbers')
assert(vim.wo[dashboard_window].signcolumn == 'no', 'dashboard retained its sign gutter')
local rendered_lines = vim.api.nvim_buf_get_lines(dashboard_buffer, 0, -1, false)
local rendered_text = table.concat(rendered_lines, '\n')
assert(rendered_text:find('', 1, true), 'dashboard omitted the compact title icon')
assert(
  rendered_text:find('███╗   ██╗', 1, true),
  'dashboard did not render the enlarged terminal icon'
)
assert(
  rendered_lines[dashboard.top_padding + 1]
    and rendered_lines[dashboard.top_padding + 1]:find('███╗   ██╗', 1, true),
  'dashboard icon did not keep its fixed vertical anchor'
)
assert(
  rendered_lines[dashboard.top_padding + 6] == '',
  'dashboard did not keep a margin between its icon and title'
)
assert(rendered_text:find('  PROJECT DECK', 1, true), 'dashboard omitted its fixed title')
local title_line = vim.iter(rendered_lines):find(function(line)
  return line:find('PROJECT DECK', 1, true) ~= nil
end)
assert(title_line, 'dashboard omitted its title line')
assert(
  not title_line:find('alpha', 1, true),
  'dashboard title retained the project context'
)
local project_footer_index
local path_footer_index
local project_footer_line
local path_footer_line
for line_index, line in ipairs(rendered_lines) do
  if line:find('  alpha', 1, true) then
    project_footer_index = line_index
    project_footer_line = line
  elseif line:find('󰉋', 1, true) then
    path_footer_index = line_index
    path_footer_line = line
  end
end
assert(project_footer_line, 'dashboard footer omitted the current project')
assert(path_footer_line, 'dashboard footer omitted the project-path icon')
assert(
  path_footer_line:find(vim.fn.strcharpart(first_root, 0, 5), 1, true),
  'dashboard footer omitted the stable project-root path'
)
assert(
  vim.fn.strdisplaywidth(path_footer_line) <= vim.api.nvim_win_get_width(dashboard_window),
  'dashboard project path overflowed the right edge of its window'
)
assert(dashboard.file_limit == 10, 'dashboard recent-file list is not usefully bounded')
assert(dashboard.project_limit == 5, 'dashboard project drawer exceeded its visual limit')
local footer_padding = dashboard.footer_padding(20, 40, 4)
assert(
  20 + dashboard.top_padding + footer_padding == 40 - dashboard.bottom_padding - 4,
  'dashboard footer did not anchor to its fixed bottom row'
)
local drawer_is_horizontal = vim.iter(rendered_lines):any(function(line)
  return line:find('alpha', 1, true) and line:find('beta', 1, true)
end)
assert(drawer_is_horizontal, 'recent projects were not arranged horizontally')
local initial_drawer_line = vim.iter(rendered_lines):find(function(line)
  return line:find('alpha', 1, true) and line:find('beta', 1, true)
end)
local relative_file_line = vim.iter(rendered_lines):find(function(line)
  return line:find('src/main.py', 1, true) ~= nil
end)
local files_are_visible = relative_file_line ~= nil
local relative_file_index
for line_index, line in ipairs(rendered_lines) do
  if line == relative_file_line then
    relative_file_index = line_index
    break
  end
end
if relative_file_line then
  assert(
    relative_file_index and project_footer_index and path_footer_index
      and relative_file_index < project_footer_index
      and project_footer_index < path_footer_index,
    'dashboard project context was not placed below the recent-file list'
  )
  assert(
    not relative_file_line:find(first_root, 1, true),
    'dashboard repeated the full project root on a recent-file row'
  )
else
  assert(
    #rendered_lines <= vim.api.nvim_win_get_height(dashboard_window),
    'dashboard overflowed a short window instead of clipping recent files'
  )
end

local function buffer_mapping(lhs)
  return vim.api.nvim_buf_call(dashboard_buffer, function()
    return vim.fn.maparg(lhs, 'n', false, true)
  end)
end

local next_project = buffer_mapping('l')
local next_file = buffer_mapping('j')
local open_selection = buffer_mapping('<CR>')
local close = buffer_mapping('q')
assert(type(next_project.callback) == 'function', 'dashboard has no project drawer navigation')
assert(type(next_file.callback) == 'function', 'dashboard has no recent-file navigation')
assert(type(open_selection.callback) == 'function', 'dashboard has no direct open action')
assert(type(close.callback) == 'function', 'dashboard has no close action')

next_project.callback()
local next_project_lines = vim.api.nvim_buf_get_lines(dashboard_buffer, 0, -1, false)
rendered_text = table.concat(next_project_lines, '\n')
if files_are_visible then
  assert(rendered_text:find('lua/init.lua', 1, true), 'project drawer did not update recent files')
end
local updated_drawer_line = vim.iter(next_project_lines):find(function(line)
  return line:find('alpha', 1, true) and line:find('beta', 1, true)
end)
assert(updated_drawer_line == initial_drawer_line, 'project navigation rolled the drawer positions')

next_file.callback()
local original_command = vim.cmd
local opened_commands = {}
vim.cmd = function(command)
  opened_commands[#opened_commands + 1] = command
end
open_selection.callback()
assert(
  opened_commands[#opened_commands] == 'edit ' .. vim.fn.fnameescape(third_file),
  'dashboard recent file did not open directly'
)

local activated_root = dashboard.activate_project(first_root)
assert(activated_root == first_root, 'project action activated the wrong root')
assert(
  opened_commands[#opened_commands] == 'lcd ' .. vim.fn.fnameescape(first_root),
  'project action did not update the dashboard working directory'
)

dashboard.open()
vim.cmd = original_command
assert(opened_commands[#opened_commands] == 'Dashboard', '<Space>h target did not open dashboard')

local code_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_win_set_buf(dashboard_window, code_buffer)
assert(vim.wo[dashboard_window].number, 'dashboard leaked its disabled line numbers into code')
assert(
  vim.wo[dashboard_window].relativenumber,
  'dashboard leaked its disabled relative line numbers into code'
)
assert(
  vim.wo[dashboard_window].signcolumn == 'auto',
  'dashboard leaked its disabled sign gutter into code'
)
assert(vim.api.nvim_buf_is_valid(original_buffer), 'dashboard test lost its original buffer')
vim.api.nvim_win_set_buf(dashboard_window, original_buffer)
vim.api.nvim_buf_delete(code_buffer, { force = true })
vim.api.nvim_set_current_buf(original_buffer)
vim.go.number = original_global_number
vim.go.relativenumber = original_global_relativenumber
vim.go.signcolumn = original_global_signcolumn
vim.fn.delete(temporary_root, 'rf')
package.loaded['config.dashboard'] = original_dashboard
