vim.opt.background = "dark"
vim.opt.clipboard = "unnamedplus"
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.number = true
vim.opt.cursorline = true
vim.opt.signcolumn = "yes"
vim.opt.colorcolumn = "160"

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

-- Let local sessions use the native clipboard provider. Sending every yank
-- through OSC 52 makes large visual selections noticeably slower because the
-- text has to be encoded and handled by the terminal. Remote sessions still
-- need OSC 52 so their clipboard reaches the local terminal.
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
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
vim.opt.foldexpr = "v:lua.require'config.folds'.expression()"
vim.opt.foldenable = true
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.foldcolumn = "0"
