# 研究文档：codex-rs/core/src/rollout/tests.rs

## 场景与职责

`tests.rs` 是 `codex-rs/core/src/rollout` 模块的集成测试文件，负责验证 rollout 系统的核心功能，包括：

1. **会话文件列表管理** - 测试 `get_threads` 函数，验证会话列表的获取、排序、分页和过滤功能
2. **线程路径查找** - 测试 `find_thread_path_by_id_str` 函数，验证通过线程 ID 查找 rollout 文件路径的能力
3. **状态数据库集成** - 测试与 SQLite 状态数据库的集成，包括路径修复和回退机制
4. **会话元数据解析** - 验证会话文件头信息的正确解析，包括 `base_instructions` 等字段

该测试文件在 Codex 的会话持久化和恢复机制中扮演关键角色，确保用户历史会话能够被正确记录、检索和恢复。

## 功能点目的

### 1. 会话列表测试 (`test_list_conversations_latest_first`)
验证会话按创建时间排序（最新优先），确保用户能看到按时间倒序排列的历史会话。

### 2. 分页游标测试 (`test_pagination_cursor`)
验证基于游标的分页机制，确保：
- 游标格式为 `"timestamp|uuid"`
- 分页边界正确处理
- 扫描文件计数准确

### 3. 文件扫描深度测试 (`test_list_threads_scans_past_head_for_user_event`)
验证当用户消息事件不在文件头部时，系统能够扫描更多行（最多 `HEAD_RECORD_LIMIT + USER_EVENT_SCAN_LIMIT`）来找到用户事件。

### 4. 状态数据库回退测试 (`find_thread_path_falls_back_when_db_path_is_stale`)
验证当 SQLite 中存储的路径过时（文件已被移动）时，系统能够：
- 检测到路径失效
- 回退到文件系统搜索
- 修复数据库中的路径记录

### 5. 源过滤测试 (`test_source_filter_excludes_non_matching_sessions`)
验证按会话源（`SessionSource::Cli` vs `SessionSource::Exec`）过滤功能，确保交互式会话与非交互式会话能被正确区分。

### 6. 模型提供商过滤测试 (`test_model_provider_filter_selects_only_matching_sessions`)
验证按模型提供商过滤功能，处理以下边界情况：
- 匹配指定提供商的会话
- 无提供商信息的会话（使用默认提供商匹配）
- 不匹配的会话被排除

### 7. 时间戳测试
- `test_created_at_sort_uses_file_mtime_for_updated_at` - 验证 `updated_at` 从文件 mtime 获取
- `test_updated_at_uses_file_mtime` - 验证按更新时间排序功能
- `test_stable_ordering_same_second_pagination` - 验证同一秒内多个文件的稳定排序（按 UUID 降序）

### 8. 元数据字段测试
- `test_base_instructions_missing_in_meta_defaults_to_null` - 验证缺失 `base_instructions` 时默认为 null
- `test_base_instructions_present_in_meta_is_preserved` - 验证 `base_instructions` 正确保存和读取

## 具体技术实现

### 关键数据结构

```rust
// 测试使用的辅助结构
struct HeadTailSummary {
    saw_session_meta: bool,
    saw_user_event: bool,
    thread_id: Option<ThreadId>,
    first_user_message: Option<String>,
    cwd: Option<PathBuf>,
    git_branch: Option<String>,
    git_sha: Option<String>,
    git_origin_url: Option<String>,
    source: Option<SessionSource>,
    agent_nickname: Option<String>,
    agent_role: Option<String>,
    model_provider: Option<String>,
    cli_version: Option<String>,
    created_at: Option<String>,
    updated_at: Option<String>,
}

// 分页结果
pub struct ThreadsPage {
    pub items: Vec<ThreadItem>,
    pub next_cursor: Option<Cursor>,
    pub num_scanned_files: usize,
    pub reached_scan_cap: bool,
}

// 游标结构
pub struct Cursor {
    ts: OffsetDateTime,
    id: Uuid,
}
```

### 测试辅助函数

#### `write_session_file` - 创建测试会话文件
```rust
fn write_session_file(
    root: &Path,
    ts_str: &str,           // 时间戳字符串，如 "2025-01-03T13-00-00"
    uuid: Uuid,
    num_records: usize,     // 响应记录数量
    source: Option<SessionSource>,
) -> std::io::Result<(OffsetDateTime, Uuid)>
```

生成目录结构：`sessions/YYYY/MM/DD/rollout-YYYY-MM-DDThh-mm-ss-<uuid>.jsonl`

文件内容格式（JSON Lines）：
```jsonl
{"timestamp": "2025-01-03T13-00-00", "type": "session_meta", "payload": {...}}
{"timestamp": "2025-01-03T13-00-00", "type": "event_msg", "payload": {"type": "user_message", ...}}
{"record_type": "response", "index": 0}
...
```

#### `insert_state_db_thread` - 向状态数据库插入测试数据
```rust
async fn insert_state_db_thread(
    home: &Path,
    thread_id: ThreadId,
    rollout_path: &Path,
    archived: bool,
)
```

使用 `codex_state::StateRuntime` 初始化数据库并插入线程元数据。

### 关键流程

#### 1. 会话列表获取流程
```
get_threads(home, page_size, cursor, sort_key, allowed_sources, model_providers, default_provider)
  └─> get_threads_in_root(root, ...)
       ├─> ThreadSortKey::CreatedAt: traverse_directories_for_paths_created()
       │    └─> walk_rollout_files()  // 遍历 YYYY/MM/DD 目录结构
       │         └─> FilesByCreatedAtVisitor::visit()
       │              └─> build_thread_item()  // 解析文件头
       └─> ThreadSortKey::UpdatedAt: traverse_directories_for_paths_updated()
            └─> collect_files_by_updated_at()  // 收集所有文件后排序
```

#### 2. 文件头解析流程
```
read_head_summary(path, HEAD_RECORD_LIMIT)
  └─> 逐行读取 JSONL
       ├─> RolloutItem::SessionMeta: 提取会话元数据
       ├─> RolloutItem::EventMsg::UserMessage: 提取首条用户消息
       └─> RolloutItem::ResponseItem: 更新 created_at
```

#### 3. 路径查找流程（含回退）
```
find_thread_path_by_id_str(home, id_str)
  ├─> 尝试从 SQLite 获取路径
  │    └─> 路径存在且有效？返回路径
  │    └─> 路径过时？记录错误，继续回退
  └─> 回退到文件系统搜索（file_search::run）
       └─> 找到文件？调用 read_repair_rollout_path() 修复数据库
```

## 关键代码路径与文件引用

### 被测试的主要函数

| 函数 | 定义位置 | 用途 |
|------|----------|------|
| `get_threads` | `list.rs:303` | 获取会话列表（主入口） |
| `find_thread_path_by_id_str` | `list.rs:1250` | 通过 ID 查找 rollout 文件路径 |
| `read_head_for_summary` | `list.rs:1087` | 读取文件头用于摘要 |
| `rollout_date_parts` | `list.rs:1266` | 从文件名提取日期组件 |
| `parse_cursor` | `list.rs:659` | 解析分页游标 |

### 测试辅助函数

| 函数 | 行号 | 用途 |
|------|------|------|
| `write_session_file` | 290 | 创建标准测试会话文件 |
| `write_session_file_with_provider` | 307 | 创建带提供商信息的测试文件 |
| `write_session_file_with_delayed_user_event` | 378 | 创建用户事件延迟出现的测试文件 |
| `write_session_file_with_meta_payload` | 435 | 创建自定义元数据 payload 的测试文件 |
| `insert_state_db_thread` | 54 | 向状态数据库插入测试线程 |
| `assert_state_db_rollout_path` | 275 | 验证数据库中的 rollout 路径 |

### 常量定义

| 常量 | 值 | 定义位置 | 用途 |
|------|-----|----------|------|
| `MAX_SCAN_FILES` | 10000 | `list.rs:103` | 单次请求扫描文件上限 |
| `HEAD_RECORD_LIMIT` | 10 | `list.rs:104` | 文件头读取行数限制 |
| `USER_EVENT_SCAN_LIMIT` | 200 | `list.rs:105` | 用户事件额外扫描行数 |
| `INTERACTIVE_SESSION_SOURCES` | `[Cli, VSCode]` | `mod.rs:7` | 交互式会话源列表 |

## 依赖与外部交互

### 外部 Crate 依赖

```rust
use chrono::TimeZone;
use pretty_assertions::assert_eq;
use tempfile::TempDir;
use time::{Duration, OffsetDateTime, PrimitiveDateTime};
use uuid::Uuid;
use anyhow::Result;
```

### 内部模块依赖

```rust
use crate::rollout::INTERACTIVE_SESSION_SOURCES;
use crate::rollout::list::{Cursor, ThreadItem, ThreadSortKey, ThreadsPage, get_threads, read_head_for_summary};
use crate::rollout::rollout_date_parts;
use crate::rollout::find_thread_path_by_id_str;
```

### 协议类型依赖

```rust
use codex_protocol::ThreadId;
use codex_protocol::models::{ContentItem, ResponseItem};
use codex_protocol::protocol::{EventMsg, RolloutItem, RolloutLine, SessionMeta, SessionMetaLine, SessionSource, UserMessageEvent};
```

### 状态数据库依赖

```rust
use codex_state::StateRuntime;
use codex_state::ThreadMetadataBuilder;
```

### 文件系统布局

测试使用的目录结构：
```
<temp_dir>/
└── sessions/
    └── YYYY/
        └── MM/
            └── DD/
                └── rollout-YYYY-MM-DDThh-mm-ss-<uuid>.jsonl
```

## 风险、边界与改进建议

### 已知风险

1. **被注释掉的测试**（行 91-215）：
   - `list_threads_prefers_state_db_when_available`
   - `list_threads_db_excludes_archived_entries`
   - `list_threads_falls_back_to_files_when_state_db_is_unavailable`
   
   这些测试被注释掉，标记为 `TODO(jif) fix`，表明状态数据库优先功能存在问题或未完全实现。

2. **硬编码的测试提供商**：`TEST_PROVIDER = "test-provider"` 可能在测试外环境中失效。

3. **时间精度问题**：测试中使用 `OffsetDateTime` 和 `chrono` 混用，可能存在时区处理边界。

### 边界情况

1. **空会话目录**：`get_threads` 正确处理空目录（返回空列表）。
2. **无效游标格式**：`parse_cursor` 返回 `None`，调用方需处理。
3. **文件系统与数据库不一致**：测试验证了回退机制，但并发修改场景未完全覆盖。
4. **同一秒内多文件**：通过 UUID 降序确保稳定排序。

### 改进建议

1. **恢复被注释的测试**：修复状态数据库优先功能，恢复相关测试覆盖。

2. **增加并发测试**：添加多线程/多进程并发访问会话文件的测试。

3. **增加损坏文件处理测试**：测试 rollout 文件部分损坏时的优雅降级。

4. **提取测试辅助函数**：`write_session_file` 系列函数较长，可考虑提取到独立测试工具模块。

5. **使用参数化测试**：多个测试使用相似的文件创建逻辑，可使用 `rstest` 等参数化测试框架简化。

6. **增加大文件性能测试**：验证 `MAX_SCAN_FILES` 和扫描限制在大规模会话目录下的性能表现。

7. **统一时间处理**：考虑统一使用 `time` crate 或 `chrono`，避免混用带来的潜在问题。
