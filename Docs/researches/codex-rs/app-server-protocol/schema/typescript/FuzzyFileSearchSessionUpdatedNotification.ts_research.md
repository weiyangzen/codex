# FuzzyFileSearchSessionUpdatedNotification Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`FuzzyFileSearchSessionUpdatedNotification` 是 Codex 应用服务器协议中用于**通知模糊文件搜索会话结果更新**的通知类型。在会话式文件搜索过程中，服务器通过此通知向客户端发送增量搜索结果。

**典型使用场景：**
- 大目录异步搜索的增量结果返回
- 实时搜索 UI 的渐进式结果展示
- 用户输入时的即时反馈
- 减少大搜索的首次响应时间

**职责：**
- 提供搜索的增量结果
- 标识结果所属的会话和查询
- 支持实时更新搜索 UI
- 与会话完成通知配对使用

## 2. 功能点目的 (Purpose of This Type)

该类型的设计目的是：

1. **增量更新**：支持大目录搜索的渐进式结果返回
2. **实时反馈**：用户输入时即时显示匹配结果
3. **性能优化**：减少大搜索的等待时间
4. **用户体验**：提供流畅的实时搜索体验

## 3. 具体技术实现 (Technical Implementation Details)

### TypeScript 定义

```typescript
export type FuzzyFileSearchSessionUpdatedNotification = { 
  sessionId: string, 
  query: string, 
  files: Array<FuzzyFileSearchResult>, 
};
```

### Rust 定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase")]
pub struct FuzzyFileSearchSessionUpdatedNotification {
    pub session_id: String,
    pub query: String,
    pub files: Vec<FuzzyFileSearchResult>,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `sessionId` | `string` | 搜索会话的唯一标识符 |
| `query` | `string` | 当前查询字符串 |
| `files` | `FuzzyFileSearchResult[]` | 增量搜索结果数组 |

### 更新语义

该通知的语义是**增量更新**还是**全量替换**？

根据常见实现模式，通常是：
- **增量追加**：新通知的 `files` 追加到现有结果
- **全量替换**：新通知的 `files` 完全替换之前的结果

客户端应该根据实际需求选择策略：

```typescript
// 增量追加策略
function handleIncrementalUpdate(notification: FuzzyFileSearchSessionUpdatedNotification) {
  const existing = getSessionResults(notification.sessionId);
  const merged = mergeResults(existing, notification.files);
  updateSessionResults(notification.sessionId, merged);
}

// 全量替换策略
function handleFullUpdate(notification: FuzzyFileSearchSessionUpdatedNotification) {
  updateSessionResults(notification.sessionId, notification.files);
}
```

### 使用示例

```typescript
// 客户端处理会话更新通知
function handleSessionUpdated(
  notification: FuzzyFileSearchSessionUpdatedNotification
) {
  const { sessionId, query, files } = notification;
  
  // 1. 验证查询是否匹配当前输入
  if (query !== getCurrentQuery(sessionId)) {
    console.warn("Stale update received");
    return;
  }
  
  // 2. 更新结果列表
  appendResults(sessionId, files);
  
  // 3. 更新 UI
  renderResults(sessionId);
  
  // 4. 显示加载指示器（如果搜索未完成）
  showLoading(sessionId, true);
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 类型定义
- **TypeScript**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/FuzzyFileSearchSessionUpdatedNotification.ts`
- **Rust**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` (lines 858-865)

### 相关类型
- `FuzzyFileSearchResult` - 单个搜索结果
- `FuzzyFileSearchSessionCompletedNotification` - 会话完成通知
- `FuzzyFileSearchSessionStartParams` - 会话开始参数

### 使用位置

1. **服务器通知定义**（`common.rs`）：
   ```rust
   server_notification_definitions! {
       // ...
       FuzzyFileSearchSessionUpdated => "fuzzyFileSearch/sessionUpdated" 
           (FuzzyFileSearchSessionUpdatedNotification),
       // ...
   }
   ```

2. **通知方法**：`fuzzyFileSearch/sessionUpdated`

### 会话流程

```
ClientRequest::FuzzyFileSearchSessionStart
  ↓
ServerNotification::FuzzyFileSearchSessionUpdated (多次)
  files: [result1, result2, ...]
  ↓
ServerNotification::FuzzyFileSearchSessionUpdated (多次)
  files: [result3, result4, ...]
  ↓
ServerNotification::FuzzyFileSearchSessionCompleted
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 协议集成
- 属于 app-server-protocol 类型（在 `common.rs` 中定义）
- 通过 `ts-rs` 自动生成 TypeScript 类型
- 使用 camelCase 序列化
- 标记为 **experimental** API（通过 session API）

### 依赖类型
```typescript
import type { FuzzyFileSearchResult } from "./FuzzyFileSearchResult";
```

### 与 Session API 的关系

```rust
#[experimental("fuzzyFileSearch/sessionStart")]
FuzzyFileSearchSessionStart => "fuzzyFileSearch/sessionStart" {
    params: FuzzyFileSearchSessionStartParams { session_id, roots },
    response: FuzzyFileSearchSessionStartResponse,
}

#[experimental("fuzzyFileSearch/sessionUpdate")]
FuzzyFileSearchSessionUpdate => "fuzzyFileSearch/sessionUpdate" {
    params: FuzzyFileSearchSessionUpdateParams { session_id, query },
    response: FuzzyFileSearchSessionUpdateResponse,
}
```

### 外部交互

1. **服务器 → 客户端**：搜索过程中多次发送更新通知
2. **客户端处理**：累积或替换结果，更新 UI
3. **用户交互**：用户看到渐进式结果，可以继续输入
4. **查询变更**：新查询触发新的更新序列

### 与同步搜索的对比

| 特性 | 同步搜索 (`FuzzyFileSearch`) | 会话搜索 (`FuzzyFileSearchSession*`) |
|------|------------------------------|--------------------------------------|
| 响应方式 | 单次响应 | 多次通知 |
| 适用场景 | 小目录 | 大目录 |
| 实时性 | 等待全部完成 | 渐进显示 |
| 可取消性 | 有限 | 更好 |
| API 状态 | 稳定 | Experimental |

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **增量语义不明确**：
   - 协议未明确 `files` 是增量还是全量
   - 不同客户端可能有不同实现

2. **重复结果**：
   - 增量更新可能包含之前已发送的结果
   - 客户端需要去重逻辑

3. **顺序保证**：
   - 通知可能乱序到达
   - 客户端需要处理乱序情况

4. **大量通知**：
   - 大目录搜索可能产生大量通知
   - 可能影响性能和用户体验

5. **与完成通知的竞态**：
   - `Updated` 和 `Completed` 通知可能同时到达
   - 客户端需要正确处理

### 改进建议

1. **明确增量语义**：
   ```rust
   pub struct FuzzyFileSearchSessionUpdatedNotification {
       pub session_id: String,
       pub query: String,
       pub files: Vec<FuzzyFileSearchResult>,
       pub update_type: UpdateType,  // 新
   }
   
   pub enum UpdateType {
       Incremental,  // 追加到现有结果
       Replace,      // 完全替换
   }
   ```

2. **添加序列号**：
   ```rust
   pub struct FuzzyFileSearchSessionUpdatedNotification {
       pub session_id: String,
       pub query: String,
       pub files: Vec<FuzzyFileSearchResult>,
       pub sequence: u64,  // 序列号，用于检测乱序
   }
   ```

3. **添加进度信息**：
   ```rust
   pub struct FuzzyFileSearchSessionUpdatedNotification {
       pub session_id: String,
       pub query: String,
       pub files: Vec<FuzzyFileSearchResult>,
       pub progress: SearchProgress,  // 新
   }
   
   pub struct SearchProgress {
       pub files_searched: usize,
       pub total_files: Option<usize>,  // 可能未知
       pub percentage: Option<f32>,
   }
   ```

4. **批量结果**：
   ```rust
   pub struct FuzzyFileSearchSessionUpdatedNotification {
       pub session_id: String,
       pub query: String,
       pub files: Vec<FuzzyFileSearchResult>,
       pub is_final: bool,  // 是否为最后一批结果
   }
   ```

5. **结果排序提示**：
   ```rust
   pub struct FuzzyFileSearchSessionUpdatedNotification {
       // ...
       pub sorted: bool,  // 结果是否已按分数排序
   }
   ```

### 测试建议
- 测试增量更新的累积逻辑
- 测试乱序通知的处理
- 测试重复结果的去重
- 验证大量通知的性能
- 测试查询变更时的状态重置

### 客户端实现建议
- 实现去重机制（基于路径）
- 处理可能的乱序通知
- 使用虚拟列表渲染大量结果
- 实现防抖，避免频繁 UI 更新
- 在收到新查询时重置状态
