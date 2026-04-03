# TurnCompletedNotification.ts Research

## 场景与职责

`TurnCompletedNotification` 是 App-Server Protocol v2 中的关键通知类型，用于在 AI 对话回合（Turn）完成时向客户端发送状态更新。该通知标志着一次用户与 AI 交互周期的结束，无论该回合是成功完成、被中断还是执行失败。

主要使用场景包括：
- **回合完成确认**：当 AI 完成对用户输入的处理并生成最终响应后，服务器发送此通知
- **状态同步**：客户端通过此通知获取回合的最终状态（completed、interrupted、failed 等）
- **历史记录更新**：TUI 客户端使用此通知更新对话历史界面
- **流程控制**：测试框架依赖此通知来验证回合执行结果

## 功能点目的

该通知的核心目的是：

1. **生命周期标记**：明确标识一个 Turn 生命周期的结束点
2. **状态传递**：携带完整的 `Turn` 对象，包含回合 ID、状态、错误信息（如有）和项目列表
3. **数据一致性**：确保客户端与服务器在回合状态上保持一致
4. **触发后续操作**：客户端收到此通知后可执行清理、UI 更新、历史持久化等操作

与其他通知的关系：
- 与 `TurnStartedNotification` 配对，标记回合的开始和结束
- 与 `TurnDiffUpdatedNotification`、`TurnPlanUpdatedNotification` 等中间通知形成完整的回合事件流

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnCompletedNotification = { 
  threadId: string, 
  turn: Turn, 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnCompletedNotification {
    pub thread_id: String,
    pub turn: Turn,
}
```

### 关联类型

- **`Turn`**：包含回合的完整信息
  - `id`: 回合唯一标识符
  - `items`: ThreadItem 数组（仅在 thread/resume 或 thread/fork 响应中填充）
  - `status`: TurnStatus 枚举（Completed、Interrupted、Failed、InProgress）
  - `error`: 可选的 TurnError，仅在状态为 failed 时填充

### 序列化特性

- 使用 camelCase 命名规范进行序列化
- 通过 ts-rs 自动生成 TypeScript 类型定义
- 支持 JsonSchema 生成用于验证

## 关键代码路径与文件引用

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:4694-4700` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnCompletedNotification.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/TurnCompletedNotification.json` | JSON Schema 定义 |

### 服务器端处理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 事件处理逻辑，发送回合完成通知 |
| `codex-rs/app-server/src/in_process.rs` | 进程内服务器实现 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:887` | ServerNotification 枚举定义 |

### 客户端消费

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 聊天组件处理通知 |
| `codex-rs/tui_app_server/src/app/app_server_adapter.rs` | App Server 适配器 |
| `codex-rs/app-server-client/src/lib.rs` | 客户端库实现 |

### 测试覆盖

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/turn_interrupt.rs:109-121` | 中断测试验证通知接收 |
| `codex-rs/app-server/tests/suite/v2/turn_start.rs` | 回合启动测试 |
| `codex-rs/app-server/tests/suite/v2/plan_item.rs` | Plan 项目测试 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | TUI 组件测试 |

## 依赖与外部交互

### 内部依赖

```
TurnCompletedNotification
├── Turn
│   ├── ThreadItem
│   ├── TurnStatus
│   └── TurnError (optional)
├── serde (Serialize, Deserialize)
├── schemars (JsonSchema)
└── ts_rs (TS)
```

### 协议集成

- **通知类型**：`turn/completed`（定义于 `common.rs:887`）
- **传输方式**：通过 WebSocket 或 stdio 发送 JSON-RPC 通知
- **ServerNotification 联合类型**：包含此通知作为变体之一

### 相关方法

- `turn/start`：启动新回合，最终会触发 `turn/completed`
- `turn/interrupt`：中断回合，会导致 `turn/completed` 携带 interrupted 状态
- `thread/resume`、`thread/fork`：这些响应中会填充 Turn 的 items 字段

## 风险、边界与改进建议

### 潜在风险

1. **数据一致性**：items 字段在不同场景下填充行为不一致（仅在 resume/fork 响应中填充），可能导致客户端逻辑错误
2. **大负载问题**：Turn 对象可能包含大量 ThreadItem，在频繁通知场景下可能影响性能
3. **状态竞态**：客户端需要正确处理通知到达顺序，避免与中间状态通知（如 diff/updated）产生竞态

### 边界情况

| 场景 | 行为 |
|------|------|
| 回合正常完成 | status = Completed，error = null |
| 回合被中断 | status = Interrupted，error 可能包含中断原因 |
| 回合执行失败 | status = Failed，error 包含详细错误信息 |
| 网络断开重连 | 客户端可能错过通知，需要通过 thread/read 重新获取状态 |

### 改进建议

1. **文档增强**：明确说明 items 字段的填充规则，避免客户端误用
2. **增量更新**：考虑在频繁更新场景下使用更轻量的通知格式
3. **确认机制**：对于关键状态变更，考虑添加客户端确认机制确保送达
4. **版本兼容**：在协议演进时保持向后兼容，避免破坏现有客户端
5. **监控埋点**：在服务器端添加通知发送的指标监控，便于排查问题
