# FileChange Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`FileChange` 是 Codex 协议中用于**表示文件变更**的 tagged union 类型。它封装了 Agent 对文件系统可能执行的所有变更类型，包括添加、删除和更新文件。

**典型使用场景：**
- Agent 应用代码补丁（patch apply）时描述文件变更
- `ApplyPatchApprovalRequest` 中展示待应用的文件变更
- 版本控制集成中描述工作目录的变更
- 文件同步和冲突解决场景

**职责：**
- 统一表示三种基本文件操作：添加、删除、更新
- 为每种操作提供必要的上下文信息（内容、差异等）
- 支持文件移动/重命名（通过 `move_path`）
- 作为审批流程中的变更描述

## 2. 功能点目的 (Purpose of This Type)

该类型的设计目的是：

1. **统一变更表示**：为所有文件操作提供统一的类型表示
2. **审批上下文**：在应用补丁前向用户展示完整的变更列表
3. **差异追踪**：通过 unified diff 精确描述文件更新
4. **支持重命名**：通过 `move_path` 支持文件移动操作

## 3. 具体技术实现 (Technical Implementation Details)

### TypeScript 定义

```typescript
export type FileChange = 
  | { "type": "add", content: string } 
  | { "type": "delete", content: string } 
  | { "type": "update", unified_diff: string, move_path: string | null };
```

### Rust 定义

```rust
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "snake_case")]
#[ts(tag = "type")]
pub enum FileChange {
    Add {
        content: String,
    },
    Delete {
        content: String,
    },
    Update {
        unified_diff: String,
        move_path: Option<PathBuf>,
    },
}
```

### 变体说明

| 变体 | 字段 | 说明 |
|------|------|------|
| `Add` | `content: string` | 新文件的内容 |
| `Delete` | `content: string` | 被删除文件的原始内容（用于恢复） |
| `Update` | `unified_diff: string` | Unified diff 格式的变更描述 |
| `Update` | `move_path: string \| null` | 如果非空，表示文件移动的目标路径 |

### 序列化格式

使用 `#[serde(tag = "type", rename_all = "snake_case")]` 实现 internally tagged union：

```json
// Add
{
  "type": "add",
  "content": "file content here"
}

// Delete
{
  "type": "delete",
  "content": "original file content"
}

// Update
{
  "type": "update",
  "unified_diff": "@@ -1,3 +1,3 @@\n line1\n-line2\n+line2_modified",
  "move_path": null
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 类型定义
- **TypeScript**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/FileChange.ts`
- **Rust**: `/home/sansha/Github/codex/codex-rs/protocol/src/protocol.rs` (lines 3140-3151)

### 相关类型
- `ApplyPatchApprovalRequestEvent` - 使用 `FileChange` 描述待应用的补丁
- `ApplyPatchApprovalParams` - 包含 `file_changes: HashMap<PathBuf, FileChange>`

### 使用位置

1. **审批请求**：
   ```rust
   pub struct ApplyPatchApprovalRequestEvent {
       pub call_id: String,
       pub turn_id: String,
       pub changes: HashMap<PathBuf, FileChange>,
       pub reason: Option<String>,
       pub grant_root: Option<PathBuf>,
   }
   ```

2. **审批参数**：
   ```rust
   pub struct ApplyPatchApprovalParams {
       pub conversation_id: ThreadId,
       pub call_id: String,
       pub file_changes: HashMap<PathBuf, FileChange>,
       pub reason: Option<String>,
       pub grant_root: Option<PathBuf>,
   }
   ```

### 相关事件
- `PatchApplyBeginEvent` - 补丁应用开始
- `PatchApplyEndEvent` - 补丁应用结束

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 协议集成
- 属于 core protocol 类型（在 `protocol` crate 中定义）
- 通过 `ts-rs` 自动生成 TypeScript 类型
- 使用 snake_case 序列化

### 与 Diff 格式的关系

`Update` 变体使用 unified diff 格式：

```
--- a/original.txt
+++ b/modified.txt
@@ -1,3 +1,3 @@
 line 1
-line 2
+line 2 modified
 line 3
```

### 外部交互

1. **Agent → 服务器**：Agent 生成 `FileChange` 描述拟议的变更
2. **服务器 → 客户端**：在审批请求中展示变更列表
3. **客户端 → 服务器**：用户批准后，服务器应用变更
4. **文件系统**：最终变更被写入文件系统

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **Delete 变体的 content 字段**：
   - 包含被删除文件的完整内容
   - 对于大文件，这可能导致内存和传输开销
   - 主要用于恢复功能，但当前未明确使用

2. **Update 的 move_path**：
   - 为 `Option<PathBuf>`，表示可选的文件移动
   - 同时包含 diff 和 move 可能令人困惑

3. **Diff 格式限制**：
   - Unified diff 可能无法表示二进制文件的变更
   - 大文件的 diff 可能非常大

4. **无权限信息**：
   - 不记录文件权限（mode）的变更
   - 只关注内容变更

### 改进建议

1. **添加文件模式支持**：
   ```rust
   pub struct FileChange {
       // ... existing fields
       pub file_mode: Option<u32>,  // Unix file permissions
   }
   ```

2. **二进制文件支持**：
   ```rust
   pub enum FileChange {
       // ... existing variants
       BinaryUpdate {
           old_sha256: String,
           new_sha256: String,
       },
   }
   ```

3. **大文件优化**：
   - 对于 Delete，考虑使用哈希替代完整内容
   - 支持 diff 的流式传输

4. **变更元数据**：
   ```rust
   pub struct FileChange {
       // ... existing fields
       pub change_id: Option<String>,  // 唯一标识
       pub estimated_size: Option<u64>, // 估计大小
   }
   ```

5. **批量变更优化**：
   - 考虑添加 `BatchFileChange` 类型用于大量文件变更
   - 支持压缩传输

### 测试建议
- 验证所有变体的序列化和反序列化
- 测试大文件（>1MB）的变更处理
- 验证包含特殊字符的文件路径
- 测试 move_path 与 diff 的组合场景

### 安全考虑
- `content` 字段可能包含敏感信息
- 审批 UI 应对大变更提供警告
- 考虑添加变更大小的限制
