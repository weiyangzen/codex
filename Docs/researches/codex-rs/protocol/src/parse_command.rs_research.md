# parse_command.rs 研究文档

## 场景与职责

`parse_command.rs` 是 Codex 协议库中的命令解析类型定义模块，定义了用于解析和表示 shell 命令的结构化类型。这些类型用于在 TUI 和 App Server 中将用户执行的 shell 命令转换为结构化的元数据，以便更好地展示命令执行摘要。

**核心职责：**
- 定义解析后命令的枚举类型（ParsedCommand）
- 支持多种命令类型的识别：文件读取、文件列表、搜索
- 提供命令元数据的结构化表示

## 功能点目的

### 1. 命令解析结果枚举 (ParsedCommand)

**目的：** 将任意 shell 命令解析为结构化的元数据，用于 UI 展示执行摘要。

**变体定义：**

```rust
pub enum ParsedCommand {
    Read {
        cmd: String,        // 原始命令字符串
        name: String,       // 文件名（用于展示）
        path: PathBuf,      // 文件路径
    },
    ListFiles {
        cmd: String,
        path: Option<String>, // 目录路径（可选）
    },
    Search {
        cmd: String,
        query: Option<String>, // 搜索查询
        path: Option<String>,  // 搜索路径
    },
    Unknown {
        cmd: String,        // 无法解析时的原始命令
    },
}
```

### 2. 序列化支持

**目的：** 支持跨进程/网络传输解析结果。

**特性：**
- 使用 `#[serde(tag = "type", rename_all = "snake_case")]` 实现 tagged union
- 支持 JSON Schema 生成（`JsonSchema`）
- 支持 TypeScript 类型生成（`TS`）

## 具体技术实现

### 数据结构详解

#### ParsedCommand::Read

用于表示文件读取命令（如 `cat`, `head`, `tail`, `less`, `bat` 等）。

```rust
Read {
    cmd: String,    // 例如: "cat README.md"
    name: String,   // 例如: "README.md"
    path: PathBuf,  // 例如: "/home/user/project/README.md"
}
```

#### ParsedCommand::ListFiles

用于表示文件列表命令（如 `ls`, `rg --files`, `find` 等）。

```rust
ListFiles {
    cmd: String,           // 例如: "rg --files src"
    path: Option<String>,  // 例如: Some("src")
}
```

#### ParsedCommand::Search

用于表示搜索命令（如 `grep`, `rg`, `ag`, `ack` 等）。

```rust
Search {
    cmd: String,           // 例如: "rg TODO src"
    query: Option<String>, // 例如: Some("TODO")
    path: Option<String>,  // 例如: Some("src")
}
```

#### ParsedCommand::Unknown

用于表示无法识别或解析的命令。

```rust
Unknown {
    cmd: String,  // 原始命令字符串
}
```

### 序列化格式示例

**Read 变体：**
```json
{
    "type": "read",
    "cmd": "cat README.md",
    "name": "README.md",
    "path": "/home/user/project/README.md"
}
```

**Search 变体：**
```json
{
    "type": "search",
    "cmd": "rg TODO src",
    "query": "TODO",
    "path": "src"
}
```

**Unknown 变体：**
```json
{
    "type": "unknown",
    "cmd": "npm run build"
}
```

## 关键代码路径与文件引用

### 本文件完整代码

```rust
use schemars::JsonSchema;
use serde::Deserialize;
use serde::Serialize;
use std::path::PathBuf;
use ts_rs::TS;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ParsedCommand {
    Read {
        cmd: String,
        name: String,
        /// (Best effort) Path to the file being read by the command. When
        /// possible, this is an absolute path, though when relative, it should
        /// be resolved against the `cwd`` that will be used to run the command
        /// to derive the absolute path.
        path: PathBuf,
    },
    ListFiles {
        cmd: String,
        path: Option<String>,
    },
    Search {
        cmd: String,
        query: Option<String>,
        path: Option<String>,
    },
    Unknown {
        cmd: String,
    },
}
```

### 调用方（实际解析实现）

**主要实现位于：** `codex-rs/shell-command/src/parse_command.rs`

该文件包含完整的命令解析逻辑：
- Bash/Zsh 命令解析
- PowerShell 命令解析
- 管道和连接符处理（`&&`, `||`, `|`, `;`）
- 多种命令类型的识别逻辑

### 使用方

| 文件 | 用途 |
|------|------|
| `protocol.rs` | 导入并重新导出 |
| `exec/src/event_processor_with_human_output.rs` | 事件处理器输出 |
| `tui/src/exec_cell/render.rs` | TUI 执行单元渲染 |
| `tui_app_server/src/exec_cell/render.rs` | App Server 执行单元渲染 |
| `tui/src/history_cell.rs` | 历史记录展示 |
| `tui_app_server/src/history_cell.rs` | App Server 历史记录 |
| `core/src/tools/handlers/unified_exec.rs` | 统一执行工具 |
| `core/src/tools/context.rs` | 工具上下文 |

### 导入路径

```rust
// protocol.rs 中导入
use crate::parse_command::ParsedCommand;

// 外部 crate 使用
use codex_protocol::parse_command::ParsedCommand;
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `ts_rs` | TypeScript 类型生成 |
| `std::path::PathBuf` | 路径表示 |

### 与其他模块的关系

```
parse_command.rs (类型定义)
    ↑
    │ 使用
    │
shell-command/src/parse_command.rs (解析实现)
    │ 生成
    ↓
ParsedCommand 实例
    │ 通过 EventMsg 传递
    ↓
tui/src/exec_cell/render.rs (UI 展示)
```

## 风险、边界与改进建议

### 已知风险

1. **类型与实现分离**
   - 风险：类型定义在 `protocol`，解析实现在 `shell-command`
   - 可能导致版本不一致
   - 缓解：两个 crate 通常一起发布

2. **路径解析依赖外部上下文**
   - 风险：`Read.path` 可能是相对路径，需要结合 `cwd` 解析
   - 文档已说明这一点，但调用方可能忽略

3. **Unknown 变体信息丢失**
   - 风险：无法解析的命令只保留原始字符串，丢失结构化信息
   - 影响：UI 只能显示原始命令，无法提供增强展示

### 边界条件

| 场景 | 行为 |
|------|------|
| 空命令 | 通常由调用方处理，不创建 ParsedCommand |
| 复杂管道 | 解析为多个 ParsedCommand 或 Unknown |
| 相对路径 | 保留原样，由调用方结合 cwd 解析 |
| 包含特殊字符 | 保留在 cmd 字段中 |

### 改进建议

1. **添加更多命令类型**
   - 当前只有 Read/ListFiles/Search/Unknown
   - 可考虑添加：Write（写入文件）、Delete（删除）、Git（Git 操作）等

2. **增强路径处理**
   - 考虑添加 `cwd` 字段到 Read 变体
   - 或提供辅助方法将相对路径转为绝对路径

3. **命令复杂度评估**
   - 添加 `is_complex()` 方法判断命令是否涉及多个操作
   - 帮助 UI 决定是否展示详细摘要

4. **安全标记**
   - 添加 `is_potentially_destructive()` 方法
   - 帮助 UI 标记可能危险的命令

5. **性能优化**
   - 当前使用 `String` 和 `PathBuf`，克隆成本较高
   - 考虑使用 `Arc<str>` 或 `Arc<Path>` 如果大量克隆

### 测试建议

当前此文件无测试（仅类型定义），测试主要在 `shell-command/src/parse_command.rs`。

建议添加：
- 序列化/反序列化一致性测试
- JSON Schema 有效性测试
- TypeScript 类型生成测试
