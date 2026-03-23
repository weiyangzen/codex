# lib.rs 深度研究文档

## 场景与职责

`lib.rs` 是 `codex-shell-command` crate 的库入口文件，负责模块组织和公共 API 暴露。该 crate 的核心定位是：

> **Command parsing and safety utilities shared across Codex crates.**
> （跨 Codex crate 共享的命令解析和安全工具）

作为共享库，它为多个下游 crate 提供统一的命令解析和安全检测能力，包括：
- `codex-core`：核心执行逻辑
- `codex-tui`：终端用户界面
- `codex-tui-app-server`：TUI 应用服务器

## 功能点目的

### 模块组织

| 模块 | 可见性 | 用途 |
|------|--------|------|
| `shell_detect` | private (`mod`) | Shell 类型检测（bash/zsh/powershell 等） |
| `bash` | public (`pub mod`) | Bash/Zsh 脚本解析和安全验证 |
| `command_safety` | public (`pub mod`) | 命令安全检测（危险/安全命令判断） |
| `parse_command` | public (`pub mod`) | 通用命令解析和元数据提取 |
| `powershell` | public (`pub mod`) | PowerShell 命令处理 |

### 公共 API 暴露

```rust
pub use command_safety::is_dangerous_command;
pub use command_safety::is_safe_command;
```

这两个函数是 crate 的主要公共接口：
- `is_dangerous_command`：检测命令是否可能具有破坏性（如 `rm -rf`）
- `is_safe_command`：检测命令是否已知安全（如 `ls`, `git status`）

## 具体技术实现

### 代码结构

```rust
//! Command parsing and safety utilities shared across Codex crates.

mod shell_detect;

pub mod bash;
pub mod command_safety;
pub mod parse_command;
pub mod powershell;

pub use command_safety::is_dangerous_command;
pub use command_safety::is_safe_command;
```

### 设计决策

1. **shell_detect 为私有模块**：
   - 内部实现细节，不对外暴露
   - 通过 `bash` 和 `powershell` 模块的公共函数间接使用

2. **command_safety 函数重导出**：
   - 简化调用方的使用方式
   - 调用方只需 `use codex_shell_command::is_safe_command`
   - 无需深入了解内部模块结构

3. **模块级可见性控制**：
   - `pub mod` 允许外部访问子模块的公共项
   - 细粒度的 API 控制，既提供灵活性又保持封装

## 关键代码路径与文件引用

### 模块依赖图

```
lib.rs
├── shell_detect (private)
│   └── ShellType, detect_shell_type
├── bash (public)
│   ├── try_parse_shell
│   ├── try_parse_word_only_commands_sequence
│   ├── extract_bash_command
│   ├── parse_shell_lc_plain_commands
│   └── parse_shell_lc_single_command_prefix
├── command_safety (public)
│   ├── is_dangerous_command (re-exported)
│   └── is_safe_command (re-exported)
├── parse_command (public)
│   ├── parse_command
│   ├── shlex_join
│   └── extract_shell_command
└── powershell (public)
    ├── extract_powershell_command
    └── prefix_powershell_script_with_utf8
```

### 下游使用者

| Crate | 使用方式 | 主要用途 |
|-------|---------|---------|
| `codex-core` | `use codex_shell_command::bash::...` | 执行策略、命令规范化、权限提升 |
| `codex-tui` | `use codex_shell_command::bash::extract_bash_command` | 执行单元格渲染 |
| `codex-tui-app-server` | `use codex_shell_command::bash::extract_bash_command` | 执行单元格渲染 |

## 依赖与外部交互

### Cargo.toml 依赖

```toml
[dependencies]
base64 = { workspace = true }
codex-protocol = { workspace = true }
codex-utils-absolute-path = { workspace = true }
once_cell = { workspace = true }
regex = { workspace = true }
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
shlex = { workspace = true }
tree-sitter = { workspace = true }
tree-sitter-bash = { workspace = true }
url = { workspace = true }
which = { workspace = true }
```

### 关键外部依赖说明

| 依赖 | 用途 |
|------|------|
| `tree-sitter` + `tree-sitter-bash` | Bash 脚本解析 |
| `shlex` | Shell 风格的词法分割和连接 |
| `codex-protocol` | `ParsedCommand` 等协议类型 |
| `which` | 可执行文件路径查找 |

## 风险、边界与改进建议

### 当前限制

1. **API 表面相对简单**：
   - 只重导出两个主要函数
   - 复杂用例需要直接访问子模块

2. **模块耦合**：
   - `bash` 和 `powershell` 模块有相似的函数签名
   - 但没有统一的 trait 或接口抽象

### 改进建议

1. **统一接口抽象**：
   ```rust
   // 可能的改进：定义统一的 ShellCommandParser trait
   pub trait ShellCommandParser {
       fn extract_script(&self, command: &[String]) -> Option<(&str, &str)>;
       fn parse_safe_commands(&self, command: &[String]) -> Option<Vec<Vec<String>>>;
   }
   ```

2. **增加更多便捷函数**：
   - 考虑重导出更多常用函数到 crate 根
   - 如 `parse_command::parse_command`, `bash::extract_bash_command` 等

3. **文档完善**：
   - 在 lib.rs 增加模块级文档说明
   - 提供使用示例和最佳实践

4. **错误处理改进**：
   - 当前许多函数返回 `Option`，考虑使用 `Result` 提供更详细的错误信息

### 维护注意事项

1. **新增模块时**：
   - 考虑是否应公开（`pub mod`）或私有（`mod`）
   - 评估是否需要重导出到 crate 根

2. **API 兼容性**：
   - `is_dangerous_command` 和 `is_safe_command` 是公共 API
   - 修改签名时需要考虑下游 crate 的兼容性
