# ThreadMetadataUpdateResponse.json 研究文档

## 场景与职责

`ThreadMetadataUpdateResponse` 是 Codex App-Server Protocol v2 API 中 `thread/metadata/update` 请求的响应结构。该响应用于确认线程元数据更新操作的成功执行，并返回更新后的线程完整信息。

**核心场景：**
1. **Git 元数据修补** - 允许客户端更新线程关联的 Git 信息（分支、SHA、origin URL）
2. **线程元数据修复** - 当 SQLite 数据库中的线程记录缺失时，通过此操作自动修复
3. **线程信息同步** - 在元数据变更后，客户端获取最新的线程状态

**典型使用流程：**
```
Client -> thread/metadata/update (ThreadMetadataUpdateParams) -> Server
Server -> ThreadMetadataUpdateResponse { thread: updated_thread } -> Client
```

## 功能点目的

### 1. 响应结构设计

```json
{
  "thread": { /* Thread 对象 */ }
}
```

**设计意图：**
- **单一职责**：响应只包含更新后的 `Thread` 对象，保持简洁
- **数据一致性**：返回完整的线程对象，确保客户端状态与服务器同步
- **不可变性**：响应是只读的，客户端通过新的请求发起后续修改

### 2. 关联的请求参数 (ThreadMetadataUpdateParams)

```rust
pub struct ThreadMetadataUpdateParams {
    pub thread_id: String,
    pub git_info: Option<ThreadMetadataGitInfoUpdateParams>,
}
```

**Git 信息更新参数特点：**
- 使用 `Option<Option<String>>` 三层嵌套实现三种语义：
  - `None` - 不修改该字段
  - `Some(None)` - 清除该字段
  - `Some(Some(value))` - 设置为新值

### 3. 与 Thread 结构体的关系

`ThreadMetadataUpdateResponse` 包含完整的 `Thread` 对象，其中与元数据相关的字段包括：
- `git_info: Option<GitInfo>` - Git 元数据（SHA、分支、origin URL）
- `name: Option<String>` - 用户自定义线程名称
- `updated_at: i64` - 最后更新时间戳

## 具体技术实现

### 1. Rust 源码定义

**文件路径：** `codex-rs/app-server-protocol/src/protocol/v2.rs`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadMetadataUpdateResponse {
    pub thread: Thread,
}
```

**关键属性：**
- `#[serde(rename_all = "camelCase")]` - 字段使用 camelCase 序列化
- `#[ts(export_to = "v2/")]` - TypeScript 类型导出到 v2/ 目录
- `JsonSchema` - 自动生成 JSON Schema
- `TS` - 自动生成 TypeScript 类型定义

### 2. JSON Schema 生成

**生成方式：** 通过 `schemars`  crate 在编译时自动生成

**Schema 特点：**
- `$schema`: `http://json-schema.org/draft-07/schema#`
- 包含 `Thread` 结构体的完整定义（内联展开）
- 所有字段标记为 `required`，无可选字段

### 3. 服务器端处理流程

**文件路径：** `codex-rs/app-server/src/codex_message_processor.rs`

```rust
async fn thread_metadata_update(&mut self, request_id: ConnectionRequestId, params: ThreadMetadataUpdateParams) {
    // 1. 解析 thread_id
    // 2. 验证 git_info 参数非空
    // 3. 加载或修复线程元数据
    // 4. 应用 Git 信息补丁
    // 5. 持久化到 SQLite 和 rollout 文件
    // 6. 发送 ThreadMetadataUpdateResponse
    self.outgoing
        .send_response(request_id, ThreadMetadataUpdateResponse { thread })
        .await;
}
```

### 4. 测试覆盖

**测试文件：** `codex-rs/app-server/tests/suite/v2/thread_metadata_update.rs`

**核心测试用例：**
1. `thread_metadata_update_patches_git_branch_and_returns_updated_thread` - 验证 Git 分支更新
2. `thread_metadata_update_rejects_empty_git_info_patch` - 验证空补丁拒绝
3. `thread_metadata_update_repairs_missing_sqlite_row_for_stored_thread` - 验证缺失记录修复
4. `thread_metadata_update_repairs_loaded_thread_without_resetting_summary` - 验证加载线程修复
5. `thread_metadata_update_repairs_missing_sqlite_row_for_archived_thread` - 验证归档线程修复
6. `thread_metadata_update_can_clear_stored_git_fields` - 验证字段清除功能

## 关键代码路径与文件引用

### 协议定义
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:2850-2855` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs:2802-2848` | ThreadMetadataUpdateParams 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3475-3512` | Thread 结构体定义 |

### 服务器实现
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs:2520-2530` | 请求处理方法 |
| `codex-rs/app-server/src/codex_message_processor.rs:130-132` | 类型导入 |

### 生成的 Schema/类型
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadMetadataUpdateResponse.json` | JSON Schema（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadMetadataUpdateResponse.ts` | TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | 合并的 v2 Schema |

### 测试
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_metadata_update.rs` | 集成测试 |

## 依赖与外部交互

### 1. 上游依赖（被调用方）

```
ThreadMetadataUpdateResponse
  └── Thread
       ├── ThreadId (codex_protocol)
       ├── ThreadStatus
       ├── SessionSource
       ├── GitInfo
       └── Turn (可选，为空数组)
```

### 2. 下游依赖（调用方）

```
thread/metadata/update RPC
  └── ThreadMetadataUpdateResponse
       └── Client (VSCode/TUI/CLI)
```

### 3. 数据流

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Client        │────▶│  App Server      │────▶│   Core/State    │
│                 │     │                  │     │                 │
│ metadata/update │     │ thread_metadata_ │     │ SQLite/Rollout  │
│    request      │     │ update()         │     │   persistence   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                       │                       │
         │                       ▼                       │
         │              ┌──────────────────┐            │
         │              │ ThreadMetadata   │            │
         │              │ UpdateResponse   │            │
         │              │ { thread }       │            │
         │              └──────────────────┘            │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Client State   │◀────│  Response sent   │◀────│  Metadata saved │
│   Updated       │     │  via WebSocket   │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

### 4. 相关协议方法

| 方法 | 方向 | 说明 |
|------|------|------|
| `thread/metadata/update` | Client → Server | 请求更新元数据 |
| `thread/read` | Client → Server | 读取线程信息（验证更新） |
| `thread/name/set` | Client → Server | 设置线程名称（独立操作） |

## 风险、边界与改进建议

### 1. 已知风险

**风险 1：SQLite 行缺失的自动修复**
- **描述**：当 SQLite 中缺少线程记录时，服务器会自动从 rollout 文件重建
- **影响**：可能导致短暂的性能开销，或在极端情况下数据不一致
- **缓解**：测试覆盖 `repairs_missing_sqlite_row` 场景

**风险 2：Git 信息的三层 Option 语义复杂**
- **描述**：`Option<Option<String>>` 对 API 使用者不够直观
- **影响**：客户端开发者可能误解如何清除字段 vs 不修改字段
- **缓解**：文档明确说明三种语义，测试验证清除功能

**风险 3：线程名称与元数据更新的分离**
- **描述**：线程名称通过 `thread/name/set` 修改，而非 `thread/metadata/update`
- **影响**：API 分散，客户端需要调用不同方法修改不同元数据
- **现状**：`ThreadNameUpdatedNotification` 独立通知名称变更

### 2. 边界情况

| 场景 | 行为 |
|------|------|
| 空 git_info 补丁 | 返回错误：`"gitInfo must include at least one field"` |
| 不存在的 thread_id | 返回标准错误响应（线程未找到） |
| 归档线程更新 | 支持，自动从归档目录加载 |
| 并发更新 | 依赖 SQLite 事务，无显式乐观锁 |

### 3. 改进建议

**建议 1：统一元数据更新接口**
```rust
// 当前：仅支持 git_info
pub struct ThreadMetadataUpdateParams {
    pub thread_id: String,
    pub git_info: Option<ThreadMetadataGitInfoUpdateParams>,
}

// 建议：扩展为通用元数据补丁
pub struct ThreadMetadataUpdateParams {
    pub thread_id: String,
    pub git_info: Option<ThreadMetadataGitInfoUpdateParams>,
    pub name: Option<Option<String>>, // 统一名称修改
    pub labels: Option<Vec<String>>,  // 未来扩展
}
```

**建议 2：添加版本控制（ETag）**
- 为 Thread 添加 `version` 或 `etag` 字段
- 支持条件更新，防止并发修改冲突

**建议 3：批量更新支持**
- 支持一次请求更新多个线程的元数据
- 减少客户端-服务器往返次数

**建议 4：增强通知机制**
- 当前：仅响应返回更新后的线程
- 建议：广播 `ThreadMetadataUpdatedNotification` 给所有订阅该线程的客户端
- 场景：多客户端同时查看同一线程时保持同步

### 4. 测试缺口

| 缺口 | 优先级 | 说明 |
|------|--------|------|
| 并发更新测试 | 中 | 验证多客户端同时更新的行为 |
| 大负载性能测试 | 低 | 大量元数据更新的响应时间 |
| 网络中断恢复 | 低 | 更新过程中连接中断的处理 |
