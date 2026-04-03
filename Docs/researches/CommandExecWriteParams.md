# CommandExecWriteParams 研究报告

## 1. 场景与职责

### 使用场景
`CommandExecWriteParams` 是 app-server-protocol v2 API 中用于向正在运行的 `command/exec` 会话写入 stdin 数据的请求参数结构。它主要用于以下场景：

- **交互式输入**：向交互式程序（如 Python REPL、Node.js 控制台）发送输入
- **密码输入**：安全地向需要密码验证的命令传递凭据
- **自动化测试**：向被测程序发送预定义的输入序列
- **远程控制**：控制正在运行的终端应用程序
- **关闭输入流**：通过 `closeStdin` 通知进程输入结束（EOF）

### 核心职责
1. **数据写入**：向指定进程的 stdin 写入 Base64 编码的数据
2. **流控制**：支持关闭 stdin 以触发进程的 EOF 处理
3. **进程绑定**：通过 `processId` 精确定位目标进程
4. **二进制支持**：Base64 编码支持任意二进制数据

## 2. 功能点目的

### 设计目标
- **灵活性**：支持写入数据和关闭输入流两种操作
- **二进制安全**：使用 Base64 编码传输任意数据
- **精确控制**：通过 `processId` 精确控制特定会话
- **流式集成**：与 `streamStdin` 选项配合实现双向流式通信

### 关键特性
| 特性 | 说明 |
|------|------|
| Base64 编码 | 支持任意二进制数据安全传输 |
| 可选数据 | `deltaBase64` 可为 null，仅用于关闭 stdin |
| 流关闭 | `closeStdin` 标志用于发送 EOF |
| 组合操作 | 可同时写入数据并关闭流 |

## 3. 具体技术实现

### 数据结构定义

```rust
// Rust 结构定义 (v2.rs)
/// Write stdin bytes to a running `command/exec` session, close stdin, or
/// both.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecWriteParams {
    /// Client-supplied, connection-scoped `processId` from the original
    /// `command/exec` request.
    pub process_id: String,
    /// Optional base64-encoded stdin bytes to write.
    #[ts(optional = nullable)]
    pub delta_base64: Option<String>,
    /// Close stdin after writing `deltaBase64`, if present.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub close_stdin: bool,
}
```

### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Write stdin bytes to a running `command/exec` session, close stdin, or both.",
  "properties": {
    "closeStdin": {
      "description": "Close stdin after writing `deltaBase64`, if present.",
      "type": "boolean"
    },
    "deltaBase64": {
      "description": "Optional base64-encoded stdin bytes to write.",
      "type": ["string", "null"]
    },
    "processId": {
      "description": "Client-supplied, connection-scoped `processId` from the original `command/exec` request.",
      "type": "string"
    }
  },
  "required": ["processId"],
  "title": "CommandExecWriteParams",
  "type": "object"
}
```

### 字段详细说明

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `processId` | string | 是 | 原始 `command/exec` 请求中提供的连接作用域进程标识符 |
| `deltaBase64` | string \| null | 否 | Base64 编码的 stdin 数据，可为 null |
| `closeStdin` | boolean | 否 | 是否在写入后关闭 stdin（默认 false） |

### 使用示例

**写入数据：**
```json
{
  "processId": "interactive-shell-001",
  "deltaBase64": "bHMK",  // "ls\n" 的 Base64
  "closeStdin": false
}
```

**仅关闭 stdin：**
```json
{
  "processId": "interactive-shell-001",
  "deltaBase64": null,
  "closeStdin": true
}
```

**写入并关闭：**
```json
{
  "processId": "interactive-shell-001",
  "deltaBase64": "ZXhpdA==",  // "exit"
  "closeStdin": true
}
```

### 完整 JSON-RPC 请求示例

```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "method": "command/exec/write",
  "params": {
    "processId": "python-repl-001",
    "deltaBase64": "cHJpbnQoJ0hlbGxvJyk=",
    "closeStdin": false
  }
}
```

## 4. 关键代码路径与文件引用

### 核心文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（第 2379-2394 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求定义（第 461-465 行） |
| `codex-rs/app-server-protocol/schema/json/v2/CommandExecWriteParams.json` | JSON Schema 文件 |

### 协议注册

在 `common.rs` 中注册：

```rust
client_request_definitions! {
    // ...
    /// Write stdin bytes to a running `command/exec` session or close stdin.
    CommandExecWrite => "command/exec/write" {
        params: v2::CommandExecWriteParams,
        response: v2::CommandExecWriteResponse,
    },
    // ...
}
```

### 关联类型

- `CommandExecParams` - 初始命令执行请求（需设置 `streamStdin=true`）
- `CommandExecWriteResponse` - 写入操作的响应（空成功响应）
- `CommandExecOutputDeltaNotification` - 输出通知（与写入配合使用）

### 执行流程

```
Client                                    Server
  |                                         |
  |---- command/exec (streamStdin=true) --->|
  |                                         |---> Spawn Process
  |                                         |---> Setup stdin pipe
  |                                         |
  |---- command/exec/write --------------->|
  |    (CommandExecWriteParams)             |---> Decode Base64
  |                                         |---> Write to stdin
  |                                         |---> [Optional] Close stdin
  |<--- CommandExecWriteResponse -----------|
  |                                         |
  |<--- CommandExecOutputDeltaNotification -|
  |     (Output from the process)           |
  |                                         |
```

## 5. 依赖与外部交互

### 内部依赖

```
CommandExecWriteParams
├── String (process_id 类型)
├── Option<String> (delta_base64 类型)
├── bool (close_stdin 类型)
├── serde (序列化/反序列化)
├── schemars (JSON Schema 生成)
└── ts_rs (TypeScript 类型生成)
```

### 外部交互

1. **与进程 stdin 的交互**：
   - 解码 Base64 数据为原始字节
   - 写入进程的 stdin 管道
   - 处理写入缓冲区和流控

2. **与 PTY 的交互**（当 `tty=true`）：
   - 数据通过 PTY 主设备写入
   - 模拟终端输入行为

3. **与流控制的交互**：
   - 处理写入缓冲区满的情况
   - 实现背压机制防止内存溢出

### 生成产物

- TypeScript 类型定义（`v2/CommandExecWriteParams.ts`）
- JSON Schema（`schema/json/v2/CommandExecWriteParams.json`）

## 6. 风险、边界与改进建议

### 潜在风险

1. **缓冲区溢出**：
   - 大量数据写入可能导致内存压力
   - 需要实现流控和背压机制

2. **编码错误**：
   - 无效的 Base64 数据需要正确处理
   - 应返回明确的错误信息

3. **竞态条件**：
   - 进程可能在写入前已退出
   - 需要处理写入失败的情况

4. **死锁风险**：
   - 如果进程等待输入但缓冲区已满
   - 需要超时和错误处理机制

### 边界情况

| 场景 | 预期行为 |
|------|----------|
| processId 不存在 | 返回错误（ProcessNotFound） |
| 进程未启用 streamStdin | 返回错误（StdinNotStreamed） |
| 进程已退出 | 返回错误（ProcessTerminated） |
| 无效的 Base64 | 返回错误（InvalidBase64） |
| deltaBase64 为 null 且 closeStdin=false | 无操作，返回成功 |
| stdin 已关闭 | 返回错误（StdinAlreadyClosed） |
| 写入空数据 | 无操作或仅关闭 stdin |

### 改进建议

1. **添加写入确认**：
   ```rust
   pub struct CommandExecWriteResponse {
       /// 实际写入的字节数
       pub bytes_written: usize,
       /// stdin 是否已关闭
       pub stdin_closed: bool,
       /// 写入缓冲区剩余空间
       pub buffer_space_remaining: Option<usize>,
   }
   ```

2. **支持分块写入**：
   ```rust
   pub struct CommandExecWriteParams {
       pub process_id: String,
       pub delta_base64: Option<String>,
       pub close_stdin: bool,
       /// 是否为多部分写入的一部分
       pub is_partial: Option<bool>,
       /// 部分写入的序列号
       pub sequence_number: Option<u64>,
   }
   ```

3. **添加编码选项**：
   ```rust
   pub struct CommandExecWriteParams {
       pub process_id: String,
       pub data: Option<String>,
       pub encoding: Option<DataEncoding>,  // Base64, UTF8, Hex
       pub close_stdin: bool,
   }
   ```

4. **流控机制**：
   ```rust
   pub struct CommandExecWriteResponse {
       pub bytes_written: usize,
       /// 是否接受更多数据
       pub accept_more: bool,
       /// 建议的等待时间后再写入
       pub backpressure_delay_ms: Option<u64>,
   }
   ```

5. **批量写入**：
   ```rust
   pub struct CommandExecWriteParams {
       pub writes: Vec<StdinWrite>,
   }
   
   pub struct StdinWrite {
       pub process_id: String,
       pub delta_base64: Option<String>,
       pub close_stdin: bool,
   }
   ```

### 最佳实践

1. **Base64 编码**：
   - 使用标准 Base64 编码（非 URL-safe）
   - 处理换行符（某些编码器会添加）

2. **流控处理**：
   - 实现客户端背压机制
   - 监听缓冲区状态再发送更多数据

3. **错误重试**：
   - 对临时错误实现重试逻辑
   - 区分可重试和不可重试错误

4. **EOF 处理**：
   - 在适当的时候关闭 stdin
   - 某些程序需要 EOF 才能正确处理输入

5. **编码安全**：
   - 验证 Base64 数据的有效性
   - 限制单次写入的数据大小
