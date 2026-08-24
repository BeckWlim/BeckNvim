local M = {}

local function escaped_pcre_literal(text)
  return text:gsub('\\E', '\\E\\\\E\\Q')
end

function M.command(prompt, root)
  local literal_prompt = escaped_pcre_literal(prompt)
  local symbol_pattern = [[^\s*(?:(?:async\s+)?def|class)\s+\w*\Q]]
    .. literal_prompt
    .. [[\E\w*]]
  return {
    'rg',
    '--vimgrep',
    '--color=never',
    '--no-heading',
    '--smart-case',
    '--hidden',
    '--glob=*.py',
    '--glob=!.git/**',
    '--glob=!**/.venv/**',
    '--glob=!**/venv/**',
    '--glob=!**/__pycache__/**',
    '--pcre2',
    symbol_pattern,
    root,
  }
end

function M.open(root)
  local finders = require('telescope.finders')
  local make_entry = require('telescope.make_entry')
  local pickers = require('telescope.pickers')
  local telescope_config = require('telescope.config').values
  local opts = { cwd = root }

  pickers.new(opts, {
    prompt_title = 'Python Project Symbols',
    finder = finders.new_job(function(prompt)
      if prompt == '' then
        return
      end
      return M.command(prompt, root)
    end, make_entry.gen_from_vimgrep(opts), opts.max_results, root),
    previewer = telescope_config.grep_previewer(opts),
    sorter = telescope_config.generic_sorter(opts),
    push_cursor_on_edit = true,
    push_tagstack_on_edit = true,
  }):find()
end

return M
