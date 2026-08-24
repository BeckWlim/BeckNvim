# 配置架构

配置按装配层、功能层和插件声明层分离：

```text
init.lua
  └─ config/init.lua
      ├─ options.lua       纯编辑器选项
      ├─ autocmds.lua      全局事件
      ├─ lazy.lua          插件管理器引导
      └─ keybindings.lua   全局按键装配

plugins/*.lua              插件依赖、加载条件和简单 opts
config/*.lua               可复用、可测试的功能实现
```

## 边界

- `plugins/` 不实现项目扫描、LSP 状态机或复杂 UI，只声明插件并调用对应的
  `config` 模块。
- `config/project.lua` 是项目根目录、路径包含关系和项目类型判断的唯一来源。
- `config/workspace_symbols.lua` 是项目符号 provider 的调度器。
  Python provider 位于 `config/python_symbols.lua`；未命中 provider 时回退到 LSP。
- `config/lsp.lua` 只管理服务器能力和设置；Python 环境解析位于
  `config/python_environment.lua`。
- `config/project_audit.lua` 和 `config/diagnostic_audit.lua` 分别处理批量扫描与
  Neovim 诊断缓存，两者共享项目上下文但不互相拥有状态。

## 扩展

新增插件时，在 `plugins/` 中添加声明；复杂配置放入同名或职责明确的
`config` 模块。新增项目符号后端时，向 `config.workspace_symbols` 注册包含
`supports(root, bufnr)` 和 `open(root, bufnr)` 的 provider。

新增项目类型或通用根目录 marker 时，只修改 `config/project.lua`。LSP server
仍保留自己的语言专属 markers：basedpyright 和 clangd 在 `config/lsp.lua` 中显式
配置，其余由 nvim-lspconfig 提供并由 mason-lspconfig 自动启用。新增 LSP 时，
只修改 `config/lsp.lua` 和 Mason 的安装列表。

## 验证

核心测试不加载完整配置或插件：

```bash
nvim --headless -u NONE -i NONE -l tests/run.lua
```

静态检查使用仓库根目录的 `.luarc.json`。完整启动检查应额外验证关键映射以及
`:checkhealth`，涉及真实语言服务器的功能应在目标项目上执行端到端查询。
