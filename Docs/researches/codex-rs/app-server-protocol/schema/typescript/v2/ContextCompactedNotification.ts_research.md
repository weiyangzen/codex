# ContextCompactedNotification.ts 研究文档

## 场景与职责

`ContextCompactedNotification.ts` 定义了上下文压缩通知类型，用于通知客户端当前线程的上下文已被压缩。这是一个**已弃用**的通知类型，被 `ContextCompaction` 线程项类型所取代。

该通知在对话历史过长、需要压缩以节省 Token 时发送，帮助客户端了解对话状态的变更。

## 功能点目的

1. **上下文压缩通知**: 告知客户端当前线程的上下文已被压缩
2. **状态同步**: 提供线程 ID 和回合 ID，帮助客户端定位压缩发生的上下文

## 具体技术实现

### 数据结构定义

```typescript
/**
 * Deprecated: Use `ContextCompaction` item type instead.
 */
export type ContextCompactedNotification = { 
  threadId: string, 
  turnId: string, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 发生上下文压缩的线程 ID |
| `turnId` | `string` | 发生上下文压缩的回合 ID |

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/common.rs`

```rust
// 在 ServerNotification 枚举中
ContextCompacted {
    thread_id: String,
    turn_id: String,
},
```

### 替代类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4257)

```rust
// ThreadItem::ContextCompaction 替代了 ContextCompactedNotification
ContextCompaction { id: String },
```

### 事件处理

**文件**: `codex-rs/app-server/src/bespoke_event_handling.rs`

处理上下文压缩事件，将核心事件转换为协议通知。

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| 核心协议 | `codex_protocol::protocol::ContextCompacted` |
| 事件系统 | `EventMsg::ContextCompaction` |

### 下游消费者

- **TUI**: 在对话历史中显示压缩标记
- **客户端**: 用于更新 UI 状态，显示上下文已压缩的提示

## 风险、边界与改进建议

### 已知风险

1. **已弃用**: 该类型已被标记为弃用，未来版本可能移除
2. **信息有限**: 仅提供线程和回合 ID，不包含压缩详情

### 迁移路径

客户端应迁移到使用 `ThreadItem::ContextCompaction`：

```typescript
// 旧方式（已弃用）
if (notification.type === 'contextCompacted') {
  const { threadId, turnId } = notification;
}

// 新方式
if (item.type === 'contextCompaction') {
  const { id } = item;
}
```

### 改进建议

1. **移除弃用类型**: 在下一个主要版本中完全移除该通知类型
2. **压缩详情**: 新类型可增加压缩前后的 Token 数量、压缩策略等信息
