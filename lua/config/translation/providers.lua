-- Translation backends: proxy resolution, provider registry, request building,
-- and response parsing. Everything here is pure or environment-driven; the
-- query-window UI and process lifecycle live in `config.translation` (init.lua).
local M = {}

M.endpoint = 'https://api.mymemory.translated.net/get'

local function proxy_host_label(proxy_url)
  if not proxy_url then
    return nil
  end
  return proxy_url:gsub('^%a+://', ''):gsub('/+$', '')
end

-- Extract the proxy variables already exported into a process environment.
-- Absent or empty values are omitted so the result is always a clean table
-- suitable for merging into a subprocess environment.
function M.proxy_from_env(env)
  local proxy = {}
  local http_proxy = env.http_proxy or env.HTTP_PROXY
  local https_proxy = env.https_proxy or env.HTTPS_PROXY
  local all_proxy = env.all_proxy or env.ALL_PROXY
  if http_proxy then proxy.http_proxy = http_proxy end
  if https_proxy then proxy.https_proxy = https_proxy end
  if all_proxy then proxy.ALL_PROXY = all_proxy end
  if next(proxy) == nil then
    return nil
  end
  return proxy
end

-- Resolve the proxy environment for outbound requests from the proxy variables
-- already exported into Neovim's environment. When none are present the
-- connection goes direct (no proxy). Returns the environment table to merge and
-- a short `host:port` label for display.
function M.resolve_proxy()
  local proxy = M.proxy_from_env(vim.env)
  if not proxy then
    return {}, nil
  end
  return proxy, proxy_host_label(proxy.https_proxy or proxy.http_proxy or proxy.ALL_PROXY)
end

function M.enable_proxy()
  for environment_name, environment_value in pairs(M.resolve_proxy()) do
    vim.env[environment_name] = environment_value
  end
end

local chinese_pattern = vim.regex([=[[一-鿿]]=])

function M.target_for(input_text)
  if chinese_pattern:match_str(input_text) then
    return 'en'
  end
  return 'zh-CN'
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
      :gsub('&#39;', "'")
      :gsub('&lt;', '<')
      :gsub('&gt;', '>')
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

local function append_text_values(detail_lines, text_values)
  if type(text_values) == 'string' then
    append_detail(detail_lines, text_values)
    return
  end
  if type(text_values) ~= 'table' then
    return
  end

  local linked_text = text_values['#text']
  if type(linked_text) == 'string' then
    append_detail(detail_lines, linked_text)
    return
  end

  for _, text_value in ipairs(text_values) do
    append_text_values(detail_lines, text_value)
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
        append_text_values(detail_lines, text_values)
      end
    end
  end
end

local function curl_base()
  return {
    'curl',
    '--silent',
    '--show-error',
    '--fail',
    '--connect-timeout',
    '5',
    '--max-time',
    '15',
    '--retry',
    '2',
    '--retry-all-errors',
    '--retry-max-time',
    '15',
  }
end

M.providers = {
  mymemory = {
    name = 'MyMemory',
    build = function(source_language, target_language, text)
      local command = curl_base()
      vim.list_extend(command, {
        '--get',
        M.endpoint,
        '--data-urlencode',
        'q=' .. text,
        '--data-urlencode',
        'langpair=' .. source_language .. '|' .. target_language,
      })
      return command
    end,
    parse = function(response_document)
      if type(response_document) ~= 'table' then
        return {}
      end

      local candidate_lines = {}
      local primary_translation = nested_value(
        response_document,
        { 'responseData', 'translatedText' },
        1
      )
      append_detail(candidate_lines, primary_translation)

      if type(response_document.matches) == 'table' then
        for _, match_document in ipairs(response_document.matches) do
          if type(match_document) == 'table' then
            append_detail(candidate_lines, match_document.translation)
          end
        end
      end
      return candidate_lines
    end,
  },
  google = {
    name = 'Google',
    build = function(_source_language, target_language, text)
      local command = curl_base()
      vim.list_extend(command, {
        '--get',
        'https://translate.googleapis.com/translate_a/single',
        '--data-urlencode',
        'client=gtx',
        '--data-urlencode',
        'sl=auto',
        '--data-urlencode',
        'tl=' .. target_language,
        '--data-urlencode',
        'dt=t',
        '--data-urlencode',
        'q=' .. text,
      })
      return command
    end,
    parse = function(response_document)
      if type(response_document) ~= 'table' or type(response_document[1]) ~= 'table' then
        return {}
      end

      local parts = {}
      for _, segment in ipairs(response_document[1]) do
        if type(segment) == 'table' and type(segment[1]) == 'string' then
          parts[#parts + 1] = segment[1]
        end
      end
      if #parts == 0 then
        return {}
      end
      return { table.concat(parts) }
    end,
  },
}

M.provider_order = { 'mymemory', 'google' }
M.default_provider = 'mymemory'

function M.next_provider(current_provider)
  for index, provider_key in ipairs(M.provider_order) do
    if provider_key == current_provider then
      return M.provider_order[index % #M.provider_order + 1]
    end
  end
  return M.provider_order[1]
end

function M.provider_status_line(provider_key, proxy_label)
  local provider_name = M.providers[provider_key] and M.providers[provider_key].name or '?'
  local proxy_status = proxy_label and ('proxy ' .. proxy_label) or 'no proxy'
  return provider_name .. ' \194\183 ' .. proxy_status
end

function M.translation_candidates(response_document)
  return M.providers.mymemory.parse(response_document)
end

function M.google_translation_candidates(response_document)
  return M.providers.google.parse(response_document)
end

-- Parse a Youdao dictionary response into display lines: phonetics, senses,
-- modern Chinese definitions with examples, and common phrases.
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
  local contemporary_chinese_word = nested_value(response_document, { 'ce', 'word', 1 }, 1)
  if type(contemporary_chinese_word) == 'table' then
    append_translation_groups(detail_lines, contemporary_chinese_word.trs)
  end
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

return M
