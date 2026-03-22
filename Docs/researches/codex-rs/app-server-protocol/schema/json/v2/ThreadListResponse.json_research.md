# ThreadListResponse.json 研究文档

## 场景与职责

`ThreadListResponse.json` 是 Codex App Server Protocol v2 API 的 JSON Schema 定义文件，定义了 `thread/list` 方法的响应结构。该响应返回经过过滤和分页的线程列表，包含每个线程的完整元数据、状态和关联信息。

**主要使用场景：**
- 客户端获取历史会话列表展示
- 分页加载大量会话数据
- 获取会话状态（idle/active/systemError 等）
- 显示会话标题、预览、Git 信息等元数据

## 功能点目的

### 1. 响应结构 (ThreadListResponse)

| 字段 | 类型 | 说明 |
|------|------|------|
| `data` | Thread[] | 线程对象数组（必需） |
| `nextCursor` | string? | 下一页游标，null 表示无更多数据 |

### 2. Thread 对象

每个线程包含丰富的元数据：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 线程唯一标识符（UUID） |
| `createdAt` | integer | 创建时间戳（Unix 秒） |
| `updatedAt` | integer | 最后更新时间戳（Unix 秒） |
| `cliVersion` | string | 创建该线程的 CLI 版本 |
| `cwd` | string | 工作目录 |
| `modelProvider` | string | 模型提供商 |
| `name` | string? | 用户设置的线程标题 |
| `preview` | string | 预览文本（通常是第一条用户消息） |
| `source` | SessionSource | 会话来源（cli/vscode/exec/appServer/subAgent） |
| `status` | ThreadStatus | 当前状态（notLoaded/idle/systemError/active） |
| `ephemeral` | boolean | 是否为临时线程（不持久化） |
| `path` | string? | 磁盘路径（unstable） |
| `gitInfo` | GitInfo? | Git 元数据（分支、commit、origin） |
| `turns` | Turn[] | 回合列表（thread/list 中为空） |
| `agentNickname` | string? | 子代理昵称 |
| `agentRole` | string? | 子代理角色 |

### 3. 嵌套类型

该 Schema 包含大量嵌套类型定义：

- **ThreadStatus**: 线程状态枚举
  - `notLoaded` - 未加载
  - `idle` - 空闲
  - `systemError` - 系统错误
  - `active` - 活跃（包含 `activeFlags`）

- **SessionSource**: 会话来源
  - 简单来源：`cli`, `vscode`, `exec`, `appServer`, `unknown`
  - 子代理来源：`subAgent`（包含 SubAgentSource 详情）

- **GitInfo**: Git 元数据
  - `sha`: commit hash
  - `branch`: 分支名
  - `originUrl`: 远程仓库 URL

## 具体技术实现

### 关键流程

1. **响应构造流程** (`codex_message_processor.rs:3035-3114`):
```rust
async fn thread_list(&self, request_id: ConnectionRequestId, params: ThreadListParams) {
    // 1. 解析参数并设置默认值
    // 2. 调用 list_threads_common() 获取线程摘要
    // 3. 转换摘要为 Thread 对象
    // 4. 查询线程名称（从文件系统）
    // 5. 查询线程状态（从 ThreadWatchManager）
    // 6. 组装 ThreadListResponse
}
```

2. **状态解析**:
   - 未加载线程：从文件系统读取，状态为 `notLoaded`
   - 已加载线程：从 `ThreadWatchManager` 获取实时状态
   - 状态可能为 `idle`, `active`, `systemError`

3. **名称解析**:
   - 从 `.codex/thread_names/` 目录读取
   - 文件名为线程 ID，内容为标题

### 数据结构

**Rust 结构定义** (`app-server-protocol/src/protocol/v2.rs:2989-2997`):
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadListResponse {
    pub data: Vec<Thread>,
    pub next_cursor: Option<String>,
}
```

**Thread 结构** (`app-server-protocol/src/protocol/v2.rs` 中 Thread 定义）:
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct Thread {
    pub id: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub cli_version: String,
    pub cwd: PathBuf,
    pub model_provider: String,
    pub name: Option<String>,
    pub preview: String,
    pub source: SessionSource,
    pub status: ThreadStatus,
    pub ephemeral: bool,
    pub path: Option<PathBuf>,
    pub git_info: Option<GitInfo>,
    pub turns: Vec<Turn>,
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
}
```

### 转换逻辑

从内部 `ConversationSummary` 转换为 `Thread`:

```rust
fn summary_to_thread(summary: ConversationSummary) -> Thread {
    Thread {
        id: summary.conversation_id.to_string(),
        created_at: summary.created_at.timestamp(),
        updated_at: summary.updated_at.timestamp(),
        cli_version: summary.cli_version,
        cwd: summary.cwd,
        model_provider: summary.model_provider,
        name: None, // 后续填充
        preview: summary.preview,
        source: summary.source.into(),
        status: ThreadStatus::NotLoaded, // 后续更新
        ephemeral: false,
        path: summary.path,
        git_info: summary.git_info.map(|g| g.into()),
        turns: Vec::new(), // thread/list 中为空
        agent_nickname: summary.agent_nickname,
        agent_role: summary.agent_role,
    }
}
```

## 关键代码路径与文件引用

### 核心实现

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:2989-2997` | ThreadListResponse 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Thread 结构定义（约 941-1053 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs:283-286` | ClientRequest 枚举中注册 thread/list 方法 |
| `codex-rs/app-server/src/codex_message_processor.rs:3035-3114` | thread_list 方法实现 |
| `codex-rs/app-server/src/codex_message_processor.rs:7859-7890` | summary_from_thread_list_item 辅助函数 |

### 测试代码

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_list.rs` | 完整的功能测试套件 |
| `codex-rs/app-server/tests/suite/v2/thread_list.rs:163-185` | 空列表响应测试 |
| `codex-rs/app-server/tests/suite/v2/thread_list.rs:313-401` | 分页和 nextCursor 测试 |
| `codex-rs/app-server/tests/suite/v2/thread_list.rs:954-999` | Git 信息包含测试 |

### 生成的 Schema 和类型

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadListResponse.json` | JSON Schema 定义（本文件，约 45KB） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadListResponse.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts` | Thread 类型定义 |

## 依赖与外部交互

### 上游依赖

1. **Core 类型** (`codex_protocol`):
   - `ConversationSummary` - 内部线程摘要
   - `SessionSource` - 会话来源
   - `GitInfo` - Git 元数据

2. **ThreadWatchManager**:
   - 提供已加载线程的实时状态
   - `loaded_statuses_for_threads()` 方法

3. **文件系统**:
   - `find_thread_names_by_ids()` - 读取线程标题
   - 扫描 `sessions/` 和 `archived_sessions/` 目录

### 下游消费

1. **VSCode 扩展**: 历史会话列表 UI
2. **TUI 客户端**: `tui_app_server/src/resume_picker.rs`
3. **CLI 客户端**: 会话恢复选择器

### 相关请求

- `ThreadListParams` - 请求参数
- `ThreadReadParams` - 获取单个线程详情（包含 turns）

## 风险、边界与改进建议

### 已知风险

1. **数据一致性**:
   - 线程状态可能滞后（基于轮询）
   - 文件系统和 SQLite 状态可能不一致

2. **性能问题**:
   - 大量线程时，逐个查询名称和状态较慢
   - 可考虑批量查询优化

3. **内存占用**:
   - Schema 文件较大（约 45KB），包含大量嵌套定义
   - 每个 Thread 对象包含完整元数据

### 边界情况

1. **Turns 为空**:
   - `thread/list` 返回的 Thread 中 `turns` 总是为空数组
   - 需要调用 `thread/read` 获取完整历史

2. **Ephemeral 线程**:
   - 临时线程不出现在列表中
   - 需要通过 `thread/loaded/list` 获取

3. **Path 字段**:
   - 标记为 `[UNSTABLE]`，不建议依赖
   - 可能在未来版本中移除或更改

4. **Name 延迟加载**:
   - 线程名称从单独的文件系统查询
   - 如果查询失败，name 为 null

### 改进建议

1. **字段精简**:
   - 考虑为列表视图提供精简版 Thread（不含 turns 等）
   - 减少数据传输量

2. **实时状态**:
   - 使用 WebSocket 推送状态变更
   - 减少轮询开销

3. **批量操作**:
   - 支持批量获取线程详情
   - 减少多次往返

4. **缓存策略**:
   - 客户端缓存线程元数据
   - ETag 或版本号支持

5. **Schema 优化**:
   - 拆分嵌套类型到独立 schema 文件
   - 便于维护和复用
