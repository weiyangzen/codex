# TurnDiffUpdatedNotification.json 研究文档

## 场景与职责

`TurnDiffUpdatedNotification` 是 Codex App-Server Protocol v2 中定义的服务器向客户端发送的通知类型，用于实时报告 Turn（对话轮次）级别的统一差异（unified diff）更新。这是文件变更追踪的核心机制，让客户端能够实时看到 AI 对代码库所做的所有修改的聚合差异视图。

典型使用场景：
- AI 助手在单次对话中修改多个文件
- 客户端需要显示所有文件变更的汇总 diff
- 代码审查场景下展示完整的变更集
- 实时预览 AI 生成的代码修改

## 功能点目的

该通知的主要目的是：
1. **变更聚合**：聚合单个 Turn 中所有文件变更的差异
2. **实时预览**：让用户在 Turn 完成前就能看到变更内容
3. **代码审查**：支持对 AI 生成的变更进行审查
4. **版本控制**：提供类似 Git diff 的变更视图

### Diff 更新流程

```
Turn 开始
  ├── FileChange item 开始 (文件1)
  │     └── FileChangeOutputDeltaNotification (增量更新)
  ├── FileChange item 开始 (文件2)
  │     └── FileChangeOutputDeltaNotification (增量更新)
  ├── ...
  └── TurnDiffUpdatedNotification (聚合 diff 更新)
        └── TurnCompletedNotification (Turn 完成)
```

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Notification that the turn-level unified diff has changed. Contains the latest aggregated diff across all file changes in the turn.",
  "properties": {
    "diff": { "type": "string" },
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["diff", "threadId", "turnId"]
}
```

### Rust 实现

位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`（行 4711-4720）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// Notification that the turn-level unified diff has changed.
/// Contains the latest aggregated diff across all file changes in the turn.
pub struct TurnDiffUpdatedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub diff: String,
}
```

### 服务端注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
server_notification_definitions! {
    TurnDiffUpdated => "turn/diff/updated" (v2::TurnDiffUpdatedNotification),
    // ...
}
```

### 差异内容格式

`diff` 字段包含统一差异格式（unified diff）的文本，例如：

```diff
--- a/src/main.rs
+++ b/src/main.rs
@@ -1,5 +1,5 @@
 fn main() {
-    println!("Hello, world!");
+    println!("Hello, Codex!");
 }
 
--- a/src/lib.rs
+++ b/src/lib.rs
@@ -10,3 +10,7 @@
 pub fn add(a: i32, b: i32) -> i32 {
     a + b
 }
+
+pub fn subtract(a: i32, b: i32) -> i32 {
+    a - b
+}
```

## 关键代码路径与文件引用

### 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/TurnDiffUpdatedNotification.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（行 4711-4720） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 服务器通知注册（行 889） |

### 服务端发送代码

位于 `codex-rs/app-server/src/bespoke_event_handling.rs`：
- 监听文件变更事件
- 聚合单个 Turn 中的所有文件变更
- 生成统一差异格式
- 发送 `TurnDiffUpdatedNotification`

### 相关通知

| 通知类型 | 说明 |
|---------|------|
| `FileChangeOutputDeltaNotification` | 单个文件变更的增量更新 |
| `ItemStartedNotification` | 项目开始通知 |
| `ItemCompletedNotification` | 项目完成通知 |

## 依赖与外部交互

### 上游依赖

1. **文件变更追踪**：需要追踪 Turn 中所有文件变更
2. **差异生成**：需要生成统一差异格式
3. **Patch 系统**：基于 `PatchChangeKind` 的变更类型

### 下游消费者

1. **代码审查 UI**：显示聚合 diff 供用户审查
2. **文件浏览器**：高亮显示变更的文件
3. **版本控制集成**：可能将 diff 提交到 Git

### 相关类型

| 类型 | 说明 |
|------|------|
| `FileUpdateChange` | 单个文件变更 |
| `PatchChangeKind` | 变更类型（Add/Delete/Update） |
| `PatchApplyStatus` | 补丁应用状态 |

## 风险、边界与改进建议

### 潜在风险

1. **Diff 体积过大**：大量文件变更时，diff 字符串可能非常大
2. **增量更新频繁**：频繁的文件变更可能导致大量通知
3. **编码问题**：diff 中的非 ASCII 字符可能需要特殊处理

### 边界情况

1. **空 diff**：没有文件变更时，diff 可能为空字符串
2. **二进制文件**：二进制文件的 diff 表示
3. **大文件**：大文件的 diff 可能截断
4. **并发修改**：文件在生成 diff 期间被外部修改

### 改进建议

1. **Diff 压缩**：对于大 diff，考虑使用压缩或分页
2. **增量 diff**：只发送自上次通知以来的变更
3. **Diff 选项**：支持配置 diff 格式（context lines 数量等）
4. **语法高亮**：添加语言信息以支持语法高亮
5. **统计信息**：添加变更统计（添加/删除行数）

### 客户端处理示例

```typescript
// 示例：客户端处理 TurnDiffUpdatedNotification
function handleTurnDiffUpdated(notification: TurnDiffUpdatedNotification) {
    const { threadId, turnId, diff } = notification;
    
    if (!diff) {
        console.log('没有文件变更');
        return;
    }
    
    // 解析 diff 提取文件变更
    const fileChanges = parseDiff(diff);
    
    // 更新 UI
    updateDiffView({
        threadId,
        turnId,
        fileChanges,
        stats: calculateDiffStats(diff)
    });
    
    // 高亮变更的文件
    highlightChangedFiles(fileChanges.map(fc => fc.path));
}

// 解析统一差异格式
function parseDiff(diff: string): FileChange[] {
    const changes: FileChange[] = [];
    const lines = diff.split('\n');
    // ... 解析逻辑
    return changes;
}
```

### 版本兼容性

- 当前为 v2 API，遵循 camelCase 命名规范
- Diff 格式遵循标准 unified diff 格式
- 与 v1 API 不兼容
