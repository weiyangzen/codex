# CommandExecResponse 研究报告

## 1. 场景与职责

### 使用场景
`CommandExecResponse` 是 app-server-protocol v2 API 中用于返回独立命令执行最终结果的核心响应结构。它在命令执行完成后发送给客户端，适用于以下场景：

- **一次性命令执行**：获取命令的退出码和输出结果
- **批处理任务**：执行脚本或批处理命令并收集结果
- **构建和测试**：运行编译、测试套件并获取输出
- **文件操作**：通过命令行工具执行文件操作并验证结果
- **非流式执行**：当不需要实时输出时，使用缓冲模式执行命令

### 核心职责
1. **结果传递**：提供命令的退出码（exit code）
2. **输出收集**：返回 stdout 和 stderr 的完整输出
3. **执行完成信号**：标记命令执行生命周期的结束
4. **与流式模式配合**：在流式模式下，stdout/stderr 为空（已通过通知发送）

## 2. 功能点目的

### 设计目标
- **完整性**：提供命令执行的所有关键结果信息
- **灵活性**：支持缓冲模式和流式模式两种使用方式
- **兼容性**：与标准 Unix 进程退出语义保持一致
- **简单性**：结构简洁，易于解析和处理

### 关键特性
| 特性 | 说明 |
|------|------|
| 退出码 | 标准 Unix 进程退出码（0 表示成功） |
| 双输出流 | 分别返回 stdout 和 stderr |
| 流式兼容 | 流式模式下输出字段为空，避免重复 |
| 字符串编码 | 输出以字符串形式返回，便于处理 |

## 3. 具体技术实现

### 数据结构定义

```rust
// Rust 结构定义 (v2.rs)
/// Final buffered result for `command/exec`.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecResponse {
    /// Process exit code.
    pub exit_code: i32,
    /// Buffered stdout capture.
    ///
    /// Empty when stdout was streamed via `command/exec/outputDelta`.
    pub stdout: String,
    /// Buffered stderr capture.
    ///
    /// Empty when stderr was streamed via `command/exec/outputDelta`.
    pub stderr: String,
}
```

### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Final buffered result for `command/exec`.",
  "properties": {
    "exitCode": {
      "description": "Process exit code.",
      "format": "int32",
      "type": "integer"
    },
    "stderr": {
      "description": "Buffered stderr capture.\n\nEmpty when stderr was streamed via `command/exec/outputDelta`.",
      "type": "string"
    },
    "stdout": {
      "description": "Buffered stdout capture.\n\nEmpty when stdout was streamed via `command/exec/outputDelta`.",
      "type": "string"
    }
  },
  "required": ["exitCode", "stderr", "stdout"],
  "title": "CommandExecResponse",
  "type": "object"
}
```

### 字段详细说明

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `exitCode` | integer (i32) | 是 | 进程退出码，0 通常表示成功 |
| `stdout` | string | 是 | stdout 缓冲输出，流式模式下为空 |
| `stderr` | string | 是 | stderr 缓冲输出，流式模式下为空 |

### 响应示例

**成功执行（缓冲模式）：**
```json
{
  "exitCode": 0,
  "stdout": "Hello, World!\n",
  "stderr": ""
}
```

**失败执行：**
```json
{
  "exitCode": 1,
  "stdout": "",
  "stderr": "Error: File not found\n"
}
```

**流式模式（输出已通过通知发送）：**
```json
{
  "exitCode": 0,
  "stdout": "",
  "stderr": ""
}
```

## 4. 关键代码路径与文件引用

### 核心文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（第 2362-2377 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求定义（第 456-460 行） |
| `codex-rs/app-server-protocol/schema/json/v2/CommandExecResponse.json` | JSON Schema 文件 |

### 协议注册

在 `common.rs` 中注册：

```rust
client_request_definitions! {
    // ...
    /// Execute a standalone command (argv vector) under the server's sandbox.
    OneOffCommandExec => "command/exec" {
        params: v2::CommandExecParams,
        response: v2::CommandExecResponse,
    },
    // ...
}
```

### 关联类型

- `CommandExecParams` - 对应的请求参数
- `CommandExecOutputDeltaNotification` - 流式输出通知（与响应配合使用）

### 执行流程

```
Client                                    Server
  |                                         |
  |---- command/exec (CommandExecParams) -->|
  |                                         |---> Spawn Process
  |                                         |<---> [Optional] Stream output via
  |                                         |       CommandExecOutputDeltaNotification
  |                                         |---> Wait for process exit
  |<--- CommandExecResponse ----------------|
  |                                         |
```

## 5. 依赖与外部交互

### 内部依赖

```
CommandExecResponse
├── i32 (exit_code 类型)
├── String (stdout/stderr 类型)
├── serde (序列化/反序列化)
├── schemars (JSON Schema 生成)
└── ts_rs (TypeScript 类型生成)
```

### 外部交互

1. **与进程管理的交互**：
   - 等待子进程退出并收集退出码
   - 捕获 stdout/stderr 输出

2. **与编码处理的交互**：
   - 将原始字节输出转换为 UTF-8 字符串
   - 处理可能的编码错误（如替换无效字符）

3. **与流式通知的协调**：
   - 确保所有 `CommandExecOutputDeltaNotification` 发送完成后再发送响应
   - 避免输出重复（流式模式下响应中 stdout/stderr 为空）

### 生成产物

- TypeScript 类型定义（`v2/CommandExecResponse.ts`）
- JSON Schema（`schema/json/v2/CommandExecResponse.json`）

## 6. 风险、边界与改进建议

### 潜在风险

1. **内存使用**：
   - 大量输出可能导致内存压力
   - 建议使用 `outputBytesCap` 或流式模式处理大输出

2. **编码问题**：
   - 非 UTF-8 输出可能导致解码错误
   - 需要定义编码错误处理策略

3. **超时处理**：
   - 命令超时后的响应行为需要明确
   - 退出码在超时情况下可能无意义

### 边界情况

| 场景 | 预期行为 |
|------|----------|
| 命令成功 | `exitCode: 0`, `stdout` 包含输出 |
| 命令失败 | `exitCode != 0`, `stderr` 可能包含错误信息 |
| 信号终止 | 退出码可能为 128 + 信号编号 |
| 流式模式 | `stdout` 和 `stderr` 为空字符串 |
| 无输出 | `stdout` 和 `stderr` 为空字符串 |
| 输出被截断 | `exitCode` 有效，输出被截断至上限 |

### 改进建议

1. **添加执行元数据**：
   ```rust
   pub struct CommandExecResponse {
       pub exit_code: i32,
       pub stdout: String,
       pub stderr: String,
       /// 执行持续时间（毫秒）
       pub duration_ms: i64,
       /// 是否因超时而终止
       pub timed_out: bool,
       /// 是否因输出上限而截断
       pub output_truncated: bool,
   }
   ```

2. **二进制输出支持**：
   ```rust
   pub struct CommandExecResponse {
       pub exit_code: i32,
       /// Base64 编码的 stdout
       pub stdout_base64: String,
       /// Base64 编码的 stderr
       pub stderr_base64: String,
       /// 原始字节数
       pub stdout_bytes: usize,
       pub stderr_bytes: usize,
   }
   ```

3. **添加信号信息**：
   ```rust
   pub struct CommandExecResponse {
       pub exit_code: i32,
       pub stdout: String,
       pub stderr: String,
       /// 如果进程被信号终止，信号编号
       pub signal: Option<i32>,
       /// 核心转储标志
       pub core_dumped: bool,
   }
   ```

4. **输出编码选项**：
   - 支持指定输出编码
   - 提供原始字节模式（Base64）

5. **分块响应**：
   - 对于大输出，支持分页返回
   - 添加 `nextChunk` 令牌

### 与 Thread-based 执行的对比

| 特性 | `CommandExecResponse` | Thread-based CommandExecution |
|------|----------------------|------------------------------|
| 上下文 | 独立执行，无 Thread/Turn | 在 Thread/Turn 上下文中执行 |
| 输出 | 直接返回或流式通知 | 通过 Item 和 Notification |
| 用途 | 简单命令执行 | 复杂对话式交互 |
| 响应 | 立即返回结果 | 异步，通过事件通知 |
