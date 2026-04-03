# TurnInterruptResponse.ts Research

## 场景与职责

`TurnInterruptResponse` 是 App-Server Protocol v2 中 `turn/interrupt` 方法的响应类型。作为一个空对象响应（`Record<string, never>`），它表示中断请求已被服务器成功接收和处理，实际的回合状态变更通过后续的 `TurnCompletedNotification` 异步通知传递。

主要使用场景包括：
- **中断确认**：确认服务器已收到并处理中断请求
- **异步分离**：将请求的同步响应与实际的异步状态变更分离
- **协议一致性**：保持请求-响应模式的完整性，即使无实际数据返回
- **测试验证**：测试框架验证中断请求的响应格式

## 功能点目的

该类型的核心目的是：

1. **请求确认**：向客户端确认中断请求已被成功接收
2. **异步架构支持**：采用异步通知模式，响应仅表示请求已受理，实际状态变更通过通知传递
3. **协议规范**：保持 JSON-RPC 协议的完整性，每个请求都有对应的响应
4. **简化处理**：空对象设计简化了响应处理逻辑

设计哲学：
- **分离关注点**：同步响应仅确认请求接收，异步通知传递实际状态
- **最终一致性**：客户端通过通知机制最终获得一致的状态视图
- **最小化设计**：无额外数据时返回空对象，避免不必要的字段

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnInterruptResponse = Record<string, never>;
```

TypeScript 中的 `Record<string, never>` 表示一个空对象类型，即没有任何属性的对象。

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnInterruptResponse {}
```

Rust 中使用空结构体 `{}` 表示无任何字段的响应。

### 方法映射

- **JSON-RPC 方法**：`turn/interrupt`
- **请求类型**：`TurnInterruptParams`
- **响应类型**：`TurnInterruptResponse`（空对象）

### 请求-响应流程

```
┌─────────┐                              ┌─────────┐
│ Client  │                              │ Server  │
└────┬────┘                              └────┬────┘
     │                                        │
     │──── turn/interrupt ───────────────────>│
     │    (TurnInterruptParams)               │
     │                                        │
     │<─── TurnInterruptResponse ─────────────│
     │    {}                                  │
     │                                        │
     │    [异步处理中...]                      │
     │                                        │
     │<─── turn/completed ────────────────────│
     │    (status: Interrupted)               │
     │                                        │
```

## 关键代码路径与文件引用

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3967-3970` | Rust 空结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnInterruptResponse.ts` | TypeScript 空对象类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/TurnInterruptResponse.json` | JSON Schema 定义（空对象） |

### 服务器端处理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 中断请求处理，返回空响应 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest 枚举中的响应类型定义 |

### 客户端处理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/app_server_session.rs` | TUI 客户端处理中断响应 |
| `codex-rs/app-server-client/src/lib.rs` | 客户端库实现 |

### 测试覆盖

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/turn_interrupt.rs:107` | 验证中断响应解析 |

## 依赖与外部交互

### 内部依赖

```
TurnInterruptResponse
├── serde (Serialize, Deserialize)
├── schemars (JsonSchema)
└── ts_rs (TS)
```

### 协议集成

- **响应配对**：
  ```rust
  TurnInterrupt => "turn/interrupt" {
      params: v2::TurnInterruptParams,
      response: v2::TurnInterruptResponse,
  }
  ```

### 异步状态同步

由于响应为空对象，实际的状态变更通过以下通知传递：

| 通知类型 | 说明 |
|---------|------|
| `turn/completed` | 回合完成通知，包含最终状态（Interrupted） |
| `error` | 如果中断过程中发生错误 |

## 风险、边界与改进建议

### 潜在风险

1. **响应与通知时序**：客户端可能在收到响应后、收到通知前查询状态，获得不一致的结果
2. **网络分区**：如果响应丢失，客户端可能重复发送中断请求
3. **无错误详情**：响应为空，无法在中断受理阶段传递警告或提示信息

### 边界情况

| 场景 | 行为 |
|------|------|
| 请求成功 | 返回空对象 `{}` |
| 回合不存在 | 返回 JSON-RPC 错误，而非空响应 |
| 回合已完成 | 返回 JSON-RPC 错误 |
| 服务器内部错误 | 返回 JSON-RPC 错误 |

### 改进建议

1. **添加受理时间戳**：在响应中添加服务器受理请求的时间戳，便于调试时序问题
2. **添加请求 ID**：响应中携带请求 ID，便于与通知关联
3. **预估处理时间**：添加预估的中断处理时间，客户端可据此设置超时
4. **状态查询接口**：提供显式的回合状态查询接口，用于验证中断结果
5. **幂等性保证**：确保重复的中断请求不会导致错误

### 设计模式对比

| 模式 | 优点 | 缺点 |
|------|------|------|
| **当前：空响应 + 通知** | 简单、异步解耦 | 客户端需等待通知确认结果 |
| **同步返回最终状态** | 立即知道结果 | 阻塞等待、超时复杂 |
| **返回处理句柄** | 可查询进度 | 增加复杂度 |

当前设计选择了简单性和异步解耦，适合大多数场景。
