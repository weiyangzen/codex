# is_dangerous_command.rs 研究文档

## 场景与职责

`is_dangerous_command.rs` 是 Codex 项目中命令安全检测模块的核心组件，负责识别可能具有破坏性或不安全行为的 shell 命令。该模块的主要职责包括：

1. **危险命令检测**：识别可能导致数据丢失、系统损坏或安全风险的命令
2. **跨平台支持**：同时支持 Windows 和 Unix-like 系统的危险命令检测
3. **嵌套命令解析**：支持解析 `bash -lc "<script>"` 形式的嵌套命令
4. **Git 命令安全分析**：专门处理 Git 命令的子命令和全局选项，防止配置覆盖攻击

该模块被 `codex-rs/shell-command` crate 的公共 API 导出，供 TUI 和其他组件在决定是否自动批准命令执行前调用。

## 功能点目的

### 1. `command_might_be_dangerous` - 主入口函数

这是模块的主要入口点，接收命令参数列表（`&[String]`），返回布尔值表示命令是否可能危险。

**检测流程**：
1. Windows 平台：调用 `windows_dangerous_commands::is_dangerous_command_windows`
2. 直接危险命令检测：调用 `is_dangerous_to_call_with_exec`
3. 嵌套脚本解析：通过 `parse_shell_lc_plain_commands` 解析 `bash -lc` 形式的命令，递归检测其中每个子命令

### 2. `is_dangerous_to_call_with_exec` - 核心危险命令识别

目前识别的危险模式：

| 命令 | 危险条件 | 风险说明 |
|------|----------|----------|
| `rm` | 包含 `-f` 或 `-rf` 参数 | 强制删除文件，可能导致数据丢失 |
| `sudo` | 递归检查被调用的命令 | 特权提升后的命令执行 |

### 3. `find_git_subcommand` - Git 子命令定位

这是一个关键的辅助函数，用于在 Git 命令参数中定位特定的子命令，同时正确处理 Git 的全局选项。

**处理的全局选项**：
- `-C`, `-c`：配置覆盖（特别注意这是安全风险点）
- `--config-env`, `--exec-path`, `--git-dir`, `--namespace`, `--super-prefix`, `--work-tree`

**安全设计**：函数会跳过已知的全局选项，但如果遇到未知的非选项参数且不是目标子命令，会立即停止扫描。这防止了将分支名等位置参数误判为子命令。

### 4. `executable_name_lookup_key` - 可执行文件名规范化

跨平台的可执行文件名提取和规范化：

- **Windows**：提取文件名并转换为小写，去除 `.exe`, `.cmd`, `.bat`, `.com` 后缀
- **非 Windows**：仅提取文件名，保持原始大小写

## 具体技术实现

### 危险命令检测逻辑

```rust
fn is_dangerous_to_call_with_exec(command: &[String]) -> bool {
    let cmd0 = command.first().map(String::as_str);

    match cmd0 {
        Some("rm") => matches!(command.get(1).map(String::as_str), Some("-f" | "-rf")),
        Some("sudo") => is_dangerous_to_call_with_exec(&command[1..]),
        _ => false,
    }
}
```

**实现要点**：
- 使用模式匹配进行命令识别
- `sudo` 命令递归检查其后的命令
- 仅检查第一个参数是否为危险标志

### Git 全局选项处理

```rust
fn is_git_global_option_with_value(arg: &str) -> bool {
    matches!(arg, "-C" | "-c" | "--config-env" | "--exec-path" | ...)
}

fn is_git_global_option_with_inline_value(arg: &str) -> bool {
    matches!(arg, s if s.starts_with("--config-env=") || ...)
        || ((arg.starts_with("-C") || arg.starts_with("-c")) && arg.len() > 2)
}
```

**关键安全考虑**：
- `-c` 选项可以覆盖 Git 配置，如 `-c core.pager=cat`，可能被用于执行任意命令
- 函数区分了需要下一个参数的选项（如 `-C path`）和行内值选项（如 `-Cpath`）

### 嵌套命令解析

```rust
if let Some(all_commands) = parse_shell_lc_plain_commands(command)
    && all_commands
        .iter()
        .any(|cmd| is_dangerous_to_call_with_exec(cmd))
{
    return true;
}
```

通过 `bash.rs` 中的 `parse_shell_lc_plain_commands` 函数解析嵌套脚本，该函数使用 tree-sitter 进行 AST 解析，只允许特定的安全操作符（`&&`, `||`, `;`, `|`）。

## 关键代码路径与文件引用

### 当前文件内部依赖

```
is_dangerous_command.rs
├── command_might_be_dangerous() [入口]
│   ├── windows_dangerous_commands::is_dangerous_command_windows() [Windows]
│   ├── is_dangerous_to_call_with_exec() [Unix直接检测]
│   └── parse_shell_lc_plain_commands() [嵌套脚本]
│       └── is_dangerous_to_call_with_exec() [递归检测]
├── find_git_subcommand() [Git命令解析]
│   ├── executable_name_lookup_key()
│   ├── is_git_global_option_with_value()
│   └── is_git_global_option_with_inline_value()
└── executable_name_lookup_key() [文件名规范化]
```

### 跨文件依赖

| 依赖文件 | 依赖内容 | 用途 |
|----------|----------|------|
| `bash.rs` | `parse_shell_lc_plain_commands` | 解析 bash/zsh -lc 脚本 |
| `windows_dangerous_commands.rs` | `is_dangerous_command_windows` | Windows 平台危险命令检测 |

### 被调用方

- `lib.rs`：通过 `pub use command_safety::is_dangerous_command` 导出
- `is_safe_command.rs`：导入 `find_git_subcommand` 和 `executable_name_lookup_key`
- TUI 和 Exec 组件：通过公共 API 调用 `command_might_be_dangerous`

## 依赖与外部交互

### 外部 Crate 依赖

- `std::path::Path`：路径处理

### 内部模块依赖

```rust
use crate::bash::parse_shell_lc_plain_commands;
use std::path::Path;
#[cfg(windows)]
#[path = "windows_dangerous_commands.rs"]
mod windows_dangerous_commands;
```

### 条件编译

- `#[cfg(windows)]`：Windows 特定的危险命令检测模块
- Windows 模块使用 `#[path = "..."]` 属性指定模块路径

## 风险、边界与改进建议

### 当前风险与边界

1. **有限的危险命令覆盖**
   - 目前仅检测 `rm -f/rf` 和 `sudo` 递归
   - 不检测 `dd`, `mkfs`, `fdisk` 等其他危险命令
   - 不检测 `curl | sh` 等管道执行模式

2. **Git 安全检测的局限性**
   - 虽然能跳过全局选项，但 `-c` 配置覆盖的检测在 `is_safe_command.rs` 中
   - 某些 Git 子命令（如 `git clean -fd`）未被识别为危险

3. **嵌套脚本解析限制**
   - 依赖 `parse_shell_lc_plain_commands` 的解析能力
   - 复杂的 shell 结构（如子 shell、命令替换）会被拒绝解析

4. **平台差异**
   - Windows 和非 Windows 的可执行文件名处理不同
   - 某些危险模式可能只在特定平台被检测

### 改进建议

1. **扩展危险命令列表**
   ```rust
   // 建议添加的检测
   Some("dd") => // 检测 if/of 参数
   Some("mkfs") | Some("mkfs.ext4") => // 文件系统格式化
   Some("fdisk") => // 分区操作
   ```

2. **增强管道检测**
   - 检测 `curl | bash` 或 `wget | sh` 等模式
   - 识别网络下载后直接执行的管道

3. **统一平台处理**
   - 考虑统一 Windows 和非 Windows 的可执行文件名处理逻辑
   - 增加更多测试覆盖跨平台场景

4. **与 is_safe_command 的协调**
   - 当前 `is_dangerous_command` 和 `is_safe_command` 有重复逻辑
   - 考虑统一的安全评估框架

### 测试覆盖

当前测试仅覆盖：
- `rm -rf /` 检测
- `rm -f /` 检测

**建议增加的测试**：
- `sudo rm -rf` 递归检测
- 嵌套脚本中的危险命令
- Git 全局选项绕过尝试
- Windows 路径处理
