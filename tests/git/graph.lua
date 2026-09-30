local repository = require('config.git.repository')

local command = repository.commands.graph_history(600)
assert(vim.tbl_contains(command, '--graph') and not vim.tbl_contains(command, '--all'))
assert(vim.tbl_contains(command, '--max-count=600') and command[#command] == 'HEAD')
assert(repository.commands.graph_history(600, 'refs/remotes/origin/topic')[#command]
  == 'refs/remotes/origin/topic')

local record = string.char(30)
local field = string.char(31)
local merge = string.rep('a', 40)
local first = string.rep('b', 40)
local second = string.rep('c', 40)
local function entry(prefix, hash, parents, subject, refs)
  return prefix .. record .. table.concat({ hash, parents, subject, refs or '' }, field)
end
local output = table.concat({
  entry('*   ', merge, first .. ' ' .. second, 'Merge topic', 'HEAD -> main'),
  '|\\  ',
  entry('| * ', second, first, 'feat: Topic work', 'origin/topic'),
  '|/  ',
  entry('* ', first, '', 'fix: Base commit'),
}, '\n')
local rows = repository.parse_graph_history(output)
assert(#rows == 5 and rows[1].commit.hash == merge
  and #rows[1].commit.parents == 2)
assert(rows[3].commit.hash == second and rows[5].commit.hash == first)
assert(rows[1].graph:find('◆', 1, true) and rows[2].graph:find('╲', 1, true))
assert(rows[3].graph:find('●', 1, true) and rows[4].graph:find('╱', 1, true))
assert(rows[1].commit.refs == 'HEAD -> main')

local formatted = require('config.git.graph').format_history(rows)
local function badge_text(formatted_rows, row_number)
  for _, badge in ipairs(formatted_rows.badges) do
    if badge.row == row_number - 1 then
      local parts = {}
      for _, chunk in ipairs(badge.chunks) do parts[#parts + 1] = chunk[1] end
      return table.concat(parts)
    end
  end
  return ''
end
assert(vim.trim(badge_text(formatted, 1)) == '[HEAD]'
  and vim.trim(badge_text(formatted, 3)) == '[origin/topic]'
  and formatted.lines[1]:find('Merge topic', 1, true)
  and formatted.lines[3]:find('feat: Topic work', 1, true)
  and not formatted.lines[1]:find('[HEAD]', 1, true),
  'Head and branch badges did not remain separate from commit titles')
local forked = require('config.git.graph').format_history(rows, nil, {
  [merge] = { 'feature' },
})
assert(vim.trim(badge_text(forked, 1)) == '[HEAD] [feature↗]'
  and forked.lines[1] == formatted.lines[1],
  'Right-aligned fork badges changed the commit title column')
for _, row in ipairs({ 1, 3, 5 }) do
  local line = formatted.lines[row]
  local node = row == 1 and '◆' or '●'
  assert(line:find(node .. ' ' .. rows[row].commit.hash:sub(1, 8), 1, true),
    'Hash is not adjacent to its graph node')
end
for _, row in ipairs({ 1, 3, 5 }) do
  local commit = rows[row].commit
  assert(formatted.lines[row]:find(commit.hash:sub(1, 8) .. ' ' .. commit.subject, 1, true),
    'Commit subject gained horizontal alignment padding')
end
assert(#formatted.lines == 5, 'Existing merge connectors gained redundant spacer rows')

local adjacent_rows = repository.parse_graph_history(table.concat({
  entry('* ', merge, second, 'refactor(core): Simplify history', 'HEAD -> main'),
  entry('* ', second, first, 'fix: Keep selection', 'topic'),
  entry('* ', first, '', 'Initial commit'),
}, '\n'))
local spaced = require('config.git.graph').format_history(adjacent_rows)
assert(#spaced.lines == 3, 'Adjacent commits gained full-height spacer rows')
assert(spaced.commits[1].hash == merge and spaced.commits[2].hash == second
  and spaced.commits[3].hash == first, 'Compact rows changed selectable commit identities')
assert(vim.trim(badge_text(spaced, 1)) == '[HEAD]'
  and vim.trim(badge_text(spaced, 2)) == '[topic]',
  'Badges did not follow their commits in the compact list')
local parallel_rows = repository.parse_graph_history(table.concat({
  entry('| * ', second, first, 'feat: Parallel work'),
  entry('| * ', first, '', 'Initial parallel commit'),
}, '\n'))
local parallel = require('config.git.graph').format_history(parallel_rows)
assert(#parallel.lines == 2 and vim.startswith(parallel.lines[2], '│ ●'),
  'Compact rows broke parallel topology lanes')
local groups = {}
for _, highlight in ipairs(formatted.highlights) do
  groups[highlight.group] = true
end
for _, badge in ipairs(formatted.badges) do
  for _, chunk in ipairs(badge.chunks) do groups[chunk[2]] = true end
end
assert(groups.DiagnosticInfo and groups.DiagnosticWarn and groups.DiagnosticOk
  and groups.DiagnosticError and groups.Directory and groups.DiagnosticHint,
  'Graph roles lost their uniform-theme highlights')

local long_rows = repository.parse_graph_history(entry('* ', merge, first,
  'feat: a long subject that needs room for analysis', 'origin/development-branch'))
local compact = require('config.git.graph').format_history(long_rows)
assert(compact.lines[1]:find(long_rows[1].commit.subject, 1, true)
  and vim.trim(badge_text(compact, 1)) == '[origin/development-branch]',
  'Long branch refs were abbreviated')
local long_fork = require('config.git.graph').format_history(long_rows, merge, {
  [merge] = { 'feature/long-branch-name' },
})
assert(vim.trim(badge_text(long_fork, 1)) == '[HEAD] [feature/long-branch-name↗]',
  'Fork badges lost their full branch path')

local standard_rows = repository.parse_graph_history(entry('* ', merge, first,
  'security(auth)!: Reject stale token'))
local standard = require('config.git.graph').format_history(standard_rows)
assert(standard.lines[1]:find('security(auth)!: Reject stale token', 1, true),
  'Conventional Commit scope and breaking marker were not preserved')
local standard_groups = {}
for _, highlight in ipairs(standard.highlights) do
  standard_groups[highlight.group] = true
end
assert(standard_groups.Identifier, 'Unknown Conventional Commit type lost theme highlighting')

local function subject_highlights(subject)
  local tagged_rows = repository.parse_graph_history(entry('* ', merge, first, subject))
  local tagged = require('config.git.graph').format_history(tagged_rows)
  local tags = {}
  for _, highlight in ipairs(tagged.highlights) do
    if highlight.priority == 150 then
      tags[#tags + 1] = {
        text = tagged.lines[1]:sub(highlight.start_col + 1, highlight.end_col),
        group = highlight.group,
      }
    end
  end
  return tagged, tags
end
local bracket_subject = '[Bugfix][Store] Return failure from PushOffloading'
local tagged, tags = subject_highlights(bracket_subject)
assert(tagged.lines[1]:find(bracket_subject, 1, true)
  and vim.deep_equal(tags, {
    { text = '[Bugfix]', group = 'DiagnosticError' },
    { text = '[Store]', group = 'Identifier' },
  }), 'Bracket type and scope tags did not retain their text and theme colors')
local _, mixed_tags = subject_highlights('[BUGFIX] [存储] fix(io): Return failure')
assert(vim.deep_equal(mixed_tags, {
  { text = '[BUGFIX]', group = 'DiagnosticError' },
  { text = '[存储]', group = 'Identifier' },
  { text = 'fix(io):', group = 'DiagnosticError' },
}), 'Spaced, mixed-case or Unicode tags shifted subject highlight boundaries')
local _, ordinary_tags = subject_highlights('Return [Store] failure')
local _, incomplete_tags = subject_highlights('[Bugfix Return failure')
assert(#ordinary_tags == 0 and #incomplete_tags == 0,
  'Ordinary title text or an incomplete bracket was treated as a prefix tag')

local branches = {
  { current = true, is_remote = false, short_name = 'main', subject = 'Current work' },
  { current = false, is_remote = true,
    short_name = 'origin/very-long-development-branch', subject = 'Remote work' },
}
local branch_rows = require('config.git.graph').format_branches(branches, 38)
local first_subject = assert(branch_rows.lines[1]:find('Current work', 1, true))
local second_subject = assert(branch_rows.lines[2]:find('Remote work', 1, true))
assert(vim.fn.strdisplaywidth(branch_rows.lines[1]:sub(1, first_subject - 1))
  == vim.fn.strdisplaywidth(branch_rows.lines[2]:sub(1, second_subject - 1))
  and branch_rows.lines[2]:find('o/very', 1, true)
  and branch_rows.lines[2]:find('…', 1, true),
  'Branch names do not have a compact aligned column')

local message_command = repository.commands.commit_message(merge)
local files_command = repository.commands.commit_files(merge)
assert(message_command[#message_command] == merge)
assert(vim.tbl_contains(files_command, '--first-parent'))
assert(vim.tbl_contains(files_command, '--name-status'))

local worktree = repository.parse_worktree_state(table.concat({
  '# branch.oid ' .. merge, '# branch.head main',
  '1 .M N... 100644 100644 100644 abc def file with spaces.txt',
  '2 R. N... 100644 100644 100644 abc def R100 new name.txt', 'old name.txt',
  '? line\nbreak.txt',
  'u UU N... 100644 100644 100644 100644 abc def ghi conflict.txt', '',
}, '\0'))
assert(worktree.commit == merge and worktree.dirty and #worktree.files == 4)
assert(worktree.files[1].path == 'file with spaces.txt'
  and worktree.files[2].original_path == 'old name.txt'
  and worktree.files[3].path == 'line\nbreak.txt'
  and worktree.files[4].status == 'UU' and worktree.files[4].path == 'conflict.txt',
  'Worktree status lost names, rename sources, or conflict status')
local with_worktree = require('config.git.graph').with_worktree(rows, worktree)
assert(#with_worktree == #rows + 1 and with_worktree[1].commit.kind == 'worktree'
  and with_worktree[2].commit.hash == merge and #rows == 5,
  'Working tree did not attach directly above HEAD without mutating the history')
local worktree_render = require('config.git.graph').format_history(with_worktree, merge)
assert(badge_text(worktree_render, 1):find('[WORKTREE]', 1, true)
  and badge_text(worktree_render, 2):find('[HEAD]', 1, true))
assert(#require('config.git.graph').with_worktree(rows, { dirty = false, commit = merge }) == #rows)
assert(#require('config.git.graph').with_worktree(rows, { dirty = true, commit = 'absent' }) == #rows)

print('Git graph parser tests passed')
