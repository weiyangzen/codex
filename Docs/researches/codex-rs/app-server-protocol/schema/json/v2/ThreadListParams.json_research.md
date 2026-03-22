# ThreadListParams.json 研究文档

## 场景与职责

`ThreadListParams.json` 是 Codex App Server Protocol v2 API 的 JSON Schema 定义文件，定义了 `thread/list` 方法的请求参数结构。该参数用于查询和过滤服务器上存储的线程（会话）列表，支持分页、排序和多维度过滤。

**主要使用场景：**
- 客户端启动时加载历史会话列表
- 实现分页浏览大量历史会话
- 按提供商、来源类型、归档状态等维度过滤会话
- 搜索特定标题或内容的会话

## 功能点目的

### 1. 分页参数

| 字段 | 类型 | 说明 |
|------|------|------|
| `cursor` | string? | 分页游标，用于获取下一页结果 |
| `limit` | integer? | 每页大小，默认服务器端设定值，最大 100 |

### 2. 排序参数

| 字段 | 类型 | 说明 |
|------|------|------|
| `sortKey` | ThreadSortKey? | 排序键，支持 `created_at` 或 `updated_at` |

### 3. 过滤参数

| 字段 | 类型 | 说明 |
|------|------|------|
| `modelProviders` | string[]? | 按模型提供商过滤（如 openai） |
| `sourceKinds` | ThreadSourceKind[]? | 按会话来源类型过滤 |
| `archived` | boolean? | 归档状态过滤，true=仅归档，false/null=非归档 |
| `cwd` | string? | 按工作目录精确匹配过滤 |
| `searchTerm` | string? | 按标题子串搜索（需要 SQLite 支持） |

### 4. 来源类型枚举 (ThreadSourceKind)

定义了会话的创建来源：
- `cli` - 命令行界面
- `vscode` - VSCode 扩展
- `exec` - 执行模式（非交互式）
- `appServer` - App Server 直接创建
- `subAgent` - 子代理（通用）
- `subAgentReview` - 审查子代理
- `subAgentCompact` - 压缩子代理
- `subAgentThreadSpawn` - 线程派生子代理
- `subAgentOther` - 其他子代理
- `unknown` - 未知来源

## 具体技术实现

### 关键流程

1. **请求处理流程** (`codex_message_processor.rs:3035`):
```rust
async fn thread_list(&self, request_id: ConnectionRequestId, params: ThreadListParams) {
    // 1. 解析分页参数（limit 默认 20，最大 100）
    // 2. 转换排序键（created_at/updated_at）
    // 3. 调用 list_threads_common() 获取线程摘要
    // 4. 查询线程名称和状态
    // 5. 构造 ThreadListResponse 返回
}
```

2. **过滤逻辑**:
   - `model_providers`: 限制特定提供商的线程
   - `source_kinds`: 空数组默认只返回交互式来源（cli, vscode, appServer）
   - `archived`: 控制是否包含归档线程
   - `cwd`: 精确匹配工作目录路径
   - `search_term`: 需要 SQLite 支持，搜索线程标题

3. **分页实现**:
   - 使用游标（cursor）而非偏移量
   - 游标是编码后的位置信息
   - 最后一页返回 `nextCursor: null`

### 数据结构

**Rust 结构定义** (`app-server-protocol/src/protocol/v2.rs:2929-2961`):
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadListParams {
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
    #[ts(optional = nullable)]
    pub sort_key: Option<ThreadSortKey>,
    #[ts(optional = nullable)]
    pub model_providers: Option<Vec<String>>,
    #[ts(optional = nullable)]
    pub source_kinds: Option<Vec<ThreadSourceKind>>,
    #[ts(optional = nullable)]
    pub archived: Option<bool>,
    #[ts(optional = nullable)]
    pub cwd: Option<String>,
    #[ts(optional = nullable)]
    pub search_term: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub enum ThreadSortKey {
    CreatedAt,
    UpdatedAt,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase", export_to = "v2/")]
pub enum ThreadSourceKind {
    Cli,
    #[serde(rename = "vscode")]
    #[ts(rename = "vscode")]
    VsCode,
    Exec,
    AppServer,
    SubAgent,
    SubAgentReview,
    SubAgentCompact,
    SubAgentThreadSpawn,
    SubAgentOther,
    Unknown,
}
```

### 常量定义

```rust
const THREAD_LIST_DEFAULT_LIMIT: usize = 20;
const THREAD_LIST_MAX_LIMIT: usize = 100;
```

## 关键代码路径与文件引用

### 核心实现

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:2929-2961` | ThreadListParams 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs:2963-2987` | ThreadSourceKind 枚举定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs:2981-2987` | ThreadSortKey 枚举定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:283-286` | ClientRequest 枚举中注册 thread/list 方法 |
| `codex-rs/app-server/src/codex_message_processor.rs:3035-3114` | thread_list 方法实现 |

### 测试代码

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_list.rs` | 完整的功能测试套件 |
| `codex-rs/app-server/tests/suite/v2/thread_list.rs:163-185` | 空列表测试 |
| `codex-rs/app-server/tests/suite/v2/thread_list.rs:313-401` | 分页游标测试 |
| `codex-rs/app-server/tests/suite/v2/thread_list.rs:403-454` | 提供商过滤测试 |
| `codex-rs/app-server/tests/suite/v2/thread_list.rs:456-514` | CWD 过滤测试 |
| `codex-rs/app-server/tests/suite/v2/thread_list.rs:516-591` | 搜索词测试 |
| `codex-rs/app-server/tests/suite/v2/thread_list.rs:593-637` | 来源类型默认过滤测试 |
| `codex-rs/app-server/tests/suite/v2/thread_list.rs:639-690` | SubAgent 派生过滤测试 |
| `codex-rs/app-server/tests/suite/v2/thread_list.rs:692-799` | 子代理变体过滤测试 |

### 生成的 Schema 和类型

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadListParams.json` | JSON Schema 定义（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadListParams.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | 合并的 v2 schemas |

## 依赖与外部交互

### 上游依赖

1. **ThreadManager** (`codex_core::ThreadManager`):
   - 提供线程列表查询能力
   - 管理线程生命周期

2. **State DB** (`codex_state::StateRuntime`):
   - SQLite 数据库存储线程元数据
   - 支持搜索词查询（需要 `sqlite` 特性）

3. **文件系统**:
   - 扫描 `sessions/` 目录查找 rollout 文件
   - 归档目录 `archived_sessions/`

### 下游消费

1. **VSCode 扩展**: 历史会话列表 UI
2. **TUI 客户端**: `tui_app_server/src/resume_picker.rs`
3. **CLI 客户端**: 会话恢复选择器

### 相关响应

- `ThreadListResponse` - 包含 `data`（Thread 数组）和 `nextCursor`

## 风险、边界与改进建议

### 已知风险

1. **SQLite 依赖**:
   - `search_term` 功能需要 SQLite 支持
   - 如果 SQLite 未启用或未完成回填，搜索功能不可用

2. **性能问题**:
   - 大量线程（>1000）时列表查询可能变慢
   - 文件系统扫描比数据库查询慢

3. **游标过期**:
   - 分页过程中线程被删除可能导致游标失效
   - 当前实现可能返回空结果而非错误

### 边界情况

1. **来源类型默认值**:
   - `source_kinds` 为空数组时，默认只返回交互式来源
   - 要获取所有来源，需要显式指定所有 `ThreadSourceKind` 变体

2. **归档线程**:
   - 默认不包含归档线程
   - 需要显式设置 `archived: true`

3. **Limit 限制**:
   - 超过 100 会被截断到 100
   - 小于 1 会被调整到 1

### 改进建议

1. **搜索功能增强**:
   - 支持全文搜索（当前仅标题）
   - 支持按时间范围过滤
   - 支持多关键词搜索

2. **排序选项**:
   - 增加按名称排序
   - 支持倒序排序（当前总是倒序）

3. **批量操作**:
   - 支持批量归档/删除
   - 支持导出选中会话

4. **缓存优化**:
   - 客户端缓存线程列表
   - 增量更新机制

5. **Schema 优化**:
   - 考虑添加 `include_turns` 选项（当前总是不包含）
   - 支持返回线程计数（不分页）
