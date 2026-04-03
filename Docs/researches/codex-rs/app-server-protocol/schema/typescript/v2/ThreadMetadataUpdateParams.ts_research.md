# ThreadMetadataUpdateParams 类型研究文档

## 场景与职责

`ThreadMetadataUpdateParams` 是 Codex App Server Protocol v2 API 中用于**更新线程元数据**的参数类型。它是 `thread/metadata/update` RPC 方法的请求参数，支持对线程的各种元数据进行增量更新。

### 主要使用场景

- **Git 信息更新**: 更新线程关联的 Git 提交、分支、远程地址
- **会话整理**: 修改线程名称、添加标签等（未来扩展）
- **元数据修复**: 修正错误的元数据信息
- **批量管理**: 通过程序化管理线程元数据

### 架构定位

该类型是线程元数据更新的入口参数，采用**增量更新**设计模式。目前主要支持 Git 信息更新，但结构设计上预留了扩展空间以支持更多元数据类型。

---

## 功能点目的

### 核心字段

| 字段 | 类型 | 目的 |
|------|------|------|
| `threadId` | `string` | 要更新的目标线程 ID（必需） |
| `gitInfo` | `ThreadMetadataGitInfoUpdateParams \| null` | Git 元数据更新（可选） |

### 设计意图

1. **增量更新**: 只更新提供的字段，未提供的字段保持不变
2. **类型安全**: 使用嵌套类型 `ThreadMetadataGitInfoUpdateParams` 封装 Git 特定逻辑
3. **可扩展性**: 结构预留添加更多元数据字段的空间
4. **空值语义**: `gitInfo` 为 `null` 时表示不更新 Git 信息

---

## 具体技术实现

### TypeScript 类型定义

```typescript
import type { ThreadMetadataGitInfoUpdateParams } from "./ThreadMetadataGitInfoUpdateParams";

export type ThreadMetadataUpdateParams = {
  threadId: string,
  /**
   * Patch the stored Git metadata for this thread.
   * Omit a field to leave it unchanged, set it to `null` to clear it, or
   * provide a string to replace the stored value.
   */
  gitInfo?: ThreadMetadataGitInfoUpdateParams | null,
};
```

### Rust 实现细节

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadMetadataUpdateParams {
    pub thread_id: String,
    /// Patch the stored Git metadata for this thread.
    /// Omit a field to leave it unchanged, set it to `null` to clear it, or
    /// provide a string to replace the stored value.
    #[ts(optional = nullable)]
    pub git_info: Option<ThreadMetadataGitInfoUpdateParams>,
}
```

### 关键技术点

1. **嵌套更新**: Git 信息更新委托给专门的 `ThreadMetadataGitInfoUpdateParams` 类型
2. **可选可空**: `#[ts(optional = nullable)]` 生成 TypeScript 的 `?: T | null`
3. **单一职责**: 每个嵌套类型负责特定元数据领域的更新逻辑

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 作用 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 2805-2812) | Rust 类型定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` (line 258-261) | RPC 方法注册 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadMetadataUpdateParams.ts` | TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/ThreadMetadataUpdateParams.json` | JSON Schema |

### 服务端实现

| 文件 | 作用 |
|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs` | 处理 metadata/update 请求 |
| `codex-rs/core/src/state_db/` | 元数据持久化 |

### 测试覆盖

| 文件 | 作用 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_metadata_update.rs` | 元数据更新测试 |

### 关键测试场景

```rust
// 基本更新
async fn thread_metadata_update_patches_git_branch_and_returns_updated_thread() -> Result<()>

// 空更新拒绝
async fn thread_metadata_update_rejects_empty_git_info_patch() -> Result<()>

// 修复缺失的 SQLite 行
async fn thread_metadata_update_repairs_missing_sqlite_row_for_stored_thread() -> Result<()>
async fn thread_metadata_update_repairs_loaded_thread_without_resetting_summary() -> Result<()>
async fn thread_metadata_update_repairs_missing_sqlite_row_for_archived_thread() -> Result<()>

// 清除字段
async fn thread_metadata_update_can_clear_stored_git_fields() -> Result<()>
```

---

## 依赖与外部交互

### 依赖类型

```typescript
import type { ThreadMetadataGitInfoUpdateParams } from "./ThreadMetadataGitInfoUpdateParams";
```

### 嵌套类型结构

```
ThreadMetadataUpdateParams
├── threadId: string                    // 目标线程
└── gitInfo?: ThreadMetadataGitInfoUpdateParams
    ├── sha?: string | null            // 提交哈希
    ├── branch?: string | null         // 分支
    └── originUrl?: string | null      // 远程地址
```

### 数据流

```
ThreadMetadataUpdateParams
    ↓
验证（threadId 存在，至少一个更新字段）
    ↓
查找线程（内存或磁盘）
    ↓
应用更新（委托给各嵌套类型）
    ↓
持久化到 SQLite
    ↓
返回 ThreadMetadataUpdateResponse
```

### 修复机制

服务端实现了自动修复功能：
- 如果 SQLite 中缺少该线程的记录，会自动从 rollout 文件重建
- 支持活跃线程、存储线程和归档线程

---

## 风险、边界与改进建议

### 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **空更新** | 所有可选字段都省略时会报错 | 服务端验证并返回明确错误 |
| **线程不存在** | 更新不存在的线程会失败 | 返回 404 类错误 |
| **并发更新** | 并发修改可能产生竞态 | 数据库事务保证原子性 |

### 边界情况

1. **空 gitInfo**: `gitInfo: {}` 会被视为空更新，返回错误
2. **未加载线程**: 可以更新未加载到内存的线程（会触发修复）
3. **归档线程**: 支持更新已归档线程的元数据

### 改进建议

1. **更多元数据字段**:
   - `name`: 线程名称更新
   - `tags`: 标签系统
   - `notes`: 用户备注
   - `customData`: 自定义键值数据

2. **批量更新**: 支持一次更新多个线程的元数据

3. **条件更新**: 添加 `ifMatch` 字段实现乐观并发控制

4. **更新历史**: 记录元数据变更历史

5. **验证增强**: 
   - 验证 threadId 格式
   - 验证 Git SHA 格式
   - 验证 URL 格式

### 使用示例

```typescript
// 更新 Git 分支
await client.threadMetadataUpdate({
  threadId: "thread-123",
  gitInfo: {
    branch: "feature/new-feature"
  }
});

// 更新完整的 Git 信息
await client.threadMetadataUpdate({
  threadId: "thread-123",
  gitInfo: {
    sha: "abc123def456",
    branch: "main",
    originUrl: "https://github.com/user/repo.git"
  }
});

// 清除 Git 信息
await client.threadMetadataUpdate({
  threadId: "thread-123",
  gitInfo: {
    sha: null,
    branch: null,
    originUrl: null
  }
});
```

### 相关类型

- `ThreadMetadataGitInfoUpdateParams`: Git 特定更新参数
- `ThreadMetadataUpdateResponse`: 更新操作的响应
- `GitInfo`: 响应中返回的 Git 信息结构
- `Thread`: 包含完整元数据的线程对象
