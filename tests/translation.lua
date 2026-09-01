local translation = require('config.translation')
assert(not translation.refresh_proxy(), 'Proxy refresh reported an inactive translation dialog')
assert(
  translation.endpoint == 'https://api.mymemory.translated.net/get',
  'translation must avoid the plugin shared Apps Script endpoint'
)
assert(
  #translation.provider_order == 1
    and translation.provider_order[1] == 'mymemory'
    and translation.next_provider('mymemory') == 'mymemory',
  'single-provider cycling did not preserve the provider-switch structure'
)
assert(
  translation.next_provider('unknown') == 'mymemory',
  'an unknown provider must fall back to the first provider'
)

assert(
  translation.provider_status_line('mymemory', '127.0.0.1:7890')
    == 'MyMemory · proxy 127.0.0.1:7890',
  'provider status line does not render provider and proxy'
)
assert(
  translation.provider_status_line('mymemory', nil) == 'MyMemory · no proxy',
  'provider status line does not render a direct connection'
)

assert(
  translation.proxy_from_env({ http_proxy = 'http://10.0.0.1:8080' }).http_proxy
    == 'http://10.0.0.1:8080',
  'lowercase proxy variable was not detected'
)
assert(
  translation.proxy_from_env({ HTTPS_PROXY = 'https://10.0.0.1:8080' }).https_proxy
    == 'https://10.0.0.1:8080',
  'uppercase proxy variable was not detected'
)
assert(
  translation.proxy_from_env({}) == nil,
  'absent proxy variables must resolve to nil'
)

local previous_http_proxy = vim.env.http_proxy
local previous_https_proxy = vim.env.https_proxy
local previous_all_proxy = vim.env.ALL_PROXY
vim.env.http_proxy = 'http://127.0.0.1:9999'
vim.env.https_proxy = 'http://127.0.0.1:9999'
vim.env.ALL_PROXY = 'socks5://127.0.0.1:9999'

local resolved_proxy, resolved_label = translation.resolve_proxy()
assert(
  resolved_proxy.http_proxy == 'http://127.0.0.1:9999'
    and resolved_proxy.https_proxy == 'http://127.0.0.1:9999'
    and resolved_proxy.ALL_PROXY == 'socks5://127.0.0.1:9999',
  'resolve_proxy did not prefer exported environment variables'
)
assert(resolved_label == '127.0.0.1:9999', 'resolve_proxy label is wrong')

local function proxy_env_matches(actual, expected)
  return (actual.http_proxy or nil) == (expected.http_proxy or nil)
    and (actual.https_proxy or nil) == (expected.https_proxy or nil)
    and (actual.ALL_PROXY or nil) == (expected.ALL_PROXY or nil)
end

assert(translation.target_for('hello world') == 'zh-CN', 'English target is not Chinese')
assert(translation.target_for('你好，world') == 'en', 'Chinese target is not English')
assert(translation.cold_time_ms == 700, 'translation debounce delay changed')

local translation_candidates = translation.translation_candidates({
  responseData = { translatedText = 'This is a test' },
  matches = {
    { translation = 'This is a test' },
    { translation = 'This is one test.' },
    { translation = 'It&#39;s a test.' },
  },
})
assert(#translation_candidates == 3, 'distinct translation candidates were not preserved')
assert(
  translation_candidates[3] == "It's a test.",
  'translation candidate entities were not decoded'
)

local english_dictionary_lines = translation.dictionary_lines({
  simple = {
    word = {
      {
        usphone = 'həˈloʊ',
        ukphone = 'həˈləʊ',
      },
    },
  },
  ec = {
    word = {
      {
        trs = {
          {
            tr = {
              { l = { i = { 'int. 你好；喂' } } },
            },
          },
        },
      },
    },
  },
  phrs = {
    phrs = {
      {
        phr = { headword = { l = { i = 'say hello' } } },
        trs = {
          { tr = { l = { i = '打招呼' } } },
        },
      },
    },
  },
})
assert(
  english_dictionary_lines[1] == '美 /həˈloʊ/  英 /həˈləʊ/',
  'English pronunciation was not rendered'
)
assert(
  vim.tbl_contains(english_dictionary_lines, 'int. 你好；喂'),
  'English detailed meaning was not rendered'
)
assert(
  vim.tbl_contains(english_dictionary_lines, '短语：say hello — 打招呼'),
  'English phrase was not rendered'
)

local chinese_dictionary_lines = translation.dictionary_lines({
  simple = {
    word = {
      { phone = 'cè shì' },
    },
  },
  ce_new = {
    word = {
      {
        trs = {
          {
            tr = {
              { l = { i = { 'test; testing' } } },
            },
          },
        },
      },
    },
  },
  ce = {
    word = {
      {
        trs = {
          {
            tr = {
              { l = { i = { '', { ['#text'] = 'examine' } } } },
            },
          },
          {
            tr = {
              { l = { i = { '', { ['#text'] = 'verify' } } } },
            },
          },
        },
      },
    },
  },
  newhh = {
    dataList = {
      {
        sense = {
          {
            cat = '动词',
            def = { '测量试验' },
            examples = { '进行<self>测试</self>' },
          },
        },
      },
    },
  },
})
assert(chinese_dictionary_lines[1] == 'cè shì', 'Chinese pronunciation was not rendered')
assert(
  vim.tbl_contains(chinese_dictionary_lines, 'examine')
    and vim.tbl_contains(chinese_dictionary_lines, 'verify'),
  'Chinese candidate expressions were not rendered'
)
assert(
  vim.tbl_contains(chinese_dictionary_lines, '[动词] 测量试验'),
  'Chinese detailed meaning was not rendered'
)
assert(
  vim.tbl_contains(chinese_dictionary_lines, '例：进行测试'),
  'Chinese example markup was not cleaned before rendering'
)

local original_system = vim.system
local system_requests = {}
vim.system = function(command, options, callback)
  local process = { killed = false }
  function process:kill(_signal)
    self.killed = true
  end
  table.insert(system_requests, {
    command = command,
    options = options,
    callback = callback,
    process = process,
  })
  return process
end

local function command_contains(command, expected_argument)
  return vim.tbl_contains(command, expected_argument)
end

local function translation_request(start_index)
  for request_index = start_index, #system_requests do
    local request = system_requests[request_index]
    if command_contains(request.command, translation.endpoint) then
      return request
    end
  end
end

local function rendered_text(buffer_number)
  local namespace = vim.api.nvim_get_namespaces().translation_query_result
  local extmarks = vim.api.nvim_buf_get_extmarks(
    buffer_number,
    namespace,
    0,
    -1,
    { details = true }
  )
  local rendered_parts = {}
  for _, extmark in ipairs(extmarks) do
    local virtual_lines = extmark[4].virt_lines or {}
    for _, virtual_line in ipairs(virtual_lines) do
      for _, virtual_chunk in ipairs(virtual_line) do
        table.insert(rendered_parts, virtual_chunk[1])
      end
    end
  end
  return table.concat(rendered_parts, '\n')
end

local function rendered_highlights(buffer_number)
  local namespace = vim.api.nvim_get_namespaces().translation_query_result
  local extmarks = vim.api.nvim_buf_get_extmarks(
    buffer_number,
    namespace,
    0,
    -1,
    { details = true }
  )
  local highlight_groups = {}
  for _, extmark in ipairs(extmarks) do
    local virtual_lines = extmark[4].virt_lines or {}
    for _, virtual_line in ipairs(virtual_lines) do
      for _, virtual_chunk in ipairs(virtual_line) do
        if virtual_chunk[2] then
          highlight_groups[virtual_chunk[2]] = true
        end
      end
    end
  end
  return highlight_groups
end

local function window_title_text(window_config)
  local title = window_config.title
  if type(title) == 'string' then
    return title
  end
  local title_parts = {}
  for _, title_chunk in ipairs(title or {}) do
    title_parts[#title_parts + 1] = title_chunk[1]
  end
  return table.concat(title_parts)
end

translation.open()
local query_winid = vim.api.nvim_get_current_win()
local query_bufnr = vim.api.nvim_win_get_buf(query_winid)
local query_window_config = vim.api.nvim_win_get_config(query_winid)
assert(query_window_config.relative == 'editor', 'translation query is not a floating window')
assert(vim.bo[query_bufnr].filetype == 'translate-query', 'translation query buffer type is wrong')
assert(
  query_window_config.col == math.floor((vim.o.columns - query_window_config.width) / 2),
  'translation query is not horizontally centered'
)
local query_window_highlights = vim.wo[query_winid].winhighlight
assert(
  query_window_highlights:find('Normal:TranslationFloat', 1, true) ~= nil,
  'translation query does not use its dedicated background'
)
assert(
  query_window_highlights:find('FloatBorder:TelescopeBorder', 1, true) ~= nil
    and query_window_highlights:find('FloatTitle:TelescopeBorder', 1, true) ~= nil
    and query_window_highlights:find('FloatFooter:TelescopeBorder', 1, true) ~= nil,
  'translation edges do not uniformly match the search interface'
)
assert(
  vim.fn.maparg('q', 'n', false, true).desc == 'Close translation query',
  'translation query close mapping is missing'
)
assert(
  vim.fn.maparg('<C-q>', 'i', false, true).desc == 'Close translation query',
  'translation query insert-mode close mapping is missing'
)
assert(
  vim.fn.maparg('<C-g>', 'n', false, true).desc == 'Switch translation provider'
    and vim.fn.maparg('<C-g>', 'i', false, true).desc == 'Switch translation provider',
  'translation query provider-switch mapping is missing'
)
assert(
  vim.fn.maparg('<C-p>', 'i', false, true).desc ~= 'Switch translation provider',
  'translation query still captures the snippet/completion key'
)
local initial_title = window_title_text(query_window_config)
assert(initial_title:find('MyMemory', 1, true), 'translation title omits the active provider')
assert(
  initial_title:find('proxy 127.0.0.1:9999', 1, true),
  'translation title omits the active proxy'
)
vim.env.http_proxy = 'http://127.0.0.1:8888'
vim.env.https_proxy = 'http://127.0.0.1:8888'
assert(translation.refresh_proxy(), 'Active translation proxy was not refreshed')
assert(
  window_title_text(vim.api.nvim_win_get_config(query_winid)):find(
    'proxy 127.0.0.1:8888',
    1,
    true
  ),
  'Translation title did not reflect the refreshed proxy'
)
vim.env.http_proxy = 'http://127.0.0.1:9999'
vim.env.https_proxy = 'http://127.0.0.1:9999'
assert(translation.refresh_proxy(), 'Translation proxy could not be restored for requests')
vim.fn.maparg('<C-g>', 'i', false, true).callback()
assert(
  window_title_text(vim.api.nvim_win_get_config(query_winid)):find('MyMemory', 1, true),
  'Single-provider switching changed the active provider'
)
local initial_highlights = rendered_highlights(query_bufnr)
assert(
  initial_highlights.TranslationNotification,
  'translation guidance does not use the notification style'
)
assert(
  not rendered_text(query_bufnr):find('proxy 127.0.0.1:9999', 1, true),
  'provider metadata still occupies the translation content area'
)

vim.api.nvim_buf_set_lines(query_bufnr, 0, -1, false, { '--literal | value' })
vim.api.nvim_exec_autocmds('TextChangedI', { buffer = query_bufnr })
assert(
  vim.wait(translation.cold_time_ms + 300, function()
    return translation_request(1) ~= nil
  end),
  'translation was not requested after the debounce delay'
)
local first_translation_request = translation_request(1)
assert(
  command_contains(first_translation_request.command, 'q=--literal | value')
    and command_contains(first_translation_request.command, 'langpair=en|zh-CN'),
  'translation query did not preserve arbitrary input'
)
assert(
  proxy_env_matches(first_translation_request.options.env, resolved_proxy),
  'translation request did not receive the detected proxy environment'
)
assert(
  not vim.tbl_contains(first_translation_request.command, 'script.google.com'),
  'translation request still uses the broken Apps Script endpoint'
)
assert(
  not vim.tbl_contains(
    first_translation_request.command,
    'https://translate.googleapis.com/translate_a/single'
  ),
  'translation request still uses the rate-limited Google web endpoint'
)

local window_count_before_result = #vim.api.nvim_list_wins()
first_translation_request.callback({
  code = 0,
  signal = 0,
  stdout = vim.json.encode({
    responseData = { translatedText = '字面值' },
    responseStatus = 200,
    matches = { { translation = '文字值' } },
  }),
  stderr = '',
})
assert(
  vim.wait(500, function()
    return rendered_text(query_bufnr):find('字面值', 1, true) ~= nil
  end),
  'translation response was not rendered in the query window'
)
assert(
  #vim.api.nvim_list_wins() == window_count_before_result,
  'translation result opened another window'
)
assert(
  vim.api.nvim_buf_get_lines(query_bufnr, 0, -1, false)[1] == '--literal | value',
  'translation result modified the query input'
)
local result_highlights = rendered_highlights(query_bufnr)
assert(result_highlights.TranslationSection, 'translation section heading is not styled')
assert(result_highlights.TranslationContent, 'translation content is not visually emphasized')

local next_request_index = #system_requests + 1
vim.api.nvim_buf_set_lines(query_bufnr, 0, -1, false, { '测试错误' })
vim.api.nvim_exec_autocmds('TextChangedI', { buffer = query_bufnr })
assert(vim.wait(translation.cold_time_ms + 300, function()
  return translation_request(next_request_index) ~= nil
end), 'second translation request was not started')
local failed_translation_request = translation_request(next_request_index)
failed_translation_request.callback({
  code = 35,
  signal = 0,
  stdout = '',
  stderr = 'curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL',
})
assert(vim.wait(500, function()
  return rendered_text(query_bufnr):find('curl: (35)', 1, true) ~= nil
end), 'curl failure was not rendered inside the translation window')
assert(
  rendered_highlights(query_bufnr).TranslationError,
  'translation failure does not use the error style'
)

vim.cmd('stopinsert')
vim.cmd('normal q')
assert(not vim.api.nvim_win_is_valid(query_winid), 'q did not close the translation query')
assert(failed_translation_request.process.killed, 'closing did not cancel translation process')

translation.open()
local insert_query_winid = vim.api.nvim_get_current_win()
local insert_close_mapping = vim.fn.maparg('<C-q>', 'i', false, true)
assert(type(insert_close_mapping.callback) == 'function', 'insert-mode close callback is missing')
insert_close_mapping.callback()
assert(
  not vim.api.nvim_win_is_valid(insert_query_winid),
  '<C-q> did not close the translation query'
)
assert(
  vim.api.nvim_get_mode().mode:sub(1, 1) ~= 'i',
  'closing the translation query preserved Insert mode'
)
vim.system = original_system
vim.env.http_proxy = previous_http_proxy
vim.env.https_proxy = previous_https_proxy
vim.env.ALL_PROXY = previous_all_proxy
