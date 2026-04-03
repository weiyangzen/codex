# api.rs 研究文档

## 场景与职责

`api.rs` 是 `codex-cloud-tasks-client` crate 的核心 API 定义文件，负责定义与 Codex Cloud 任务服务交互的抽象接口和数据模型。它是整个 cloud-tasks-client 的契约层，为上层应用（如 TUI、CLI）提供统一的数据结构和 trait 定义。

该模块的主要使用场景：
- 定义云任务（Cloud Task）领域模型（任务状态、摘要、尝试等）
- 提供后端抽象接口 `CloudBackend`，支持多种实现（HTTP 客户端、Mock 客户端）
- 标准化错误类型 `CloudTaskError`，统一处理各类失败场景

## 功能点目的

### 1. 错误处理体系 (`CloudTaskError`)

定义了四种错误类型：
- `Unimplemented`: 功能未实现（用于 Mock 或占位实现）
- `Http(String)`: HTTP 请求失败
- `Io(String)`: IO 操作失败
- `Msg(String)`: 通用错误消息

### 2. 核心数据类型

| 类型 | 用途 |
|------|------|
| `TaskId` | 任务唯一标识符（String 包装器） |
| `TaskStatus` | 任务状态枚举：Pending/Ready/Applied/Error |
| `TaskSummary` | 任务列表项摘要信息 |
| `TaskListPage` | 分页任务列表（含游标） |
| `DiffSummary` | 代码变更统计（文件数、增删行数） |
| `TaskText` | 任务的文本内容（prompt + messages） |
| `TurnAttempt` | Best-of-N 尝试的单个结果 |
| `AttemptStatus` | 尝试状态：Pending/InProgress/Completed/Failed/Cancelled/Unknown |
| `ApplyOutcome` | 补丁应用结果（成功/部分/失败） |
| `CreatedTask` | 新建任务返回结果 |

### 3. CloudBackend Trait

定义了 9 个异步方法，覆盖完整的任务生命周期：

```rust
// 任务列表与查询
async fn list_tasks(&self, env, limit, cursor) -> Result<TaskListPage>;
async fn get_task_summary(&self, id) -> Result<TaskSummary>;
async fn get_task_diff(&self, id) -> Result<Option<String>>;
async fn get_task_messages(&self, id) -> Result<Vec<String>>;
async fn get_task_text(&self, id) -> Result<TaskText>;

// Best-of-N 尝试管理
async fn list_sibling_attempts(&self, task, turn_id) -> Result<Vec<TurnAttempt>>;

// 补丁应用（预检/实际）
async fn apply_task_preflight(&self, id, diff_override) -> Result<ApplyOutcome>;
async fn apply_task(&self, id, diff_override) -> Result<ApplyOutcome>;

// 创建任务
async fn create_task(&self, env_id, prompt, git_ref, qa_mode, best_of_n) -> Result<CreatedTask>;
```

## 具体技术实现

### 序列化配置

- `TaskId`: 使用 `#[serde(transparent)]` 透明序列化为字符串
- `TaskStatus`: 使用 kebab-case（`"kebab-case"`）序列化
- `ApplyStatus`: 使用 lowercase（`"lowercase"`）序列化

### AttemptStatus 的特殊处理

`AttemptStatus` **没有**使用 serde 派生，因为它主要用于内部状态管理而非网络传输。其默认值为 `Unknown`。

### TaskText 的默认值

为 `TaskText` 手动实现了 `Default`，确保：
- `messages` 和 `sibling_turn_ids` 为空 Vec
- `attempt_status` 默认为 `Unknown`
- 可选字段为 `None`

## 关键代码路径与文件引用

```
codex-rs/cloud-tasks-client/src/api.rs
├── 错误定义 (lines 8-18)
├── 数据类型定义 (lines 20-131)
│   ├── TaskId, TaskStatus, TaskSummary
│   ├── AttemptStatus, TurnAttempt
│   ├── ApplyStatus, ApplyOutcome
│   ├── CreatedTask, TaskListPage
│   ├── DiffSummary, TaskText
│   └── TaskText::Default 实现
└── CloudBackend trait (lines 133-170)
```

**被调用方**（实现该 trait）：
- `http.rs`: `HttpClient` - 真实的 HTTP 后端实现
- `mock.rs`: `MockClient` - 测试用的 Mock 实现

**调用方**（使用 trait）：
- `codex-rs/cloud-tasks/src/app.rs`: TUI 应用逻辑
- `codex-rs/cloud-tasks/src/cli.rs`: CLI 命令处理

## 依赖与外部交互

### 外部依赖

| crate | 用途 |
|-------|------|
| `chrono` | 时间戳处理 (`DateTime<Utc>`) |
| `serde` | 序列化/反序列化 |
| `thiserror` | 错误类型派生 |
| `async-trait` | 异步 trait 支持（在 trait 定义中隐含） |

### 内部依赖

无直接内部依赖，作为底层 API 定义模块。

## 风险、边界与改进建议

### 当前风险

1. **AttemptStatus 序列化缺失**: `AttemptStatus` 未实现 serde，如果需要网络传输会出问题
2. **TaskId 透明序列化**: 虽然简洁，但失去了类型安全性（任何字符串都可隐式转换）
3. **错误类型粒度不足**: `Http(String)` 和 `Io(String)` 仅包含字符串消息，缺少结构化错误码

### 边界情况

1. **时间戳解析**: `TaskSummary.updated_at` 使用 `DateTime<Utc>`，依赖后端返回正确格式
2. **可选字段**: `TaskSummary.environment_id/label` 可能为 None，调用方需处理
3. **Best-of-N**: `attempt_total` 为 `Option<usize>`，旧版后端可能不返回此字段

### 改进建议

1. **增强错误类型**:
   ```rust
   pub enum CloudTaskError {
       Http { status: u16, message: String },
       Io { path: PathBuf, error: std::io::Error },
       // ...
   }
   ```

2. **为 AttemptStatus 添加 serde 支持**（如果需要网络传输）

3. **TaskId 类型安全**:
   ```rust
   #[derive(Debug, Clone, PartialEq, Eq)]
   pub struct TaskId(String); // 移除 transparent，显式转换
   ```

4. **分页游标类型化**: 当前 `cursor` 是 `Option<String>`，可考虑包装为 `Cursor` 类型

5. **文档完善**: 为 `CloudBackend` 各方法添加更详细的文档说明，特别是错误场景
