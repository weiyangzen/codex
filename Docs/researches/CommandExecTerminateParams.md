# CommandExecTerminateParams 研究报告

## 1. 场景与职责

### 使用场景
`CommandExecTerminateParams` 是 app-server-protocol v2 API 中用于终止正在运行的 `command/exec` 会话的请求参数结构。它主要用于以下场景：

- **用户取消操作**：用户主动取消正在执行的长时间运行命令
- **超时处理**：当命令执行超过预期时间时自动终止
- **资源回收**：清理不再需要的后台进程
- **错误恢复**：在检测到错误或异常时终止相关进程
- **会话清理**：在连接关闭前显式终止所有关联进程

### 核心职责
1. **进程终止**：向指定的进程发送终止信号
2. **资源清理**：确保进程资源被正确释放
3. **会话管理**：通过 `processId` 精确定位目标进程
4. **优雅关闭**：给予进程适当的清理时间（如需要）

## 2. 功能点目的

### 设计目标
- **精确控制**：通过 `processId` 精确指定要终止的进程
- **即时生效**：终止请求立即处理，减少资源占用
- **安全性**：仅终止属于当前连接的进程，防止越权操作
- **简洁性**：最小化的参数设计，降低使用复杂度

### 关键特性
| 特性 | 说明 |
|------|------|
| 进程绑定 | 通过 `processId` 精确控制特定会话 |
| 连接作用域 | 只能终止当前连接创建的进程 |
| 立即执行 | 终止操作同步处理，快速响应 |
| 幂等性 | 对已经终止的进程再次终止应返回成功 |

## 3. 具体技术实现

### 数据结构定义

```rust
// Rust 结构定义 (v2.rs)
/// Terminate a running `command/exec` session.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecTerminateParams {
    /// Client-supplied, connection-scoped `processId` from the original
    /// `command/exec` request.
    pub process_id: String,
}
```

### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Terminate a running `command/exec` session.",
  "properties": {
    "processId": {
      "description": "Client-supplied, connection-scoped `processId` from the original `command/exec` request.",
      "type": "string"
    }
  },
  "required": ["processId"],
  "title": "CommandExecTerminateParams",
  "type": "object"
}
```

### 字段详细说明

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `processId` | string | 是 | 原始 `command/exec` 请求中提供的连接作用域进程标识符 |

### 使用示例

```json
{
  "processId": "long-running-task-001"
}
```

### 完整 JSON-RPC 请求示例

```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "method": "command/exec/terminate",
  "params": {
    "processId": "terminal-session-001"
  }
}
```

## 4. 关键代码路径与文件引用

### 核心文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（第 2402-2410 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求定义（第 466-470 行） |
| `codex-rs/app-server-protocol/schema/json/v2/CommandExecTerminateParams.json` | JSON Schema 文件 |

### 协议注册

在 `common.rs` 中注册：

```rust
client_request_definitions! {
    // ...
    /// Terminate a running `command/exec` session by client-supplied `processId`.
    CommandExecTerminate => "command/exec/terminate" {
        params: v2::CommandExecTerminateParams,
        response: v2::CommandExecTerminateResponse,
    },
    // ...
}
```

### 关联类型

- `CommandExecParams` - 初始命令执行请求（创建进程时需提供 `processId`）
- `CommandExecTerminateResponse` - 终止操作的响应（空成功响应）
- `CommandExecResponse` - 终止后最终可能收到的命令执行响应

### 执行流程

```
Client                                    Server
  |                                         |
  |---- command/exec/terminate ------------>|
  |    (CommandExecTerminateParams)         |
  |                                         |---> Find process by processId
  |                                         |---> Send termination signal
  |                                         |---> Wait for process exit
  |                                         |---> Cleanup resources
  |<--- CommandExecTerminateResponse -------|
  |                                         |
  |<--- [Optional] CommandExecResponse -----|
  |     (if process exits after termination)|
```

## 5. 依赖与外部交互

### 内部依赖

```
CommandExecTerminateParams
├── String (process_id 类型)
├── serde (序列化/反序列化)
├── schemars (JSON Schema 生成)
└── ts_rs (TypeScript 类型生成)
```

### 外部交互

1. **与进程管理的交互**：
   - 通过 `processId` 查找进程句柄
   - 发送终止信号（SIGTERM 或 SIGKILL）
   - 等待进程退出并回收资源

2. **与信号系统的交互**：
   - 首先尝试发送 SIGTERM（优雅终止）
   - 超时后发送 SIGKILL（强制终止）

3. **与沙箱的交互**：
   - 确保进程在沙箱内被正确终止
   - 清理沙箱相关的资源

### 平台实现差异

| 平台 | 终止机制 |
|------|----------|
| Linux/macOS | 使用 `kill(pid, SIGTERM)`，超时后使用 `SIGKILL` |
| Windows | 使用 `TerminateProcess()` API |

### 生成产物

- TypeScript 类型定义（`v2/CommandExecTerminateParams.ts`）
- JSON Schema（`schema/json/v2/CommandExecTerminateParams.json`）

## 6. 风险、边界与改进建议

### 潜在风险

1. **僵尸进程**：
   - 如果终止信号未被正确处理，可能产生僵尸进程
   - 需要确保父进程正确等待子进程退出

2. **资源泄漏**：
   - PTY 设备、文件描述符等资源需要正确释放
   - 沙箱资源需要清理

3. **数据丢失**：
   - 强制终止可能导致未保存的数据丢失
   - 需要权衡优雅终止和强制终止的时机

4. **权限问题**：
   - 只能终止当前连接创建的进程
   - 需要验证 `processId` 的归属

### 边界情况

| 场景 | 预期行为 |
|------|----------|
| processId 不存在 | 返回错误（如 ProcessNotFound） |
| 进程已自然退出 | 返回成功（幂等性） |
| 进程无响应 | 先 SIGTERM，超时后 SIGKILL |
| 连接已断开 | 服务器应自动清理相关进程 |
| 沙箱异常 | 强制清理所有相关资源 |

### 改进建议

1. **添加终止选项**：
   ```rust
   pub struct CommandExecTerminateParams {
       pub process_id: String,
       /// 终止方式
       pub mode: Option<TerminateMode>,
       /// 优雅终止超时时间（毫秒）
       pub graceful_timeout_ms: Option<u64>,
   }
   
   pub enum TerminateMode {
       /// 先尝试优雅终止，超时后强制终止
       GracefulThenForce,
       /// 立即强制终止
       Force,
       /// 仅发送优雅终止信号，不强制
       GracefulOnly,
   }
   ```

2. **批量终止**：
   ```rust
   pub struct CommandExecTerminateParams {
       /// 支持终止多个进程
       pub process_ids: Vec<String>,
   }
   ```

3. **终止原因**：
   ```rust
   pub struct CommandExecTerminateParams {
       pub process_id: String,
       /// 终止原因，用于日志和审计
       pub reason: Option<String>,
   }
   ```

4. **响应增强**：
   ```rust
   pub struct CommandExecTerminateResponse {
       /// 进程终止前的状态
       pub previous_status: ProcessStatus,
       /// 实际使用的终止信号
       pub signal_used: String,
       /// 终止耗时（毫秒）
       pub termination_duration_ms: u64,
   }
   ```

5. **自动终止策略**：
   - 支持配置空闲超时自动终止
   - 支持连接断开时自动终止关联进程
   - 支持资源限制触发自动终止

### 最佳实践

1. **优雅终止优先**：
   - 先发送 SIGTERM，给予进程清理时间
   - 超时后再使用 SIGKILL

2. **超时配置**：
   - 根据进程类型配置合理的优雅终止超时
   - 交互式程序可能需要更长的超时

3. **状态检查**：
   - 终止后检查进程是否确实已退出
   - 处理可能的僵尸进程

4. **日志记录**：
   - 记录所有终止操作
   - 包括终止原因、使用的信号、耗时等
