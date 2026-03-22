# ParsedCommand.ts Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`ParsedCommand` 用于表示解析后的命令结构，将用户输入的命令分类为特定的操作类型（如读取文件、列出文件、搜索等）。

**使用场景：**
- 执行审批流程中解析用户命令，提供结构化的命令信息
- 安全分析中识别命令的意图和潜在风险
- UI 显示中提供命令的友好描述

**职责：**
- 将原始命令字符串解析为结构化的命令类型
- 提取命令的关键参数（如文件路径、搜索查询等）
- 支持多种常见命令类型的解析

## 2. 功能点目的 (Purpose of This Type)

该类型的主要目的是：

1. **命令理解**：帮助系统理解用户命令的意图
2. **安全分析**：基于命令类型和参数进行风险评估
3. **UI 优化**：为用户提供命令的结构化视图

**命令类型：**
- `read`：读取文件内容
  - `cmd`：原始命令字符串
  - `name`：命令名称
  - `path`：文件路径（尽可能为绝对路径）
- `list_files`：列出目录内容
  - `cmd`：原始命令字符串
  - `path`：目录路径（可选）
- `search`：搜索文件或内容
  - `cmd`：原始命令字符串
  - `query`：搜索查询（可选）
  - `path`：搜索路径（可选）
- `unknown`：无法识别的命令
  - `cmd`：原始命令字符串

## 3. 具体技术实现 (Technical Implementation Details)

**Rust 定义**（位于 `codex-rs/protocol/src/parse_command.rs`）：

```rust
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

**TypeScript 生成定义：**

```typescript
export type ParsedCommand = { "type": "read", cmd: string, name: string, 
/**
 * (Best effort) Path to the file being read by the command. When
 * possible, this is an absolute path, though when relative, it should
 * be resolved against the `cwd`` that will be used to run the command
 * to derive the absolute path.
 */
path: string, } | { "type": "list_files", cmd: string, path: string | null, } | { "type": "search", cmd: string, query: string | null, path: string | null, } | { "type": "unknown", cmd: string, };
```

**关键实现细节：**
- 使用 `#[serde(tag = "type")]` 实现 tagged union 序列化
- `Read` 命令使用 `PathBuf` 表示路径
- 其他命令使用 `Option<String>` 表示可选参数

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Rust 源文件：**
- `/home/sansha/Github/codex/codex-rs/protocol/src/parse_command.rs`：主要定义

**TypeScript 生成文件：**
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/ParsedCommand.ts`

**使用位置：**
- `ExecApprovalRequestEvent.parsed_cmd` 字段（approvals.rs 第 195 行）
- 在 `default_available_decisions` 方法中可能用于决策逻辑

**相关类型：**
- `ExecApprovalRequestEvent`：包含解析后的命令列表

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**依赖 crate：**
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成
- `std::path::PathBuf`：路径处理

**序列化格式：**
- 使用 tagged union 格式，例如：
  ```json
  { "type": "read", "cmd": "cat file.txt", "name": "cat", "path": "/path/to/file.txt" }
  ```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

**潜在风险：**
1. **解析不准确**：命令解析是"尽力而为"的，可能不准确
2. **路径解析**：相对路径需要结合 `cwd` 解析，可能出错
3. **命令注入**：解析器需要小心处理特殊字符和注入攻击

**边界情况：**
1. 复杂命令：管道、重定向等复杂命令可能被归类为 `unknown`
2. 多文件操作：当前 `read` 只支持单文件

**改进建议：**
1. **添加更多命令类型**：如 `write`、`delete`、`execute` 等
2. **支持复杂命令**：解析管道和重定向
3. **参数提取**：提取更多命令行参数（如 `grep` 的选项）
4. **风险评分**：为每种命令类型添加风险评分
5. **命令链**：支持解析命令链（如 `cmd1 && cmd2`）
6. **沙箱影响分析**：分析命令对沙箱的影响（如哪些文件被访问）
