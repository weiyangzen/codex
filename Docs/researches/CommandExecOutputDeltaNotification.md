# CommandExecOutputDeltaNotification 研究报告

## 1. 场景与职责

### 使用场景
`CommandExecOutputDeltaNotification` 是 app-server-protocol v2 API 中的服务器通知类型，用于在流式命令执行过程中向客户端推送实时的输出数据块。该通知主要用于以下场景：

- **实时终端会话**：当客户端通过 `command/exec` 启动一个 PTY（伪终端）会话时，服务器通过此通知实时推送 stdout/stderr 输出
- **长时间运行的命令**：对于执行时间较长的命令，客户端可以实时看到输出而不是等待命令完成
- **交互式应用**：支持 vim、less 等需要实时渲染的交互式应用程序

### 核心职责
1. **流式数据传输**：将命令输出以 Base64 编码的增量数据块形式推送给客户端
2. **连接生命周期管理**：通知是连接作用域的（connection-scoped），当原始连接关闭时，服务器会终止相关进程
3. **输出上限指示**：通过 `capReached` 字段告知客户端是否达到了输出字节上限

## 2. 功能点目的

### 设计目标
- **低延迟实时性**：避免客户端等待整个命令执行完成才能看到输出
- **二进制安全**：使用 Base64 编码传输，支持任意二进制数据
- **流区分**：明确区分 stdout 和 stderr 两个输出流
- **资源保护**：通过 `outputBytesCap` 机制防止输出过大导致内存问题

### 关键特性
| 特性 | 说明 |
|------|------|
| Base64 编码 | 所有输出数据均使用 Base64 编码，确保二进制安全 |
| 双流传输 | 支持 stdout 和 stderr 分别传输 |
| 上限截断指示 | `capReached` 标记告知客户端输出是否被截断 |
| 连接绑定 | 通知与特定连接绑定，连接断开则进程终止 |

## 3. 具体技术实现

### 数据结构定义

```rust
// Rust 结构定义 (v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecOutputDeltaNotification {
    /// Client-supplied, connection-scoped `processId`
    pub process_id: String,
    /// Output stream for this chunk
    pub stream: CommandExecOutputStream,
    /// Base64-encoded output bytes
    pub delta_base64: String,
    /// `true` when `outputBytesCap` truncated later output
    pub cap_reached: bool,
}

/// Stream label enum
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum CommandExecOutputStream {
    /// stdout stream. PTY mode multiplexes terminal output here.
    Stdout,
    /// stderr stream.
    Stderr,
}
```

### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Base64-encoded output chunk emitted for a streaming `command/exec` request.",
  "properties": {
    "capReached": {
      "description": "`true` on the final streamed chunk for a stream when `outputBytesCap` truncated later output on that stream.",
      "type": "boolean"
    },
    "deltaBase64": {
      "description": "Base64-encoded output bytes.",
      "type": "string"
    },
    "processId": {
      "description": "Client-supplied, connection-scoped `processId` from the original `command/exec` request.",
      "type": "string"
    },
    "stream": {
      "$ref": "#/definitions/CommandExecOutputStream",
      "description": "Output stream for this chunk."
    }
  },
  "required": ["capReached", "deltaBase64", "processId", "stream"],
  "title": "CommandExecOutputDeltaNotification",
  "type": "object"
}
```

### 字段说明

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `processId` | string | 是 | 客户端提供的连接作用域进程标识符 |
| `stream` | enum | 是 | 输出流类型："stdout" 或 "stderr" |
| `deltaBase64` | string | 是 | Base64 编码的输出字节 |
| `capReached` | boolean | 是 | 是否达到输出上限截断 |

## 4. 关键代码路径与文件引用

### 核心文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（第 4909-4927 行） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `CommandExecOutputStream` 枚举定义（第 2436-2445 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 服务器通知定义宏（第 874-901 行） |
| `codex-rs/app-server-protocol/schema/json/v2/CommandExecOutputDeltaNotification.json` | JSON Schema 文件 |

### 协议注册

在 `common.rs` 中，该通知通过 `server_notification_definitions!` 宏注册：

```rust
server_notification_definitions! {
    // ... 其他通知
    CommandExecOutputDelta => "command/exec/outputDelta" (v2::CommandExecOutputDeltaNotification),
    // ...
}
```

### 关联请求

该通知与以下客户端请求配合使用：
- `OneOffCommandExec` (`command/exec`) - 启动命令执行
- `CommandExecWrite` (`command/exec/write`) - 向 stdin 写入数据
- `CommandExecResize` (`command/exec/resize`) - 调整 PTY 大小
- `CommandExecTerminate` (`command/exec/terminate`) - 终止进程

## 5. 依赖与外部交互

### 内部依赖

```
CommandExecOutputDeltaNotification
├── CommandExecOutputStream (枚举)
├── serde (序列化/反序列化)
├── schemars (JSON Schema 生成)
├── ts_rs (TypeScript 类型生成)
└── codex_experimental_api_macros (ExperimentalApi 宏)
```

### 外部交互

1. **与客户端的交互**：
   - 通过 WebSocket/JSON-RPC 连接发送通知
   - 客户端需要解码 Base64 数据并渲染到终端 UI

2. **与沙箱的交互**：
   - 从沙箱进程中读取 stdout/stderr
   - 将原始字节编码为 Base64 后发送

3. **与连接管理的交互**：
   - 通知与特定连接绑定
   - 连接断开时自动清理相关进程

### 生成产物

- TypeScript 类型定义（`v2/CommandExecOutputDeltaNotification.ts`）
- JSON Schema（`schema/json/v2/CommandExecOutputDeltaNotification.json`）

## 6. 风险、边界与改进建议

### 潜在风险

1. **Base64 开销**：
   - 数据量增加约 33%（Base64 编码开销）
   - 对于大量输出可能影响性能和带宽

2. **连接稳定性**：
   - 连接断开会导致进程终止，可能中断重要操作
   - 网络不稳定时用户体验受影响

3. **内存管理**：
   - 如果客户端处理不及时，可能造成缓冲区堆积
   - `outputBytesCap` 需要合理设置

### 边界情况

| 场景 | 行为 |
|------|------|
| 空输出 | `deltaBase64` 为空字符串 |
| 达到上限 | `capReached` 设为 true，后续输出被丢弃 |
| 进程退出 | 不再发送新的通知，等待最终 `CommandExecResponse` |
| 连接断开 | 服务器自动终止进程 |

### 改进建议

1. **压缩支持**：
   - 考虑对大量数据使用压缩（如 gzip）减少传输量
   - 添加 `compression` 字段指示编码方式

2. **批量发送**：
   - 对于高频小数据块，考虑合并多个 delta 减少网络往返
   - 添加 `batch` 模式选项

3. **心跳机制**：
   - 添加保活心跳，检测连接状态
   - 支持连接恢复后重新订阅输出

4. **增量编码优化**：
   - 对于文本输出，考虑使用 diff/增量编码减少重复传输
   - 添加 `encoding` 字段支持多种编码方式

5. **流控机制**：
   - 实现背压（backpressure）机制，防止生产者过快
   - 客户端可以暂停/恢复接收输出
