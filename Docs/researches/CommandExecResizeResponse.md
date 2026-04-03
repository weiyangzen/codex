# CommandExecResizeResponse 研究报告

## 1. 场景与职责

### 使用场景
`CommandExecResizeResponse` 是 app-server-protocol v2 API 中用于响应 PTY 会话大小调整请求的空响应结构。它用于确认 `command/exec/resize` 请求的处理结果，适用于以下场景：

- **终端大小调整确认**：确认 PTY 会话的大小调整操作已成功完成
- **异步操作同步**：作为客户端等待服务器完成调整操作的信号
- **错误边界处理**：在失败情况下承载错误信息

### 核心职责
1. **操作确认**：向客户端确认 resize 操作已完成
2. **协议完整性**：保持请求-响应协议的完整性
3. **未来扩展**：为将来可能添加的响应字段预留结构

## 2. 功能点目的

### 设计目标
- **简洁性**：对于简单的成功确认，不需要复杂的响应数据
- **协议一致性**：遵循 JSON-RPC 2.0 的请求-响应模式
- **可扩展性**：空结构为未来添加字段提供兼容性

### 关键特性
| 特性 | 说明 |
|------|------|
| 空成功响应 | 无数据字段，仅表示操作成功 |
| 错误承载 | 失败时通过 JSON-RPC error 字段传递错误信息 |
| 类型安全 | 明确定义的响应类型，便于客户端处理 |

## 3. 具体技术实现

### 数据结构定义

```rust
// Rust 结构定义 (v2.rs)
/// Empty success response for `command/exec/resize`.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecResizeResponse {}
```

### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Empty success response for `command/exec/resize`.",
  "title": "CommandExecResizeResponse",
  "type": "object"
}
```

### 响应示例

**成功响应：**
```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "result": {}
}
```

**错误响应：**
```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "error": {
    "code": -32000,
    "message": "Process not found",
    "data": {
      "processId": "unknown-session"
    }
  }
}
```

## 4. 关键代码路径与文件引用

### 核心文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（第 2430-2434 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求定义（第 471-475 行） |
| `codex-rs/app-server-protocol/schema/json/v2/CommandExecResizeResponse.json` | JSON Schema 文件 |

### 协议注册

在 `common.rs` 中注册：

```rust
client_request_definitions! {
    // ...
    CommandExecResize => "command/exec/resize" {
        params: v2::CommandExecResizeParams,
        response: v2::CommandExecResizeResponse,
    },
    // ...
}
```

### 关联类型

- `CommandExecResizeParams` - 对应的请求参数
- `CommandExecParams` - 初始命令执行请求
- `CommandExecOutputDeltaNotification` - 调整大小后的输出通知

## 5. 依赖与外部交互

### 内部依赖

```
CommandExecResizeResponse
├── serde (序列化/反序列化)
├── schemars (JSON Schema 生成)
├── ts_rs (TypeScript 类型生成)
└── 无其他字段依赖
```

### 外部交互

1. **与 JSON-RPC 协议的交互**：
   - 作为 `result` 字段的值返回
   - 空对象 `{}` 表示成功

2. **与错误处理的交互**：
   - 失败时返回 JSON-RPC error 对象
   - 错误码和消息根据具体情况确定

### 生成产物

- TypeScript 类型定义（`v2/CommandExecResizeResponse.ts`）
- JSON Schema（`schema/json/v2/CommandExecResizeResponse.json`）

## 6. 风险、边界与改进建议

### 潜在风险

1. **缺乏详细信息**：
   - 当前空响应对调试帮助有限
   - 无法确认实际应用的终端大小

2. **异步延迟**：
   - 响应返回不代表应用程序已处理 SIGWINCH
   - 终端应用可能需要时间重新渲染

### 边界情况

| 场景 | 预期行为 |
|------|----------|
| 操作成功 | 返回空对象 `{}` |
| 进程不存在 | 返回 JSON-RPC 错误 |
| 非 PTY 会话 | 返回 JSON-RPC 错误 |
| 尺寸无效 | 返回 JSON-RPC 错误 |

### 改进建议

1. **添加确认字段**：
   ```rust
   pub struct CommandExecResizeResponse {
       /// 确认应用的终端大小
       pub applied_size: CommandExecTerminalSize,
       /// 操作时间戳
       pub timestamp_ms: i64,
   }
   ```

2. **添加状态信息**：
   ```rust
   pub struct CommandExecResizeResponse {
       /// 进程是否仍在运行
       pub process_running: bool,
       /// 是否为 PTY 会话
       pub is_pty: bool,
   }
   ```

3. **保留空响应作为选项**：
   - 对于不需要详细信息的场景，保持向后兼容
   - 通过请求参数控制响应详细程度

4. **错误码标准化**：
   - 定义特定的错误码用于常见失败场景
   - 如：`-32001` = ProcessNotFound, `-32002` = NotAPtySession

### 与其他空响应的对比

| 响应类型 | 对应请求 | 说明 |
|----------|----------|------|
| `CommandExecResizeResponse` | `command/exec/resize` | PTY 大小调整确认 |
| `CommandExecWriteResponse` | `command/exec/write` | stdin 写入确认 |
| `CommandExecTerminateResponse` | `command/exec/terminate` | 进程终止确认 |

这些空响应遵循相同的设计模式，保持 API 的一致性。
