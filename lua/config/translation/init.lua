-- Translation query window: input float, debounce, subprocess lifecycle, and
-- result rendering. Backend selection, proxy resolution, and response parsing
-- live in `config.translation.providers`; their pure functions are re-exported
-- here so the public surface remains `config.translation`.
local providers = require('config.translation.providers')
local float = require('config.ui.float')

local M = {
  cold_time_ms = 700,
  max_query_bytes = 500,
}

for _, name in ipairs({
  'endpoint',
  'providers',
  'provider_order',
  'proxy_from_env',
  'resolve_proxy',
  'enable_proxy',
  'target_for',
  'next_provider',
  'provider_status_line',
  'translation_candidates',
  'dictionary_lines',
}) do
  M[name] = providers[name]
end

local result_namespace = vim.api.nvim_create_namespace('translation_query_result')
local active_query_state

local function stop_process(process)
  if not process then
    return
  end
  pcall(function()
    process:kill(15)
  end)
end

local function stop_requests(query_state)
  stop_process(query_state.translation_process)
  stop_process(query_state.dictionary_process)
  query_state.translation_process = nil
  query_state.dictionary_process = nil
end

local function stop_timer(query_state)
  if not query_state.timer:is_closing() then
    query_state.timer:stop()
    query_state.timer:close()
  end
end

local function query_is_active(query_state)
  return active_query_state == query_state
    and vim.api.nvim_buf_is_valid(query_state.bufnr)
    and vim.api.nvim_win_is_valid(query_state.winid)
end

local function close_query()
  local query_state = active_query_state
  active_query_state = nil
  if not query_state then
    return
  end

  if vim.api.nvim_get_mode().mode:sub(1, 1) == 'i' then
    vim.cmd('stopinsert')
  end
  stop_timer(query_state)
  stop_requests(query_state)
  if vim.api.nvim_win_is_valid(query_state.winid) then
    vim.api.nvim_win_close(query_state.winid, true)
  end
end

local function query_text(query_state)
  local input_lines = vim.api.nvim_buf_get_lines(query_state.bufnr, 0, -1, false)
  return table.concat(input_lines, '\n')
end

local function text_line(text, highlight_group)
  local display_text = text == '' and ' ' or text
  return { { '  ' .. display_text, highlight_group } }
end

local function section_divider(label, available_width)
  local left_rule = '── '
  local right_padding = ' '
  local occupied_width = vim.fn.strdisplaywidth(left_rule .. label .. right_padding)
  local right_rule_width = math.max(1, available_width - occupied_width)
  return {
    { left_rule, 'TranslationSeparator' },
    { label, 'TranslationSection' },
    { right_padding .. string.rep('─', right_rule_width), 'TranslationSeparator' },
  }
end

local function query_title(provider, proxy_label)
  local status_line = providers.provider_status_line(provider, proxy_label)
  return ' Translator · ' .. status_line .. ' '
end

local function update_query_title(query_state)
  if not vim.api.nvim_win_is_valid(query_state.winid) then
    return
  end
  vim.api.nvim_win_set_config(query_state.winid, {
    title = query_title(query_state.provider, query_state.proxy_label),
    title_pos = 'center',
  })
end

local function show_result(query_state, content_lines)
  if not query_is_active(query_state) then
    return
  end

  local virtual_lines = {}
  for _, content_line in ipairs(content_lines) do
    table.insert(virtual_lines, content_line)
  end

  vim.api.nvim_buf_clear_namespace(query_state.bufnr, result_namespace, 0, -1)
  local last_input_row = vim.api.nvim_buf_line_count(query_state.bufnr) - 1
  vim.api.nvim_buf_set_extmark(query_state.bufnr, result_namespace, last_input_row, 0, {
    virt_lines = virtual_lines,
    virt_lines_above = false,
    virt_lines_leftcol = true,
  })
end

local function render_current_result(query_state)
  local rendered_lines = {}
  if query_state.translation_error then
    table.insert(rendered_lines, section_divider(
      'Translation failed',
      vim.api.nvim_win_get_width(query_state.winid)
    ))
    table.insert(rendered_lines, text_line(query_state.translation_error, 'TranslationError'))
  elseif query_state.translation_lines then
    table.insert(rendered_lines, section_divider(
      'Translation',
      vim.api.nvim_win_get_width(query_state.winid)
    ))
    for _, translation_line in ipairs(query_state.translation_lines) do
      table.insert(rendered_lines, text_line(translation_line, 'TranslationContent'))
    end
  else
    table.insert(rendered_lines, text_line('Translating…', 'TranslationNotification'))
  end

  if query_state.dictionary_lines and #query_state.dictionary_lines > 0 then
    table.insert(rendered_lines, text_line('', 'TranslationContent'))
    table.insert(rendered_lines, section_divider(
      'Dictionary',
      vim.api.nvim_win_get_width(query_state.winid)
    ))
    for _, dictionary_line in ipairs(query_state.dictionary_lines) do
      table.insert(rendered_lines, text_line(dictionary_line, 'TranslationDictionary'))
    end
  end
  show_result(query_state, rendered_lines)
end

local function show_notification(query_state, message)
  show_result(query_state, { text_line(message, 'TranslationNotification') })
end

local function should_query_dictionary(input_text)
  local normalized_text = vim.trim(input_text)
  return not normalized_text:find('\n', 1, true)
    and vim.fn.strchars(normalized_text) <= 32
end

local function request_dictionary(query_state, input_text, request_text)
  if not should_query_dictionary(input_text) then
    return
  end

  local normalized_text = vim.trim(input_text)
  local dictionary_command = {
    'curl',
    '--silent',
    '--show-error',
    '--fail',
    '--max-time',
    '8',
    '--get',
    'https://dict.youdao.com/jsonapi',
    '--data-urlencode',
    'q=' .. normalized_text,
  }
  local dictionary_process
  local request_started = pcall(function()
    dictionary_process = vim.system(dictionary_command, {
      text = true,
      env = query_state.proxy_env,
    }, function(completed_process)
      vim.schedule(function()
        if not query_is_active(query_state)
          or query_state.latest_request_text ~= request_text
          or completed_process.code ~= 0 then
          return
        end

        local decode_succeeded, response_document = pcall(
          vim.json.decode,
          completed_process.stdout
        )
        if not decode_succeeded then
          return
        end
        query_state.dictionary_lines = providers.dictionary_lines(response_document)
        render_current_result(query_state)
      end)
    end)
  end)
  if request_started then
    query_state.dictionary_process = dictionary_process
  end
end

local function concise_process_error(completed_process)
  local raw_error = vim.trim(completed_process.stderr or '')
  if raw_error == '' then
    raw_error = ('curl exited with code %d'):format(completed_process.code)
  end
  local single_line_error = raw_error:gsub('[\r\n]+', ' ')
  return vim.fn.strcharpart(single_line_error, 0, 240)
end

local function request_translation(query_state, input_text, request_text, target_language)
  local normalized_text = vim.trim(input_text)
  if #normalized_text > M.max_query_bytes then
    query_state.translation_error = ('Input exceeds the backend %d-byte limit.'):format(
      M.max_query_bytes
    )
    render_current_result(query_state)
    return
  end

  local source_language = target_language == 'en' and 'zh-CN' or 'en'
  local provider = providers.providers[query_state.provider] or providers.providers.mymemory
  local translation_command = provider.build(source_language, target_language, normalized_text)

  local translation_process
  local request_started, start_error = pcall(function()
    translation_process = vim.system(translation_command, {
      text = true,
      env = query_state.proxy_env,
    }, function(completed_process)
      vim.schedule(function()
        if not query_is_active(query_state)
          or query_state.latest_request_text ~= request_text then
          return
        end

        if completed_process.code ~= 0 then
          query_state.translation_error = concise_process_error(completed_process)
          render_current_result(query_state)
          return
        end

        local decode_succeeded, response_document = pcall(
          vim.json.decode,
          completed_process.stdout
        )
        if not decode_succeeded or type(response_document) ~= 'table' then
          query_state.translation_error = 'The translation service returned an unparsable response.'
          render_current_result(query_state)
          return
        end

        local response_status = tonumber(response_document.responseStatus)
        if response_status and response_status ~= 200 then
          query_state.translation_error = tostring(
            response_document.responseDetails or 'The translation service rejected the request.'
          )
          render_current_result(query_state)
          return
        end

        local translation_lines = provider.parse(response_document)
        if #translation_lines == 0 then
          query_state.translation_error = 'The translation service returned no candidates.'
        else
          query_state.translation_lines = translation_lines
          query_state.translation_error = nil
        end
        render_current_result(query_state)
      end)
    end)
  end)

  if request_started then
    query_state.translation_process = translation_process
  else
    query_state.translation_error = vim.fn.strcharpart(tostring(start_error), 0, 240)
    render_current_result(query_state)
  end
end

function M.translate(input_text)
  if vim.trim(input_text) == '' then
    return false
  end

  local target_language = providers.target_for(input_text)
  local query_state = active_query_state
  if not query_state then
    return false
  end

  stop_requests(query_state)
  query_state.latest_request_text = input_text
  query_state.translation_lines = nil
  query_state.translation_error = nil
  query_state.dictionary_lines = nil
  render_current_result(query_state)
  request_dictionary(query_state, input_text, input_text)
  request_translation(query_state, input_text, input_text, target_language)
  return true
end

function M.switch_provider(query_state)
  query_state.provider = providers.next_provider(query_state.provider)
  update_query_title(query_state)
  local input_text = query_text(query_state)
  if vim.trim(input_text) == '' then
    show_notification(query_state, 'Type Chinese or English, pause to auto-translate.')
  else
    M.translate(input_text)
  end
end

function M.refresh_proxy()
  local query_state = active_query_state
  if not query_state or not query_is_active(query_state) then
    return false
  end
  local proxy_environment, proxy_label = providers.resolve_proxy()
  query_state.proxy_env = proxy_environment
  query_state.proxy_label = proxy_label
  update_query_title(query_state)
  local input_text = query_text(query_state)
  if vim.trim(input_text) ~= '' then
    M.translate(input_text)
  end
  return true
end

local function schedule_translation(query_state)
  if not query_is_active(query_state) then
    return
  end

  query_state.timer:stop()
  query_state.latest_request_text = nil
  query_state.translation_lines = nil
  query_state.translation_error = nil
  query_state.dictionary_lines = nil
  stop_requests(query_state)
  local input_text = query_text(query_state)
  if vim.trim(input_text) == '' then
    show_notification(query_state, 'Type Chinese or English, pause to auto-translate.')
    return
  end

  show_notification(query_state, 'Waiting…')
  query_state.timer:start(M.cold_time_ms, 0, vim.schedule_wrap(function()
    if not query_is_active(query_state) then
      return
    end

    local current_input_text = query_text(query_state)
    if vim.trim(current_input_text) ~= '' then
      M.translate(current_input_text)
    end
  end))
end

function M.open()
  close_query()

  local proxy_env, proxy_label = providers.resolve_proxy()
  local initial_provider = providers.default_provider
  local width = math.max(50, math.min(88, math.floor(vim.o.columns * 0.72)))
  local height = math.max(10, math.min(16, math.floor((vim.o.lines - 2) * 0.55)))
  local query_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[query_bufnr].bufhidden = 'wipe'
  vim.bo[query_bufnr].filetype = 'translate-query'

  local query_winid = vim.api.nvim_open_win(query_bufnr, true, {
    relative = 'editor',
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = query_title(initial_provider, proxy_label),
    title_pos = 'center',
    footer = ' Auto 700ms \194\183 Ctrl-G provider \194\183 q/Ctrl-Q close ',
    footer_pos = 'center',
  })
  vim.wo[query_winid].wrap = true
  vim.wo[query_winid].scrolloff = 0
  vim.wo[query_winid].winhighlight = table.concat({
    'Normal:TranslationFloat',
    'NormalFloat:TranslationFloat',
    'EndOfBuffer:TranslationFloat',
    'FloatBorder:TelescopeBorder',
    'FloatTitle:TelescopeBorder',
    'FloatFooter:TelescopeBorder',
  }, ',')

  local debounce_timer = assert(vim.uv.new_timer())
  local query_state = {
    bufnr = query_bufnr,
    winid = query_winid,
    timer = debounce_timer,
    latest_request_text = nil,
    translation_lines = nil,
    translation_error = nil,
    dictionary_lines = nil,
    translation_process = nil,
    dictionary_process = nil,
    proxy_env = proxy_env,
    proxy_label = proxy_label,
    provider = initial_provider,
  }
  active_query_state = query_state
  show_notification(query_state, 'Type Chinese or English, pause to auto-translate.')

  local change_group = vim.api.nvim_create_augroup(
    'translation_query_' .. query_bufnr,
    { clear = true }
  )
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = change_group,
    buffer = query_bufnr,
    callback = function()
      schedule_translation(query_state)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = change_group,
    buffer = query_bufnr,
    once = true,
    callback = function()
      if active_query_state == query_state then
        active_query_state = nil
      end
      stop_timer(query_state)
      stop_requests(query_state)
    end,
  })

  vim.cmd('startinsert')
  float.bind_close({
    accepts_input = true,
    buffer = query_bufnr,
    close = close_query,
    description = 'Close translation query',
  })
  -- Keep provider switching stable even when only one backend is currently
  -- registered, so adding a supported replacement does not change the UI.
  vim.keymap.set({ 'n', 'i' }, '<C-g>', function()
    M.switch_provider(query_state)
  end, {
    buffer = query_bufnr,
    nowait = true,
    silent = true,
    desc = 'Switch translation provider',
  })
end

return M
