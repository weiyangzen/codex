# TurnInterruptParams.ts Research

## 场景与职责

`TurnInterruptParams` 是 App-Server Protocol v2 中用于中断正在执行的 AI 回合（Turn）的请求参数类型。它允许客户端在用户需要停止当前 AI 处理时发送中断信号，例如用户想要取消一个长时间运行的命令或修正输入。

主要使用场景包括：
- **用户取消操作**：用户点击取消按钮或按下 Ctrl+C 时中断当前回合
- **超时处理**：当回合执行时间超过预期时自动触发中断
- **策略变更**：用户在中途决定改变执行策略，需要停止当前回合
- **错误恢复**：检测到严重错误时主动中断以避免进一步问题
- **测试场景**：测试框架验证中断功能的正确性

## 功能点目的

该类型的核心目的是：

1. **精确控制**：通过 threadId 和 turnId 精确定位要中断的特定回合
2. **防止误操作**：要求提供 turnId 确保中断的是预期的回合，避免误中断其他回合
3. **优雅终止**：给服务器机会进行清理工作，而非强制杀死进程
4. **状态同步**：中断后通过 `TurnCompletedNotification` 同步最终状态

与其他类型的关系：
- 与 `TurnInterruptResponse` 配对，形成完整的请求-响应循环
- 中断成功后，服务器会发送 `TurnCompletedNotification`，状态为 `Interrupted`
- 与 `TurnStartParams` 对应，一个启动回合，一个中断回合

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnInterruptParams = { 
  threadId: string, 
  turnId: string, 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnInterruptParams {
    pub thread_id: String,
    pub turn_id: String,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | string | 目标线程的唯一标识符，标识回合所在的对话线程 |
| `turnId` | string | 目标回合的唯一标识符，精确指定要中断的回合 |

### 方法映射

- **JSON-RPC 方法**：`turn/interrupt`
- **请求类型**：`ClientRequest::TurnInterrupt`
- **响应类型**：`TurnInterruptResponse`（空对象）

## 关键代码路径与文件引用

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3959-3965` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnInterruptParams.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/TurnInterruptParams.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest 枚举定义（`turn/interrupt` 方法） |

### 服务器端处理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 中断请求处理逻辑 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 消息处理器中的中断处理 |
| `codex-rs/exec/src/lib.rs` | 执行器层面的中断支持 |

### 客户端实现

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/app_server_session.rs` | TUI App Server 会话中断实现 |
| `codex-rs/tui/src/app.rs` | TUI 客户端中断触发逻辑 |
| `codex-rs/app-server-client/src/lib.rs` | 客户端库中断方法 |

### 测试覆盖

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/turn_interrupt.rs` | 中断功能的完整集成测试 |
| `codex-rs/app-server/tests/common/mcp_process.rs` | 测试辅助函数，包含中断请求发送 |

## 依赖与外部交互

### 内部依赖

```
TurnInterruptParams
├── thread_id: String
├── turn_id: String
├── serde (Serialize, Deserialize)
├── schemars (JsonSchema)
└── ts_rs (TS)
```

### 协议集成

- **请求方法**：`turn/interrupt`（定义于 `common.rs`）
- **请求-响应流程**：
  1. 客户端发送 `TurnInterruptParams`
  2. 服务器返回 `TurnInterruptResponse`（空对象）
  3. 服务器处理中断并发送 `TurnCompletedNotification`

### 中断处理流程

```
Client                                  Server
  |                                       |
  |---- turn/interrupt (TurnInterruptParams) --->|
  |                                       |
  |<--- TurnInterruptResponse ------------|
  |                                       |
  |<--- turn/completed (status=Interrupted) -----|
  |                                       |
```

### 相关类型

| 类型 | 说明 |
|------|------|
| `TurnInterruptResponse` | 中断请求的响应（空对象） |
| `TurnStatus::Interrupted` | 中断后的回合状态 |
| `TurnCompletedNotification` | 中断完成后发送的通知 |

## 风险、边界与改进建议

### 潜在风险

1. **竞态条件**：如果中断请求到达时回合刚好完成，可能导致意外行为
2. **清理不完整**：强制中断可能导致资源泄漏（如临时文件、子进程）
3. **状态不一致**：客户端和服务器对回合状态的认知可能暂时不一致
4. **误中断风险**：错误的 turnId 可能中断错误的回合

### 边界情况

| 场景 | 行为 |
|------|------|
| 回合已完成 | 返回错误，指示回合不在可中断状态 |
| 回合不存在 | 返回错误，指示无效的 turnId |
| 线程不存在 | 返回错误，指示无效的 threadId |
| 重复中断 | 第二次及后续中断请求返回错误或忽略 |
| 中断执行中的命令 | 发送信号终止子进程，清理资源 |
| 网络中断 | 客户端可能无法收到响应，需通过轮询确认状态 |

### 改进建议

1. **幂等性保证**：确保重复的中断请求不会导致错误，而是返回已中断的状态
2. **中断原因**：添加可选的 `reason` 字段，用于记录中断原因（用户取消、超时、错误等）
3. **优雅超时**：添加 `timeout` 字段，指定等待优雅中断的最大时间
4. **强制中断**：添加 `force` 选项，允许强制终止无法优雅中断的回合
5. **中断进度**：对于复杂的中断操作，发送进度通知
6. **原子性检查**：服务器在处理中断前验证 turnId 是否匹配当前活跃回合
7. **审计日志**：记录所有中断操作，便于问题追踪

### 测试建议

1. **正常中断**：验证活跃回合可被正确中断
2. **已完成回合**：验证对已完成回合的中断请求返回适当错误
3. **不存在回合**：验证对不存在回合的中断请求返回适当错误
4. **重复中断**：验证重复中断请求的处理
5. **长命令中断**：验证执行中的 shell 命令可被正确终止
6. **资源清理**：验证中断后资源（临时文件、子进程）被正确清理
