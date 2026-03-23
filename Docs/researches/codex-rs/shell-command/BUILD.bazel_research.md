# codex-rs/shell-command/BUILD.bazel 研究文档

## 场景与职责

该 BUILD.bazel 文件是 Bazel 构建系统对 `codex-shell-command` crate 的构建配置。该 crate 是 Codex 项目中负责**命令解析与安全检查**的核心基础库，为整个系统提供跨平台的 shell 命令解析、危险性评估和安全白名单验证能力。

## 功能点目的

### 1. 构建目标定义
- **crate 名称**: `codex-shell-command` (Rust 内部使用 `codex_shell_command` 命名空间)
- **构建规则**: 使用项目自定义的 `codex_rust_crate` 宏（定义于 `//:defs.bzl`）
- **用途**: 统一封装 shell 命令解析与安全检查功能，供其他 crate 依赖

### 2. 编译时数据依赖
```bazel
compile_data = ["src/command_safety/powershell_parser.ps1"]
```
该配置将 PowerShell 解析脚本嵌入编译产物，用于 Windows 平台的 PowerShell 命令 AST 解析。

## 具体技术实现

### 关键流程

```
Bazel 构建流程:
1. 调用 codex_rust_crate 宏
2. 编译 Rust 源码 (src/*.rs)
3. 嵌入 compile_data 资源文件
4. 生成 codex_shell_command crate
```

### 数据结构

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `name` | `"shell-command"` | Bazel 目标名 |
| `crate_name` | `"codex_shell_command"` | Rust crate 名 |
| `compile_data` | `["src/command_safety/powershell_parser.ps1"]` | 编译时嵌入文件 |

## 关键代码路径与文件引用

### 本文件路径
- `codex-rs/shell-command/BUILD.bazel`

### 依赖的构建定义
- `//:defs.bzl` - 项目级 Rust crate 构建宏

### 引用的资源文件
- `src/command_safety/powershell_parser.ps1` - PowerShell AST 解析脚本

### 源码结构（同目录）
```
codex-rs/shell-command/src/
├── lib.rs                    # 库入口，导出公共模块
├── bash.rs                   # Bash 脚本解析（tree-sitter）
├── powershell.rs             # PowerShell 命令处理
├── shell_detect.rs           # Shell 类型检测
├── parse_command.rs          # 命令解析主逻辑
└── command_safety/
    ├── mod.rs                # 安全模块入口
    ├── is_dangerous_command.rs   # 危险命令检测
    ├── is_safe_command.rs        # 安全命令白名单
    ├── windows_dangerous_commands.rs  # Windows 危险命令
    ├── windows_safe_commands.rs       # Windows 安全命令
    └── powershell_parser.ps1        # PowerShell 解析脚本
```

## 依赖与外部交互

### 上游依赖（由 Cargo.toml 定义）
| crate | 用途 |
|-------|------|
| `tree-sitter` + `tree-sitter-bash` | Bash 脚本 AST 解析 |
| `shlex` | Shell 词法分析 |
| `regex` | 正则匹配 |
| `serde` + `serde_json` | 序列化 |
| `which` | 可执行文件查找 |
| `codex-protocol` | 协议类型定义（ParsedCommand） |
| `codex-utils-absolute-path` | 绝对路径处理 |

### 下游调用方
- `codex-core` - 核心执行逻辑，调用 `is_known_safe_command()` 和 `parse_command()`
- `codex-tui` / `codex-tui_app_server` - UI 层命令展示
- `codex-mcp-server` - MCP 工具执行

## 风险、边界与改进建议

### 风险点

1. **PowerShell 解析脚本嵌入**
   - `powershell_parser.ps1` 必须在编译时可用
   - 若文件缺失，Bazel 构建会失败
   - **缓解**: 文件已纳入 `compile_data`，确保打包

2. **跨平台兼容性**
   - Windows 安全检测逻辑与 Unix 差异较大
   - 部分代码使用 `#[cfg(windows)]` / `#[cfg(unix)]` 条件编译
   - **风险**: 非 Windows 平台无法测试 Windows 专用逻辑

### 边界情况

1. **tree-sitter 解析限制**
   - Bash 解析依赖 tree-sitter-bash，复杂脚本可能解析失败
   - 解析失败时保守地标记为 Unknown

2. **PowerShell 版本差异**
   - 支持 `powershell.exe` (v5.1) 和 `pwsh.exe` (v6+)
   - AST 解析行为可能因版本而异

### 改进建议

1. **构建优化**
   ```bazel
   # 可考虑添加 rustfmt 检查
   # 或集成 clippy lint 规则
   ```

2. **测试覆盖**
   - 当前测试主要在内联 `#[cfg(test)]` 模块
   - 建议添加集成测试验证完整解析流程

3. **文档完善**
   - 建议为 `compile_data` 的用途添加注释
   - 说明 PowerShell 脚本的嵌入目的

4. **安全策略**
   - 安全白名单（is_safe_command.rs）需要定期审计
   - 建议与安全团队建立 review 流程
