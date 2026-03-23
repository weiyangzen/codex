# mod.rs 研究文档

## 场景与职责

`mod.rs` 是 `command_safety` 模块的入口文件，负责组织和导出子模块。该模块是 Codex 项目中命令安全检测的核心组件，为 TUI 和其他组件提供统一的命令安全评估接口。

## 功能点目的

该文件非常简单，仅包含三个 `pub mod` 声明：

1. **`is_dangerous_command`**：危险命令检测模块
   - 导出 `command_might_be_dangerous` 函数
   - 用于识别可能导致数据丢失或系统损坏的命令

2. **`is_safe_command`**：安全命令白名单模块
   - 导出 `is_known_safe_command` 函数
   - 用于识别已知安全的、可以自动批准的命令

3. **`windows_safe_commands`**：Windows 安全命令模块
   - 提供 Windows 平台特定的安全命令检测
   - 被 `is_safe_command` 内部使用

## 具体技术实现

### 模块导出结构

```rust
pub mod is_dangerous_command;
pub mod is_safe_command;
pub mod windows_safe_commands;
```

### 模块组织

```
command_safety/
├── mod.rs                    # 模块入口（当前文件）
├── is_dangerous_command.rs   # 危险命令检测
├── is_safe_command.rs        # 安全命令白名单
├── windows_dangerous_commands.rs  # Windows 危险命令（条件编译）
├── windows_safe_commands.rs  # Windows 安全命令
└── powershell_parser.ps1     # PowerShell 解析脚本
```

## 关键代码路径与文件引用

### 父模块引用

在 `lib.rs` 中：

```rust
pub mod command_safety;
pub use command_safety::is_dangerous_command;
pub use command_safety::is_safe_command;
```

### 模块间依赖

```
mod.rs
├── is_dangerous_command.rs
│   └── [Windows] windows_dangerous_commands.rs
├── is_safe_command.rs
│   ├── is_dangerous_command.rs (导入 find_git_subcommand)
│   └── windows_safe_commands.rs
└── windows_safe_commands.rs
    └── powershell_parser.ps1 (内嵌脚本)
```

## 依赖与外部交互

### 无直接依赖

该文件本身不导入任何外部 crate 或内部模块，仅作为模块组织文件。

### 子模块依赖

各子模块的依赖关系：

| 子模块 | 依赖 |
|--------|------|
| `is_dangerous_command` | `bash.rs`, `windows_dangerous_commands.rs` |
| `is_safe_command` | `bash.rs`, `is_dangerous_command.rs`, `windows_safe_commands.rs` |
| `windows_safe_commands` | `powershell_parser.ps1` (内嵌) |

## 风险、边界与改进建议

### 当前设计分析

**优点**：
- 模块职责清晰，分离危险检测和安全白名单
- 平台特定代码隔离（Windows 模块）
- 公共 API 简洁明确

**潜在问题**：
- `windows_safe_commands` 被直接导出，但主要是内部使用
- 模块间的循环依赖风险（`is_safe_command` 导入 `is_dangerous_command`）

### 改进建议

1. **重新考虑导出级别**
   ```rust
   // 当前
   pub mod windows_safe_commands;
   
   // 建议：如果主要是内部使用
   pub(crate) mod windows_safe_commands;
   ```

2. **添加模块文档**
   ```rust
   //! 命令安全检测模块
   //!
   //! 提供两类安全评估：
   //! - 危险命令检测：识别可能导致损害的命令
   //! - 安全命令白名单：识别已知安全的命令
   ```

3. **考虑统一接口**
   ```rust
   // 建议添加统一的安全评估入口
   pub enum SafetyStatus {
       KnownSafe,
       KnownDangerous,
       Unknown,
   }
   
   pub fn evaluate_safety(command: &[String]) -> SafetyStatus {
       if is_dangerous_command::command_might_be_dangerous(command) {
           return SafetyStatus::KnownDangerous;
       }
       if is_safe_command::is_known_safe_command(command) {
           return SafetyStatus::KnownSafe;
       }
       SafetyStatus::Unknown
   }
   ```

### 模块边界

当前模块边界清晰，但需要注意：

1. **`is_dangerous_command` 和 `is_safe_command` 的关系**
   - 两者是独立的判断
   - 一个命令可能既不是危险的也不是已知安全的（Unknown 状态）
   - 不存在既是危险又是安全的情况（逻辑上）

2. **Windows 模块的特殊性**
   - `windows_dangerous_commands.rs` 使用条件编译 `#[cfg(windows)]`
   - `windows_safe_commands.rs` 始终存在，但内部有平台特定逻辑
