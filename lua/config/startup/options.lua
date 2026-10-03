vim.opt.background = "dark"
vim.opt.termguicolors = true
-- The project dashboard owns the welcome screen; do not flash Neovim's intro
-- while its UIEnter callback is preparing the homepage.
vim.opt.shortmess:append("I")
vim.opt.clipboard = "unnamedplus"
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.number = true
-- Keep diagnostic signs close to line numbers; grow the gutter for larger files.
vim.opt.numberwidth = 2
vim.opt.cursorline = true
vim.opt.signcolumn = "auto"
vim.opt.colorcolumn = "160"
-- Git layouts use separate tabs internally; hide the native Scratch/file tab bar.
vim.opt.showtabline = 0

vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.shiftround = true
vim.opt.autoindent = true
vim.opt.smartindent = true

vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.cmdheight = 1
vim.opt.wrap = false
vim.opt.hidden = true
vim.opt.pumheight = 10
vim.opt.autoread = true

vim.opt.guifont = "Hack Nerd Font:h14"

-- A tmux pane may predate an SSH attachment and still inherit desktop display
-- variables. Let tmux reach the attached terminal instead of that desktop.
-- Outside tmux, local sessions retain the native provider and SSH uses OSC 52.
if vim.env.TMUX and vim.fn.executable("tmux") == 1 then
  vim.g.clipboard = "tmux"
elseif vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
      ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
    },
    paste = {
      ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
      ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
    },
  }
end

-- Use Treesitter syntax nodes as fold boundaries. Keep files expanded when
-- they are opened; folds are created only when requested by the user.
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.require'config.syntax.folds'.expression()"
vim.opt.foldenable = true
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.foldcolumn = "0"
