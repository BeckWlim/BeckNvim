# Neovim 配置

一套面向日常开发的个人 Neovim 配置。使用 [lazy.nvim](https://github.com/folke/lazy.nvim)
管理插件，内置代码补全、LSP、模糊搜索、Git 状态、终端、文件树和 Markdown 渲染。

## 环境要求

- Neovim 0.11 或更高版本
- Git
- [ripgrep](https://github.com/BurntSushi/ripgrep)（Telescope 全文搜索）
- `make` 和 C 编译器（编译 `telescope-fzf-native.nvim`）
- Nerd Font（可选，用于完整显示图标；GUI 默认使用 Hack Nerd Font）

LSP 服务器由 Mason 在首次启动后按需安装。目前配置了 Bash、C/C++、Lua、
Markdown、Python 和 Vim script 支持。

## 安装

先备份已有配置，再克隆本仓库：

```bash
mv ~/.config/nvim ~/.config/nvim.bak
git clone <repository-url> ~/.config/nvim
nvim
```

首次启动时 lazy.nvim 会自动下载插件。随后可在 Neovim 中运行：

```vim
:Lazy check
:Mason
:checkhealth
```

插件版本由 `lazy-lock.json` 锁定。使用 `:Lazy update` 更新后，请一并提交新的锁文件。

## 目录结构

```text
init.lua                  启动入口
lua/config/lazy.lua       lazy.nvim 引导与插件加载
lua/config/options.lua    通用编辑器选项
lua/config/keybindings.lua 全局按键映射
lua/plugins/              按功能拆分的插件配置
lazy-lock.json            插件版本锁文件
```

## 常用按键

Leader 键使用 Neovim 默认值 `\\`。下表中的 `<Space>` 是实际的空格键前缀，
不是 Leader 键。

### 窗口与跳转

| 按键 | 功能 |
| --- | --- |
| `<Space>w i/j/k/l` | 切换到上/左/下/右窗口 |
| `<Space>w v/s` | 垂直/水平分屏 |
| `<Space>w q/o` | 关闭当前窗口/仅保留当前窗口 |
| `<Tab>` / `<S-Tab>` | 下一个/上一个窗口 |
| `<Space>r i/k/j/l` | 增高/降低/变窄/变宽窗口 |
| `<Space>r =` | 均分窗口 |
| `<Space>o` / `<Space>p` | 跳转列表后退/前进 |
| `<Space>z z/c/o` | 切换折叠/关闭全部/打开全部折叠 |

### 搜索

| 按键 | 功能 |
| --- | --- |
| `<Space>f f` | 搜索项目文件 |
| `<Space>f v` | 搜索文件并垂直分屏打开 |
| `<Space>f g` | 全文搜索 |
| `<Space>f b` | 搜索已打开的 buffer |
| `<Space>b v` | 搜索 buffer 并垂直分屏打开 |
| `<Space>f r` | 搜索最近文件 |
| `<Space>f h` | 搜索帮助文档 |
| `<Space>f k` | 搜索按键映射 |
| `<Space>f s` | 搜索当前文件符号 |
| `<Space>f w` | 搜索项目符号 |

Telescope 搜索结果中可用 `<C-v>` 垂直分屏、`<C-x>` 水平分屏打开。

### LSP 与诊断

| 按键 | 功能 |
| --- | --- |
| `gd` / `gD` | 跳转到定义/声明 |
| `gr` / `gI` | 查找引用/跳转到实现 |
| `K` | 显示悬浮文档 |
| `<Space>i` | 跳转到实现 |
| `<Space>D` | 跳转到类型定义 |
| `<Space>rn` | 重命名符号 |
| `<Space>e` | 显示诊断详情 |
| `[d` / `]d` | 上一个/下一个诊断 |
| `<Space>q` | 打开诊断列表 |
| `<Space>lp` | 切换 BasedPyright 第三方依赖诊断 |

`<Space>gf`、`<Space>gv` 和 `<Space>gx` 用于在当前窗口、垂直分屏或水平分屏中
跳转到 C/C++ `#include`、Python `import`、Lua `require` 引用的文件。

### 工具

| 按键 | 功能 |
| --- | --- |
| `<F3>` | 切换文件树 |
| `<C-t>` | 切换水平终端 |
| `<M-e>` | 快速包围 |
| `<Space>mp` | 切换 Markdown 渲染 |
| `<Space>dv` | 打开当前分支 Diffview |
| `<Space>dvm` | 与 `main` 分支比较 |
| `<Space>dvh` | 查看当前文件历史 |
| `<Space>dvc` | 关闭 Diffview |
| `gcc` / `gc` | 注释当前行/选中区域 |

## 个性化

- 主题和补全菜单颜色：`lua/plugins/theme.lua`
- 缩进、剪贴板和显示选项：`lua/config/options.lua`
- LSP 与补全：`lua/plugins/lsp.lua`
- 搜索和代码编辑插件：`lua/plugins/coding.lua`

配置默认通过 OSC 52 与系统剪贴板交互，适合 SSH 和远程终端场景。
