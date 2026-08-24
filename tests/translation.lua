local translation_spec_path = vim.fs.joinpath(
  vim.fn.getcwd(),
  'lua',
  'plugins',
  'translation.lua'
)
local translation_spec_chunk, translation_spec_load_error = loadfile(translation_spec_path)
assert(translation_spec_chunk, translation_spec_load_error)

local plugin_specs = translation_spec_chunk()
local translation_spec = plugin_specs[1]
local translation = require('config.translation')
local translation_options = translation.options()

assert(
  translation_spec[1] == 'askfiy/smart-translate.nvim',
  'translation plugin declaration changed unexpectedly'
)
assert(
  translation_spec.dependencies[1] == 'askfiy/http.nvim',
  'translation HTTP dependency is missing'
)
assert(
  translation_options.default.cmds.target == 'zh-CN',
  'translation target is not Simplified Chinese'
)
assert(
  translation_options.default.cmds.handle == 'query-panel',
  'translation result is not configured in the query panel'
)

local normal_mapping = translation_spec.keys[1]
assert(
  normal_mapping[1] == '<Space>t' and type(normal_mapping[2]) == 'function',
  'free-form translation mapping is missing'
)
assert(
  #translation_spec.keys == 1 and normal_mapping.mode == 'n',
  'translation must use only the free-form query mapping'
)

local original_translate_command = vim.cmd.Translate
local captured_command
vim.cmd.Translate = function(command_options)
  captured_command = command_options
end

assert(translation.target_for('hello world') == 'zh-CN', 'English target is not Chinese')
assert(translation.target_for('你好，world') == 'en', 'Chinese target is not English')
assert(translation.cold_time_ms == 700, 'translation debounce delay changed')

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
  vim.tbl_contains(chinese_dictionary_lines, '[动词] 测量试验'),
  'Chinese detailed meaning was not rendered'
)
assert(
  vim.tbl_contains(chinese_dictionary_lines, '例：进行测试'),
  'Chinese example markup was not cleaned before rendering'
)

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
assert(
  vim.fn.maparg('q', 'n', false, true).desc == 'Close translation query',
  'translation query close mapping is missing'
)
assert(
  vim.fn.maparg('<C-q>', 'i', false, true).desc == 'Close translation query',
  'translation query insert-mode close mapping is missing'
)

vim.api.nvim_buf_set_lines(query_bufnr, 0, -1, false, { '--literal | value' })
vim.api.nvim_exec_autocmds('TextChangedI', { buffer = query_bufnr })
assert(
  vim.wait(translation.cold_time_ms + 300, function()
    return captured_command ~= nil
  end),
  'translation was not requested after the debounce delay'
)
assert(
  captured_command.args[1] == '--target=zh-CN'
    and captured_command.args[2] == ' --literal | value',
  'translation query did not preserve arbitrary input'
)

local window_count_before_result = #vim.api.nvim_list_wins()
translation.render({
  original = { captured_command.args[2] },
  translation = { '字面值' },
})
assert(
  #vim.api.nvim_list_wins() == window_count_before_result,
  'translation result opened another window'
)
assert(
  vim.api.nvim_buf_get_lines(query_bufnr, 0, -1, false)[1] == '--literal | value',
  'translation result modified the query input'
)

vim.cmd.Translate = original_translate_command
vim.cmd('stopinsert')
vim.cmd('normal q')
assert(not vim.api.nvim_win_is_valid(query_winid), 'q did not close the translation query')

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
