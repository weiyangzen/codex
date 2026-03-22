# FuzzyFileSearchSessionUpdatedNotification.json 研究文档

## 场景与职责

`FuzzyFileSearchSessionUpdatedNotification` 是 Codex App-Server 协议中用于**通知模糊文件搜索会话结果更新**的通知结构。当服务器在搜索会话中找到新的匹配结果时，向客户端发送此通知。

该类型属于 **Server → Client** 的通知流，对应 JSON-RPC 通知方法为 `fuzzyFileSearch/sessionUpdated`。

### 使用场景

1. **增量结果推送**：服务器逐步推送搜索结果，无需等待完整搜索完成
2. **实时更新**：支持大型项目的实时搜索体验
3. **流式结果**：允许客户端在搜索进行中显示部分结果

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sessionId` | string | ✅ | 搜索会话标识 |
| `query` | string | ✅ | 当前搜索查询 |
| `files` | FuzzyFileSearchResult[] | ✅ | 匹配的文件结果列表 |

### 结果项类型（FuzzyFileSearchResult）

与 `FuzzyFileSearchResponse` 中的结果项相同：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file_name` | string | ✅ | 文件名 |
| `path` | string | ✅ | 完整路径 |
| `root` | string | ✅ | 所属根目录 |
| `match_type` | FuzzyFileSearchMatchType | ✅ | 匹配类型（file 或 directory） |
| `score` | integer | ✅ | 匹配分数 |
| `indices` | integer[] \| null | ❌ | 匹配字符索引 |

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase")]
pub struct FuzzyFileSearchSessionUpdatedNotification {
    pub session_id: String,
    pub query: String,
    pub files: Vec<FuzzyFileSearchResult>,
}
```

### ServerNotification 注册

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_notification_definitions! {
    FuzzyFileSearchSessionUpdated => "fuzzyFileSearch/sessionUpdated" (FuzzyFileSearchSessionUpdatedNotification),
}
```

### 与会话更新的关系

```rust
// 客户端发送更新请求
pub struct FuzzyFileSearchSessionUpdateParams {
    pub session_id: String,
    pub query: String,
}

// 服务器推送更新通知
pub struct FuzzyFileSearchSessionUpdatedNotification {
    pub session_id: String,
    pub query: String,
    pub files: Vec<FuzzyFileSearchResult>,
}
```

注意：客户端发送 `sessionUpdate` 请求，服务器通过 `sessionUpdated` 通知推送结果。

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 主类型定义（行 861-866） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerNotification 注册（行 919） |

### 相关类型

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | FuzzyFileSearchResult（行 803-811） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | FuzzyFileSearchSessionUpdateParams（行 840-846） |

---

## 依赖与外部交互

### 依赖类型

```rust
// 复用 FuzzyFileSearchResult
pub use FuzzyFileSearchResult;
```

### 实验性状态

该通知属于实验性 API（标记为 `#[experimental("fuzzyFileSearch/sessionUpdate")]`）。

---

## 风险、边界与改进建议

### 已知风险

1. **通知丢失**：作为通知而非请求-响应，可能因网络问题丢失
2. **顺序问题**：多个 `sessionUpdated` 通知可能乱序到达
3. **重复结果**：同一文件可能在多个通知中重复出现

### 边界情况

1. **空结果通知**：`files` 为空数组表示当前查询无匹配
2. **过期查询**：通知到达时客户端可能已经发送了新的查询
3. **大量通知**：快速输入可能导致大量通知，客户端需要节流处理

### 改进建议

1. **添加序列号**：帮助客户端检测乱序和丢失：
   ```rust
   pub struct FuzzyFileSearchSessionUpdatedNotification {
       pub session_id: String,
       pub query: String,
       pub files: Vec<FuzzyFileSearchResult>,
       pub sequence_number: u32,  // 新增
   }
   ```

2. **增量更新**：只发送新增或移除的结果，而非完整列表：
   ```rust
   pub struct FuzzyFileSearchSessionUpdatedNotification {
       pub session_id: String,
       pub query: String,
       pub added: Vec<FuzzyFileSearchResult>,
       pub removed: Vec<String>,  // 路径列表
   }
   ```

3. **添加时间戳**：帮助客户端判断通知的新鲜度：
   ```rust
   pub struct FuzzyFileSearchSessionUpdatedNotification {
       pub session_id: String,
       pub query: String,
       pub files: Vec<FuzzyFileSearchResult>,
       pub timestamp_ms: u64,
   }
   ```

4. **结果去重**：服务器端确保同一文件不在多个通知中重复发送

5. **稳定化 API**：考虑将此通知与会话管理 API 一起提升为稳定 API
