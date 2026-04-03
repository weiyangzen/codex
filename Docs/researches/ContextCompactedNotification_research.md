# ContextCompactedNotification 研究报告

## 1. 场景与职责

### 1.1 使用场景

`ContextCompactedNotification` 是 Codex App-Server Protocol v2 中的一个**已弃用（Deprecated）**通知类型，用于通知客户端当前对话线程的上下文已被压缩（compacted）。

**典型场景包括：**
- 当对话历史过长，超过模型上下文窗口限制时，系统自动触发上下文压缩
- 用户手动调用 `thread/compact/start` API 启动压缩流程
- 系统为维护性能而主动清理历史消息

### 1.2 核心职责

该通知的主要职责是：
1. **状态同步**：告知客户端特定 Turn 的上下文已被压缩
2. **历史标记**：帮助客户端理解为何某些历史消息不再完整可用
3. **兼容性维护**：保持与旧版本客户端的向后兼容

**重要说明**：根据 schema 描述，此通知已被标记为弃用，推荐使用 `ContextCompaction` item type 替代。

---

## 2. 功能点目的

### 2.1 设计意图

上下文压缩是 LLM 应用中的关键功能，用于解决：
- **Token 限制**：模型有最大上下文长度限制
- **成本控制**：减少不必要的 token 消耗
- **性能优化**：过长的历史会影响响应速度

### 2.2 通知目的

| 目的 | 说明 |
|------|------|
| 事件通知 | 异步通知客户端压缩事件已发生 |
| 范围标识 | 通过 `threadId` 和 `turnId` 精确定位 |
| 迁移提示 | 引导开发者迁移到新的 `ContextCompaction` item type |

### 2.3 弃用原因

迁移到 `ContextCompaction` item type 的优势：
1. 更统一的 item 生命周期管理
2. 与其他 Turn items 一致的处理流程
3. 更好的可观测性和调试能力

---

## 3. 具体技术实现

### 3.1 数据结构定义

**JSON Schema 定义** (`/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2/ContextCompactedNotification.json`):

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Deprecated: Use `ContextCompaction` item type instead.",
  "properties": {
    "threadId": {
      "type": "string"
    },
    "turnId": {
      "type": "string"
    }
  },
  "required": ["threadId", "turnId"],
  "title": "ContextCompactedNotification",
  "type": "object"
}
```

**Rust 结构体定义** (`codex-rs/app-server-protocol/src/protocol/v2.rs`):

```rust
/// Deprecated: Use `ContextCompaction` item type instead.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ContextCompactedNotification {
    pub thread_id: String,
    pub turn_id: String,
}
```

### 3.2 协议集成

**在 ServerNotification 枚举中注册** (`codex-rs/app-server-protocol/src/protocol/common.rs`):

```rust
server_notification_definitions! {
    // ... 其他通知
    /// Deprecated: Use `ContextCompaction` item type instead.
    ContextCompacted => "thread/compacted" (v2::ContextCompactedNotification),
    // ... 其他通知
}
```

**Wire 格式**：`"thread/compacted"`

### 3.3 序列化规范

| 属性 | 类型 | 序列化名称 | 必填 |
|------|------|-----------|------|
| thread_id | String | `threadId` | 是 |
| turn_id | String | `turnId` | 是 |

- 使用 camelCase 命名规范
- 通过 `#[serde(rename_all = "camelCase")]` 实现
- TypeScript 类型导出到 `v2/` 目录

---

## 4. 关键代码路径与文件引用

### 4.1 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2/ContextCompactedNotification.json` | JSON Schema 定义 |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs` (Line 5010-5017) | Rust 结构体定义 |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` (Line 915) | ServerNotification 枚举注册 |

### 4.2 事件处理代码

**事件处理位置** (`codex-rs/app-server/src/bespoke_event_handling.rs` Line 1245-1253):

```rust
EventMsg::ContextCompacted(..) => {
    let notification = ContextCompactedNotification {
        thread_id: conversation_id.to_string(),
        turn_id: event_turn_id.clone(),
    };
    outgoing
        .send_server_notification(ServerNotification::ContextCompacted(notification))
        .await;
}
```

### 4.3 核心协议事件定义

**Core Protocol 事件** (`codex-rs/protocol/src/protocol.rs`):

上下文压缩事件在核心协议层通过 `EventMsg::ContextCompacted` 定义，经 `bespoke_event_handling.rs` 转换为 v2 API 通知。

### 4.4 代码调用链

```
Core Protocol Layer
    ↓ EventMsg::ContextCompacted
App-Server Event Handler (bespoke_event_handling.rs)
    ↓ 转换为 ContextCompactedNotification
ServerNotification 枚举包装
    ↓ JSON 序列化
Client (WebSocket/SSE)
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `codex_protocol::protocol::EventMsg` | 核心协议事件定义 |
| `codex_app_server_protocol::ServerNotification` | 通知枚举包装 |
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |
| `ts_rs` | TypeScript 类型导出 |

### 5.2 外部交互

**与客户端的交互**：
- 通过 WebSocket 或 SSE 连接发送
- 客户端应监听 `"thread/compacted"` 方法名
- 收到后应更新本地 Turn 状态

**与核心协议的交互**：
```rust
// 核心协议层触发
EventMsg::ContextCompacted(..)

// 转换为 v2 通知
ContextCompactedNotification {
    thread_id: conversation_id.to_string(),
    turn_id: event_turn_id.clone(),
}
```

### 5.3 相关 API

| API | 关系 |
|-----|------|
| `thread/compact/start` | 触发上下文压缩的 API |
| `ContextCompaction` item type | 推荐使用的新替代方案 |
| `thread/read` | 可查询压缩后的 Turn 状态 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 说明 | 严重程度 |
|------|------|---------|
| 已弃用 | 该通知类型已被标记弃用，未来可能移除 | 中 |
| 信息有限 | 仅包含 threadId 和 turnId，缺少压缩详情 | 低 |
| 兼容性 | 旧客户端依赖此通知，需平滑迁移 | 中 |

### 6.2 边界情况

1. **并发压缩**：多个 Turn 同时触发压缩时，通知顺序可能交错
2. **网络延迟**：通知可能在压缩完成后延迟到达
3. **重连场景**：客户端重连后可能错过压缩通知

### 6.3 改进建议

#### 短期（维护阶段）

1. **文档完善**
   - 在 API 文档中明确标注弃用状态
   - 提供迁移指南到 `ContextCompaction`

2. **监控增强**
   - 添加 metrics 追踪此通知的使用频率
   - 监控还有多少客户端在使用旧通知

#### 长期（演进方向）

1. **完全迁移**
   - 推动所有客户端迁移到 `ContextCompaction` item type
   - 在适当版本后移除此通知类型

2. **功能增强**（如果保留）
   - 添加压缩前后 token 数量信息
   - 添加压缩原因（自动/手动）
   - 添加被压缩的消息范围

### 6.4 迁移路径

```rust
// 旧方式（当前）
ServerNotification::ContextCompacted(ContextCompactedNotification {
    thread_id,
    turn_id,
})

// 新方式（推荐）
// 通过 ItemStarted/ItemCompleted 通知中的 ContextCompaction item
ServerNotification::ItemStarted(...)
ServerNotification::ItemCompleted(...)
```

---

## 附录：相关代码片段

### A.1 ServerNotification 定义

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_notification_definitions! {
    // ...
    ContextCompacted => "thread/compacted" (v2::ContextCompactedNotification),
    // ...
}
```

### A.2 事件处理完整代码

```rust
// codex-rs/app-server/src/bespoke_event_handling.rs
EventMsg::ContextCompacted(..) => {
    let notification = ContextCompactedNotification {
        thread_id: conversation_id.to_string(),
        turn_id: event_turn_id.clone(),
    };
    outgoing
        .send_server_notification(ServerNotification::ContextCompacted(notification))
        .await;
}
```

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/app-server-protocol v2 API*
