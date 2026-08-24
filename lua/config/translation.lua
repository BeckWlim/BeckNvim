local M = {
  cold_time_ms = 700,
}

local chinese_pattern = vim.regex([=[[\u4e00-\u9fff]]=])
local result_namespace = vim.api.nvim_create_namespace('translation_query_result')
local active_query_state

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
  if vim.api.nvim_win_is_valid(query_state.winid) then
    vim.api.nvim_win_close(query_state.winid, true)
  end
end

local function query_text(query_state)
  local input_lines = vim.api.nvim_buf_get_lines(query_state.bufnr, 0, -1, false)
  return table.concat(input_lines, '\n')
end

local function nested_value(container, path, path_index)
  if path_index > #path then
    return container
  end
  if type(container) ~= 'table' then
    return nil
  end
  return nested_value(container[path[path_index]], path, path_index + 1)
end

local function clean_markup(raw_text)
  return vim.trim(
    raw_text
      :gsub('<[^>]->', '')
      :gsub('&quot;', '"')
      :gsub('&amp;', '&')
  )
end

local function append_detail(detail_lines, raw_text)
  if type(raw_text) ~= 'string' or #detail_lines >= 8 then
    return
  end

  local normalized_text = clean_markup(raw_text)
  if normalized_text ~= '' and not vim.tbl_contains(detail_lines, normalized_text) then
    table.insert(detail_lines, normalized_text)
  end
end

local function append_translation_groups(detail_lines, translation_groups)
  if type(translation_groups) ~= 'table' then
    return
  end

  for _, translation_group in ipairs(translation_groups) do
    local translation_items = type(translation_group) == 'table'
        and translation_group.tr
      or nil
    if type(translation_items) == 'table' then
      for _, translation_item in ipairs(translation_items) do
        local text_values = nested_value(translation_item, { 'l', 'i' }, 1)
        if type(text_values) == 'string' then
          append_detail(detail_lines, text_values)
        elseif type(text_values) == 'table' then
          for _, text_value in ipairs(text_values) do
            append_detail(detail_lines, text_value)
          end
        end
      end
    end
  end
end

function M.dictionary_lines(response_document)
  if type(response_document) ~= 'table' then
    return {}
  end

  local detail_lines = {}
  local simple_word = nested_value(response_document, { 'simple', 'word', 1 }, 1)
  if type(simple_word) == 'table' then
    local phone_parts = {}
    if type(simple_word.usphone) == 'string' then
      table.insert(phone_parts, '美 /' .. simple_word.usphone .. '/')
    end
    if type(simple_word.ukphone) == 'string' then
      table.insert(phone_parts, '英 /' .. simple_word.ukphone .. '/')
    end
    if #phone_parts == 0 and type(simple_word.phone) == 'string' then
      table.insert(phone_parts, simple_word.phone)
    end
    if #phone_parts > 0 then
      append_detail(detail_lines, table.concat(phone_parts, '  '))
    end
  end

  local english_word = nested_value(response_document, { 'ec', 'word', 1 }, 1)
  if type(english_word) == 'table' then
    append_translation_groups(detail_lines, english_word.trs)
  end

  local chinese_word = nested_value(response_document, { 'ce_new', 'word', 1 }, 1)
  if type(chinese_word) == 'table' then
    append_translation_groups(detail_lines, chinese_word.trs)
  end

  local modern_chinese_entry = nested_value(
    response_document,
    { 'newhh', 'dataList', 1 },
    1
  )
  if type(modern_chinese_entry) == 'table' and type(modern_chinese_entry.sense) == 'table' then
    for _, sense in ipairs(modern_chinese_entry.sense) do
      if type(sense) == 'table' then
        local definitions = type(sense.def) == 'table'
            and table.concat(sense.def, '；')
          or ''
        local category = type(sense.cat) == 'string' and sense.cat or ''
        local definition_prefix = category ~= '' and '[' .. category .. '] ' or ''
        append_detail(detail_lines, definition_prefix .. definitions)
        if type(sense.examples) == 'table' and type(sense.examples[1]) == 'string' then
          append_detail(detail_lines, '例：' .. sense.examples[1])
        end
      end
    end
  end

  local phrase_entries = nested_value(response_document, { 'phrs', 'phrs' }, 1)
  if type(phrase_entries) == 'table' then
    for phrase_index = 1, math.min(2, #phrase_entries) do
      local phrase_entry = phrase_entries[phrase_index]
      local phrase_text = nested_value(phrase_entry, { 'phr', 'headword', 'l', 'i' }, 1)
      local phrase_translation = nested_value(phrase_entry, { 'trs', 1, 'tr', 'l', 'i' }, 1)
      if type(phrase_text) == 'string' and type(phrase_translation) == 'string' then
        append_detail(detail_lines, '短语：' .. phrase_text .. ' — ' .. phrase_translation)
      end
    end
  end

  return detail_lines
end

local function show_result(query_state, result_lines, highlight_group)
  if not query_is_active(query_state) then
    return
  end

  local separator_width = math.max(1, vim.api.nvim_win_get_width(query_state.winid) - 2)
  local virtual_lines = {
    { { string.rep('─', separator_width), 'FloatBorder' } },
  }
  for _, result_line in ipairs(result_lines) do
    local display_line = result_line == '' and ' ' or result_line
    table.insert(virtual_lines, { { ' ' .. display_line, highlight_group } })
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
  if query_state.translation_lines then
    table.insert(rendered_lines, '翻译')
    vim.list_extend(rendered_lines, query_state.translation_lines)
  else
    table.insert(rendered_lines, 'Translating…')
  end

  if query_state.dictionary_lines and #query_state.dictionary_lines > 0 then
    table.insert(rendered_lines, '')
    table.insert(rendered_lines, '详细释义')
    vim.list_extend(rendered_lines, query_state.dictionary_lines)
  end
  show_result(query_state, rendered_lines, 'NormalFloat')
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
  vim.system(dictionary_command, { text = true }, function(completed_process)
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
      query_state.dictionary_lines = M.dictionary_lines(response_document)
      render_current_result(query_state)
    end)
  end)
end

function M.target_for(input_text)
  if chinese_pattern:match_str(input_text) then
    return 'en'
  end
  return 'zh-CN'
end

function M.translate(input_text)
  if vim.trim(input_text) == '' then
    return false
  end

  local target_language = M.target_for(input_text)
  local command_text = input_text
  if command_text:sub(1, 2) == '--' then
    command_text = ' ' .. command_text
  end

  local query_state = active_query_state
  if query_state then
    query_state.latest_request_text = command_text
    query_state.translation_lines = nil
    query_state.dictionary_lines = nil
    render_current_result(query_state)
    request_dictionary(query_state, input_text, command_text)
  end

  vim.cmd.Translate({
    args = { '--target=' .. target_language, command_text },
  })
  return true
end

local function schedule_translation(query_state)
  if not query_is_active(query_state) then
    return
  end

  query_state.timer:stop()
  query_state.latest_request_text = nil
  query_state.translation_lines = nil
  query_state.dictionary_lines = nil
  local input_text = query_text(query_state)
  if vim.trim(input_text) == '' then
    show_result(query_state, { '输入中文或英文，停顿后自动翻译。' }, 'Comment')
    return
  end

  show_result(query_state, { 'Waiting…' }, 'Comment')
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
    title = ' Translate 中 ↔ EN ',
    title_pos = 'center',
    footer = ' Auto: 700ms · Normal q / Insert Ctrl-Q: close ',
    footer_pos = 'center',
  })
  vim.wo[query_winid].wrap = true
  vim.wo[query_winid].scrolloff = 0

  local debounce_timer = assert(vim.uv.new_timer())
  local query_state = {
    bufnr = query_bufnr,
    winid = query_winid,
    timer = debounce_timer,
    latest_request_text = nil,
    translation_lines = nil,
    dictionary_lines = nil,
  }
  active_query_state = query_state
  show_result(query_state, { '输入中文或英文，停顿后自动翻译。' }, 'Comment')

  vim.keymap.set('n', 'q', close_query, {
    buffer = query_bufnr,
    nowait = true,
    silent = true,
    desc = 'Close translation query',
  })
  vim.keymap.set('i', '<C-q>', close_query, {
    buffer = query_bufnr,
    nowait = true,
    silent = true,
    desc = 'Close translation query',
  })

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
    end,
  })

  vim.cmd('startinsert')
end

---@param translator { original: string[], translation: string[] }
function M.render(translator)
  local query_state = active_query_state
  if not query_state or translator.original[1] ~= query_state.latest_request_text then
    return
  end
  query_state.translation_lines = translator.translation
  render_current_result(query_state)
end

function M.options()
  return {
    default = {
      cmds = {
        source = 'auto',
        target = 'zh-CN',
        handle = 'query-panel',
        engine = 'google',
      },
      cache = true,
    },
    translator = {
      handle = {
        {
          name = 'query-panel',
          render = M.render,
        },
      },
    },
  }
end

return M
