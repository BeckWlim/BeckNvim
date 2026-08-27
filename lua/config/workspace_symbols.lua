local project = require('config.project')

local M = {}
local ready = false

local function definition(kind, name)
  return { kind = kind, name = name }
end

local function assigned_python_type_kind(assigned_value)
  for _, constructor in ipairs({ 'TypeVar', 'ParamSpec', 'TypeVarTuple' }) do
    if assigned_value:match('^%s*[%w_%.]*' .. constructor .. '%s*%(') then
      return 'TypeVar'
    end
  end

  for _, constructor in ipairs({ 'NewType', 'TypeAliasType' }) do
    if assigned_value:match('^%s*[%w_%.]*' .. constructor .. '%s*%(') then
      return 'Type'
    end
  end
end

local function python_definition(source_line)
  local class_name = source_line:match('^%s*class%s+([%a_][%w_]*)')
  if class_name then
    return definition('Class', class_name)
  end

  local function_name = source_line:match('^%s*async%s+def%s+([%a_][%w_]*)')
    or source_line:match('^%s*def%s+([%a_][%w_]*)')
  if function_name then
    return definition('Function', function_name)
  end

  local declared_type_name = source_line:match('^%s*type%s+([%a_][%w_]*)%s*%b[]%s*=')
    or source_line:match('^%s*type%s+([%a_][%w_]*)%s*=')
  if declared_type_name then
    return definition('Type', declared_type_name)
  end

  local annotated_name, annotation, annotated_value =
    source_line:match('^([%a_][%w_]*)%s*:%s*(.-)%s*=%s*(.+)$')
  if annotated_name then
    if annotation:match('TypeAlias') then
      return definition('Type', annotated_name)
    end
    return definition(assigned_python_type_kind(annotated_value) or 'Variable', annotated_name)
  end

  local assigned_name, assigned_value = source_line:match('^([%a_][%w_]*)%s*=%s*(.+)$')
  if assigned_name then
    return definition(assigned_python_type_kind(assigned_value) or 'Variable', assigned_name)
  end

  local declared_name, declared_annotation =
    source_line:match('^([%a_][%w_]*)%s*:%s*(.-)%s*$')
  if declared_name then
    local declared_kind = declared_annotation:match('TypeAlias') and 'Type' or 'Variable'
    return definition(declared_kind, declared_name)
  end
end

local function lua_definition(source_line)
  local function_name = source_line:match('^%s*local%s+function%s+([%a_][%w_%.:]*)')
    or source_line:match('^%s*function%s+([%a_][%w_%.:]*)')
    or source_line:match('^%s*local%s+([%a_][%w_]*)%s*=%s*function')
    or source_line:match('^%s*([%a_][%w_%.:]*)%s*=%s*function')
  if function_name then
    return definition('Function', function_name)
  end

  local local_name = source_line:match('^%s*local%s+([%a_][%w_]*)%s*=')
  local assigned_name = local_name or source_line:match('^%s*([%a_][%w_%.:]*)%s*=')
  if assigned_name then
    return definition('Variable', assigned_name)
  end
end

local function shell_definition(source_line)
  local function_name = source_line:match('^%s*function%s+([%a_][%w_]*)')
    or source_line:match('^%s*([%a_][%w_]*)%s*%(%s*%)')
  if function_name then
    return definition('Function', function_name)
  end

  local assigned_name = source_line:match('^%s*([%a_][%w_]*)=')
    or source_line:match('^%s*local%s+([%a_][%w_]*)=')
    or source_line:match('^%s*declare%s+[^%s]*%s*([%a_][%w_]*)=')
    or source_line:match('^%s*readonly%s+([%a_][%w_]*)=')
    or source_line:match('^%s*export%s+([%a_][%w_]*)=')
  if assigned_name then
    return definition('Variable', assigned_name)
  end
end

local function vim_definition(source_line)
  local function_name = source_line:match('^%s*fu%w*!?%s+([%w_:#%.]+)')
    or source_line:match('^%s*def!?%s+([%w_:#%.]+)')
  if function_name then
    return definition('Function', function_name)
  end

  local class_name = source_line:match('^%s*class%s+([%a_][%w_]*)')
  if class_name then
    return definition('Class', class_name)
  end

  local command_name = source_line:match('^%s*com%w*!?%s+([%a_][%w_]*)')
  if command_name then
    return definition('Command', command_name)
  end

  local variable_name = source_line:match('^%s*let%s+([%w_:#%.]+)')
    or source_line:match('^%s*var%s+([%w_:#%.]+)')
  if variable_name then
    return definition('Variable', variable_name)
  end
end

local function c_family_definition(source_line)
  local macro_name = source_line:match('^%s*#%s*define%s+([%a_][%w_]*)')
  if macro_name then
    return definition('Macro', macro_name)
  end

  local namespace_name = source_line:match('^%s*namespace%s+([%a_][%w_]*)')
  if namespace_name then
    return definition('Namespace', namespace_name)
  end

  local enum_name = source_line:match('^%s*enum%s+class%s+([%a_][%w_]*)')
    or source_line:match('^%s*enum%s+struct%s+([%a_][%w_]*)')
    or source_line:match('^%s*enum%s+([%a_][%w_]*)')
  if enum_name then
    return definition('Enum', enum_name)
  end

  local type_name = source_line:match('^%s*class%s+([%a_][%w_]*)')
    or source_line:match('^%s*struct%s+([%a_][%w_]*)')
    or source_line:match('^%s*union%s+([%a_][%w_]*)')
    or source_line:match('^%s*concept%s+([%a_][%w_]*)')
    or source_line:match('^%s*using%s+([%a_][%w_]*)%s*=')
    or source_line:match('^%s*typedef%s+.-([%a_][%w_]*)%s*;%s*$')
  if type_name then
    return definition('Type', type_name)
  end

  local qualified_function_name =
    source_line:match('^%s*([%a_][%w_]*::[%w_:~]+)%s*%(')
  local typed_function_name =
    source_line:match('^%s*[%w_:<>,%*&~%s]+%s+([%a_~][%w_:~]*)%s*%(')
  local function_name = qualified_function_name or typed_function_name
  if function_name then
    return definition('Function', function_name)
  end

  local declaration_prefix, variable_name = source_line:match(
    '^%s*(.-)%s+([%a_][%w_]*)%s*[%[%]0-9]*%s*[=;]'
  )
  if declaration_prefix
      and declaration_prefix:match('^[%w_:<>,%*&~%s]+$')
      and variable_name
      and not source_line:match('^%s*return%s+') then
    return definition('Variable', variable_name)
  end
end

local c_family_extensions = {
  c = true,
  cc = true,
  cpp = true,
  cxx = true,
  h = true,
  hh = true,
  hpp = true,
  hxx = true,
  cu = true,
  cuh = true,
}

function M.definition(filename, source_line)
  local extension = filename:match('%.([^./]+)$')
  local normalized_extension = extension and extension:lower() or ''
  if normalized_extension == 'py' then
    return python_definition(source_line)
  end
  if normalized_extension == 'lua' then
    return lua_definition(source_line)
  end
  if normalized_extension == 'sh' or normalized_extension == 'bash' then
    return shell_definition(source_line)
  end
  if normalized_extension == 'vim' then
    return vim_definition(source_line)
  end
  if normalized_extension == 'md' or normalized_extension == 'markdown' then
    local heading_name = source_line:match('^%s*#+%s+(.+)%s*$')
    if heading_name then
      return definition('Section', heading_name)
    end
  end
  if c_family_extensions[normalized_extension] then
    return c_family_definition(source_line)
  end
end

local function escaped_pcre_literal(text)
  return text:gsub('\\E', '\\E\\\\E\\Q')
end

function M.commands(prompt, root)
  local normalized_prompt = vim.trim(prompt)
  if #normalized_prompt < 2 then
    return
  end

  local literal_prompt = escaped_pcre_literal(normalized_prompt)
  local simple_name_pattern
  local compound_name_pattern
  if #normalized_prompt == 2 then
    simple_name_pattern = [=[(?=[A-Za-z_])\Q]=] .. literal_prompt .. [=[\E\w*]=]
    compound_name_pattern = [=[(?=[A-Za-z_])(?:[\w~]+[.:])*\Q]=]
      .. literal_prompt
      .. [=[\E[\w.:~]*]=]
  else
    simple_name_pattern = [=[(?=[A-Za-z_])\w*\Q]=]
      .. literal_prompt
      .. [=[\E\w*]=]
    compound_name_pattern = [=[(?=[A-Za-z_])[\w.:~]*\Q]=]
      .. literal_prompt
      .. [=[\E[\w.:~]*]=]
  end
  local function search_command(globs, symbol_pattern)
    local command = {
      'rg',
      '--vimgrep',
      '--color=never',
      '--no-heading',
      '--smart-case',
      '--hidden',
      '--pcre2',
    }
    vim.list_extend(command, globs)
    vim.list_extend(command, {
      '--glob=!.git/**',
      '--glob=!**/.venv/**',
      '--glob=!**/venv/**',
      '--glob=!**/env/**',
      '--glob=!**/__pycache__/**',
      '--glob=!**/build/**',
      '--glob=!**/dist/**',
      '^(?:' .. symbol_pattern .. ')',
      root,
    })
    return command
  end

  local python_pattern = table.concat({
    [=[\s*(?:(?:async\s+)?def|class|type)\s+]=] .. simple_name_pattern,
    simple_name_pattern .. [=[\s*(?::[^=\r\n]+)?\s*=(?!=)]=],
    simple_name_pattern .. [=[\s*:\s*[^=\r\n]+$]=],
  }, '|')
  local lua_pattern = table.concat({
    [=[\s*(?:local\s+)?function\s+]=] .. compound_name_pattern,
    [=[\s*(?:local\s+)?]=] .. compound_name_pattern .. [=[\s*=]=],
  }, '|')
  local shell_pattern = table.concat({
    [=[\s*function\s+]=] .. simple_name_pattern,
    [=[\s*]=] .. simple_name_pattern .. [=[\s*\(\s*\)]=],
    [=[\s*(?:(?:local|readonly|export)\s+|declare\s+[^\s]+\s+)?]=]
      .. simple_name_pattern
      .. '=',
  }, '|')
  local vim_pattern = [=[\s*(?:fu\w*!?|def!?|class|com\w*!?|let|var)\s+]=]
    .. compound_name_pattern
  local markdown_pattern = [=[\s*#{1,6}\s+[^\r\n]*\Q]=]
    .. literal_prompt
    .. [=[\E[^\r\n]*]=]
  local c_family_pattern = table.concat({
    [=[\s*(?:class|struct|union|namespace|concept)\s+]=] .. simple_name_pattern,
    [=[\s*enum(?:\s+(?:class|struct))?\s+]=] .. simple_name_pattern,
    [=[\s*using\s+]=] .. simple_name_pattern .. [=[\s*=]=],
    [=[\s*typedef\b[^\r\n]*\b]=] .. simple_name_pattern .. [=[\s*;]=],
    [=[\s*#\s*define\s+]=] .. simple_name_pattern,
    [=[\s*(?=[\w:~]*::)]=] .. compound_name_pattern .. [=[\s*\(]=],
    [=[\s*(?:[\w_:<>,*&~]+\s+)+]=]
      .. compound_name_pattern
      .. [=[\s*\(]=],
    [=[\s*(?:[\w_:<>,*&~]+\s+)+]=]
      .. simple_name_pattern
      .. [=[\s*(?:[=;\[])]=],
  }, '|')

  return {
    search_command({ '--glob=*.py' }, python_pattern),
    search_command({ '--glob=*.lua' }, lua_pattern),
    search_command({ '--glob=*.sh', '--glob=*.bash' }, shell_pattern),
    search_command({ '--glob=*.vim' }, vim_pattern),
    search_command({ '--glob=*.md', '--glob=*.markdown' }, markdown_pattern),
    search_command({
      '--glob=*.c',
      '--glob=*.cc',
      '--glob=*.cpp',
      '--glob=*.cxx',
      '--glob=*.h',
      '--glob=*.hh',
      '--glob=*.hpp',
      '--glob=*.hxx',
      '--glob=*.cu',
      '--glob=*.cuh',
    }, c_family_pattern),
  }
end

local function multi_job_finder(root, entry_maker)
  local Job = require('plenary.job')
  local maximum_results = 1000
  local jobs = {}
  local generation = 0
  local active_process_complete

  local function stop_jobs()
    for _, job in ipairs(jobs) do
      if not job.is_shutdown then
        job:shutdown()
      end
    end
    jobs = {}
  end

  local function cancel_active_query()
    generation = generation + 1
    active_process_complete = nil
    stop_jobs()
  end

  local finder = {
    close = function()
      cancel_active_query()
    end,
  }

  return setmetatable(finder, {
    __call = function(_, prompt, process_result, process_complete)
      cancel_active_query()
      local active_generation = generation
      active_process_complete = process_complete

      local function complete_active_query()
        if generation ~= active_generation or active_process_complete ~= process_complete then
          return
        end
        active_process_complete = nil
        process_complete()
      end

      local commands = M.commands(prompt, root)
      if not commands then
        complete_active_query()
        return
      end

      local remaining_jobs = #commands
      local received_line_count = 0
      local result_index = 0
      for _, command in ipairs(commands) do
        local executable = command[1]
        local arguments = vim.list_slice(command, 2)
        local job = Job:new({
          command = executable,
          args = arguments,
          cwd = root,
          enable_recording = false,
          on_stdout = function(_, line)
            if generation ~= active_generation
                or received_line_count >= maximum_results
                or not line
                or line == '' then
              return
            end
            received_line_count = received_line_count + 1
            local output_line = line
            vim.schedule(function()
              if generation ~= active_generation or result_index >= maximum_results then
                return
              end
              local entry = entry_maker(output_line)
              if entry then
                result_index = result_index + 1
                entry.index = result_index
                process_result(entry)
              end
            end)
            if received_line_count == maximum_results then
              vim.schedule(function()
                if generation == active_generation then
                  stop_jobs()
                end
              end)
            end
          end,
          on_exit = function()
            vim.schedule(function()
              if generation ~= active_generation then
                return
              end
              remaining_jobs = remaining_jobs - 1
              if remaining_jobs == 0 then
                jobs = {}
                complete_active_query()
              end
            end)
          end,
        })
        table.insert(jobs, job)
        job:start()
      end
    end,
  })
end

local function relative_path(root, filename)
  local normalized_root = vim.fs.normalize(root)
  local normalized_filename = vim.fs.normalize(filename)
  local root_prefix = normalized_root .. '/'
  if normalized_filename:sub(1, #root_prefix) == root_prefix then
    return normalized_filename:sub(#root_prefix + 1)
  end
  return normalized_filename
end

local function symbol_entry_maker(root, opts)
  local entry_display = require('telescope.pickers.entry_display')
  local make_entry = require('telescope.make_entry')
  local vimgrep_entry_maker = make_entry.gen_from_vimgrep(opts)
  local displayer = entry_display.create({
    separator = '  ',
    items = {
      { width = 36 },
      { width = 10 },
      { remaining = true },
    },
  })

  local function make_display(entry)
    return displayer({
      { entry.symbol_name, 'TelescopeResultsIdentifier' },
      { entry.symbol_kind, 'TelescopeResultsComment' },
      ('%s:%d'):format(entry.symbol_path, entry.lnum),
    })
  end

  return function(line)
    local entry = vimgrep_entry_maker(line)
    local parsed_definition = M.definition(entry.filename, entry.text)
    if not parsed_definition then
      return
    end

    entry.symbol_name = parsed_definition.name
    entry.symbol_kind = parsed_definition.kind
    entry.symbol_path = relative_path(root, entry.filename)
    entry.ordinal = ('%s %s %s'):format(
      parsed_definition.name,
      parsed_definition.kind,
      entry.symbol_path
    )
    entry.display = make_display
    return entry
  end
end

function M.setup()
  ready = false
  vim.schedule(function()
    ready = true
  end)
end

function M.is_ready()
  return ready
end

function M.open()
  if not ready then
    vim.notify('Project definition search is loading; retry shortly', vim.log.levels.INFO)
    return
  end

  local root = project.for_buffer(vim.api.nvim_get_current_buf())
  local pickers = require('telescope.pickers')
  local telescope_config = require('telescope.config').values
  local opts = { cwd = root }

  pickers.new(opts, {
    prompt_title = 'Project Definitions (type 2+ characters)',
    finder = multi_job_finder(root, symbol_entry_maker(root, opts)),
    previewer = telescope_config.grep_previewer(opts),
    sorter = telescope_config.generic_sorter(opts),
    push_cursor_on_edit = true,
    push_tagstack_on_edit = true,
  }):find()
end

return M
