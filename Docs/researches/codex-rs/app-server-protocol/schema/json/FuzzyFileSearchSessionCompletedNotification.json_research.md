# FuzzyFileSearchSessionCompletedNotification.json 研究文档

## 场景与职责

`FuzzyFileSearchSessionCompletedNotification` 是 Codex App-Server 协议中用于**通知模糊文件搜索会话完成**的通知结构。当服务器完成一个搜索会话的所有处理时，向客户端发送此通知。

该类型属于 **Server → Client** 的通知流，对应 JSON-RPC 通知方法为 `fuzzyFileSearch/sessionCompleted`。

### 使用场景

1. **会话结束标记**：标记一个搜索会话的正式结束
2. **清理资源**：客户端收到此通知后可以释放与会话相关的资源
3. **最终状态确认**：确保客户端知道服务器已完成所有处理

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sessionId` | string | ✅ | 搜索会话标识 |

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase")]
pub struct FuzzyFileSearchSessionCompletedNotification {
    pub session_id: String,
}
```

### ServerNotification 注册

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_notification_definitions! {
    FuzzyFileSearchSessionCompleted => "fuzzyFileSearch/sessionCompleted" (FuzzyFileSearchSessionCompletedNotification),
}
```

### 会话生命周期

```
sessionStart (Client → Server)
    ↓
sessionUpdate (Client → Server) ←→ sessionUpdated (Server → Client)
    ↓
sessionStop (Client → Server)
    ↓
sessionCompleted (Server → Client)
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 主类型定义（行 867-871） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerNotification 注册（行 920） |

### 相关类型

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | FuzzyFileSearchSessionStartParams |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | FuzzyFileSearchSessionUpdateParams |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | FuzzyFileSearchSessionUpdatedNotification |

---

## 依赖与外部交互

### 依赖类型

无外部 crate 依赖。

### 实验性状态

整个模糊文件搜索会话管理 API 处于实验性状态：
- `fuzzyFileSearch/sessionStart`
- `fuzzyFileSearch/sessionUpdate`
- `fuzzyFileSearch/sessionStop`
- `fuzzyFileSearch/sessionUpdated`
- `fuzzyFileSearch/sessionCompleted`

---

## 风险、边界与改进建议

### 已知风险

1. **实验性 API**：该通知属于实验性 API，可能在未来版本中变更或移除

2. **可靠性**：作为通知（非请求-响应），不保证送达，客户端需要处理丢失情况

### 边界情况

1. **重复通知**：服务器可能因重试机制发送重复的 `sessionCompleted` 通知
2. **未启动的会话**：收到未知 `sessionId` 的完成通知（可能是过期会话）

### 改进建议

1. **添加完成原因**：说明会话完成的原因：
   ```rust
   pub struct FuzzyFileSearchSessionCompletedNotification {
       pub session_id: String,
       pub reason: SessionCompleteReason,  // Completed, Cancelled, Error
   }
   ```

2. **添加统计信息**：提供会话期间的搜索统计：
   ```rust
   pub struct FuzzyFileSearchSessionCompletedNotification {
       pub session_id: String,
       pub stats: SessionStats,
   }
   
   pub struct SessionStats {
       pub total_searches: u32,
       pub total_results: u32,
       pub duration_ms: u32,
   }
   ```

3. **稳定化 API**：考虑将此通知与会话管理 API 一起提升为稳定 API

4. **确认机制**：考虑添加客户端确认机制，确保服务器知道客户端已收到完成通知
