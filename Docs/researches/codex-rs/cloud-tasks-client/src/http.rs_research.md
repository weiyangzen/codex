# http.rs 研究文档

## 场景与职责

`http.rs` 是 `codex-cloud-tasks-client` crate 的 HTTP 实现模块，提供了 `CloudBackend` trait 的具体实现 `HttpClient`。它负责与 Codex Cloud 后端服务进行真实的 HTTP 通信，处理任务列表查询、详情获取、补丁应用和任务创建等操作。

主要使用场景：
- TUI 应用（`codex cloud` 命令）与后端的真实交互
- CLI 命令（`codex cloud exec/status/list/apply/diff`）的数据获取
- 支持两种后端 API 风格：Codex API (`/api/codex`) 和 ChatGPT API (`/backend-api/wham`)

## 功能点目的

### 1. HttpClient 结构体

```rust
pub struct HttpClient {
    pub base_url: String,
    backend: backend::Client,  // codex_backend_client::Client
}
```

提供 builder 风格的配置方法：
- `new()`: 创建客户端
- `with_bearer_token()`: 设置认证令牌
- `with_user_agent()`: 设置 User-Agent
- `with_chatgpt_account_id()`: 设置 ChatGPT 账户 ID

### 2. CloudBackend Trait 实现

为 `HttpClient` 实现 `CloudBackend`，将 trait 方法委托给内部 API 模块：

| 方法 | 委托 API |
|------|----------|
| `list_tasks` | `tasks_api().list()` |
| `get_task_summary` | `tasks_api().summary()` |
| `get_task_diff` | `tasks_api().diff()` |
| `get_task_messages` | `tasks_api().messages()` |
| `get_task_text` | `tasks_api().task_text()` |
| `list_sibling_attempts` | `attempts_api().list()` |
| `apply_task/apply_task_preflight` | `apply_api().run()` |
| `create_task` | `tasks_api().create()` |

### 3. 内部 API 模块

#### `api::Tasks` - 任务相关 API

- `list()`: 获取任务列表，支持分页（limit/cursor）和环境过滤（env）
- `summary()`: 获取任务摘要，解析复杂的嵌套 JSON 响应
- `diff()`: 获取任务 diff
- `messages()`: 获取助手消息
- `task_text()`: 获取任务完整文本（prompt + messages）
- `create()`: 创建新任务，支持 `CODEX_STARTING_DIFF` 环境变量注入初始补丁

#### `api::Attempts` - Best-of-N 尝试管理

- `list()`: 获取指定 turn 的兄弟尝试列表，支持排序

#### `api::Apply` - 补丁应用

- `run()`: 执行补丁应用或预检，使用 `codex_git::apply_git_patch`

## 具体技术实现

### 后端响应解析

#### 任务摘要解析 (`summary` 方法)

复杂的 JSON 解析逻辑（lines 180-247）：

```rust
// 1. 获取原始响应
let (details, body, ct) = self.details_with_body(&id.0).await?;

// 2. 解析 JSON
let parsed: Value = serde_json::from_str(&body)?;

// 3. 提取 task 对象
let task_obj = parsed.get("task").and_then(Value::as_object);

// 4. 提取 task_status_display（嵌套状态显示）
let status_display = parsed.get("task_status_display").or_else(...);

// 5. 状态映射
let status = map_status(status_display.as_ref());

// 6. diff 统计（优先从 status_display，否则从 diff 内容计算）
let mut summary = diff_summary_from_status_display(status_display.as_ref());
if summary.is_empty() && let Some(diff) = details.unified_diff() {
    summary = diff_summary_from_diff(&diff);
}
```

#### 消息提取双路径 (`messages` 方法)

1. 优先从 `details.assistant_text_messages()`（结构化解析）
2. 回退到 `extract_assistant_messages_from_body()`（原始 JSON 解析）

### Best-of-N 尝试排序

```rust
fn compare_attempts(a: &TurnAttempt, b: &TurnAttempt) -> Ordering {
    match (a.attempt_placement, b.attempt_placement) {
        (Some(lhs), Some(rhs)) => lhs.cmp(&rhs),  // 按 placement 排序
        (Some(_), None) => Ordering::Less,        // 有 placement 的在前
        (None, Some(_)) => Ordering::Greater,
        (None, None) => match (a.created_at, b.created_at) {
            (Some(lhs), Some(rhs)) => lhs.cmp(&rhs),  // 回退到时间
            // ...
        },
    }
}
```

### 补丁应用流程 (`Apply::run`)

```rust
pub(crate) async fn run(
    &self,
    task_id: TaskId,
    diff_override: Option<String>,  // 可覆盖的 diff
    preflight: bool,                // 是否仅预检
) -> Result<ApplyOutcome> {
    // 1. 获取 diff（优先使用 override，否则从后端获取）
    let diff = match diff_override {
        Some(diff) => diff,
        None => self.backend.get_task_details(&id).await?.unified_diff()
            .ok_or(...)?,
    };
    
    // 2. 验证 unified diff 格式
    if !is_unified_diff(&diff) { ... }
    
    // 3. 调用 codex_git 应用补丁
    let req = codex_git::ApplyGitRequest {
        cwd: std::env::current_dir().unwrap_or_else(|_| std::env::temp_dir()),
        diff: diff.clone(),
        revert: false,
        preflight,
    };
    let r = codex_git::apply_git_patch(&req)?;
    
    // 4. 解析结果状态
    let status = if r.exit_code == 0 { ApplyStatus::Success }
                 else if !r.applied_paths.is_empty() { ApplyStatus::Partial }
                 else { ApplyStatus::Error };
    
    // 5. 错误日志记录（失败时）
    if matches!(status, ApplyStatus::Partial | ApplyStatus::Error) {
        append_error_log(&format!(...));
    }
    
    Ok(ApplyOutcome { ... })
}
```

### 任务创建支持初始补丁

通过 `CODEX_STARTING_DIFF` 环境变量支持注入初始补丁（lines 331-338）：

```rust
if let Ok(diff) = std::env::var("CODEX_STARTING_DIFF") && !diff.is_empty() {
    input_items.push(serde_json::json!({
        "type": "pre_apply_patch",
        "output_diff": { "diff": diff }
    }));
}
```

### diff 格式检测

```rust
fn is_unified_diff(diff: &str) -> bool {
    let t = diff.trim_start();
    if t.starts_with("diff --git ") { return true; }
    let has_dash_headers = diff.contains("\n--- ") && diff.contains("\n+++ ");
    let has_hunk = diff.contains("\n@@ ") || diff.starts_with("@@ ");
    has_dash_headers && has_hunk
}
```

## 关键代码路径与文件引用

```
codex-rs/cloud-tasks-client/src/http.rs
├── HttpClient 结构体 (lines 20-59)
│   ├── new()
│   ├── with_bearer_token()
│   ├── with_user_agent()
│   └── with_chatgpt_account_id()
├── CloudBackend 实现 (lines 61-124)
│   └── 方法委托给内部 API
├── api::Tasks (lines 126-386)
│   ├── list() - 任务列表 (lines 145-178)
│   ├── summary() - 任务摘要 (lines 180-247)
│   ├── diff() - 获取 diff (lines 249-259)
│   ├── messages() - 获取消息 (lines 261-285)
│   ├── task_text() - 获取文本 (lines 287-314)
│   ├── create() - 创建任务 (lines 316-377)
│   └── details_with_body() - 辅助方法 (lines 379-385)
├── api::Attempts (lines 388-414)
│   └── list() - 兄弟尝试 (lines 399-413)
├── api::Apply (lines 416-559)
│   └── run() - 应用补丁 (lines 427-558)
├── 工具函数 (lines 561-893)
│   ├── details_path() - URL 构建 (lines 561-569)
│   ├── extract_assistant_messages_from_body() (lines 571-612)
│   ├── turn_attempt_from_map() (lines 614-629)
│   ├── compare_attempts() (lines 631-643)
│   ├── extract_diff_from_turn() (lines 645-671)
│   ├── extract_assistant_messages_from_turn() (lines 673-693)
│   ├── attempt_status_from_str() (lines 695-703)
│   ├── parse_timestamp_value() (lines 705-712)
│   ├── map_task_list_item_to_summary() (lines 714-730)
│   ├── map_status() (lines 732-759)
│   ├── parse_updated_at() (lines 761-770)
│   ├── env_label_from_status_display() (lines 772-777)
│   ├── diff_summary_from_diff() (lines 779-805)
│   ├── diff_summary_from_status_display() (lines 807-826)
│   ├── latest_turn_timestamp() (lines 828-837)
│   ├── attempt_total_from_status_display() (lines 839-846)
│   ├── is_unified_diff() (lines 848-856)
│   ├── tail() (lines 858-864)
│   └── summarize_patch_for_logging() (lines 866-892)
└── append_error_log() - 错误日志 (lines 895-905)
```

### 依赖文件

- `codex-rs/backend-client/src/client.rs`: `backend::Client` 定义
- `codex-rs/backend-client/src/types.rs`: `CodeTaskDetailsResponse` 等类型
- `codex-rs/utils/git/src/apply.rs`: `codex_git::apply_git_patch`

### 调用方

- `codex-rs/cloud-tasks/src/app.rs`: TUI 应用
- `codex-rs/cloud-tasks/src/main.rs`: CLI 入口

## 依赖与外部交互

### 外部依赖

| crate | 用途 |
|-------|------|
| `chrono` | 时间戳处理 |
| `serde_json` | JSON 解析 |
| `async-trait` | 异步 trait |
| `codex-backend-client` | 底层 HTTP 客户端 |
| `codex-git` | Git 补丁应用 |

### 内部依赖

| 模块 | 用途 |
|------|------|
| `api.rs` | 类型定义和 trait |

## 风险、边界与改进建议

### 当前风险

1. **硬编码超时**: `load_tasks` 在调用方（app.rs）使用 5 秒超时，但 http.rs 内部无超时控制
2. **错误日志文件**: `append_error_log` 直接写入 `error.log`，无日志轮转或大小限制
3. **Git 工作目录假设**: `apply_git_patch` 使用 `std::env::current_dir()`，可能在某些环境下不准确
4. **JSON 解析脆弱性**: `summary()` 方法手动解析嵌套 JSON，容易因后端格式变化而失败

### 边界情况

1. **空 diff**: `diff()` 方法可能返回 `Ok(None)`，调用方需处理
2. **非 unified diff 格式**: `is_unified_diff` 会拒绝 codex-patch 格式
3. **时间戳解析失败**: `parse_updated_at` 回退到 `Utc::now()`
4. **分页游标**: 任务列表分页使用字符串游标，可能包含特殊字符

### 改进建议

1. **结构化日志**: 使用 `tracing` 替代手动文件写入
   ```rust
   // 替代 append_error_log
   tracing::error!(target: "cloud_tasks", "{message}");
   ```

2. **配置化超时**: 将超时参数暴露给调用方
   ```rust
   pub async fn list_tasks_with_timeout(
       &self,
       timeout: Duration,
       ...
   ) -> Result<TaskListPage>;
   ```

3. **JSON Schema 验证**: 使用强类型替代手动 Value 解析
   ```rust
   #[derive(Deserialize)]
   struct TaskDetailsResponse {
       task: TaskMetadata,
       task_status_display: Option<TaskStatusDisplay>,
   }
   ```

4. **diff 格式支持**: 扩展 `is_unified_diff` 支持更多格式，或添加自动转换

5. **缓存机制**: 为 `get_task_summary` 等高频调用添加内存缓存

6. **重试逻辑**: 为网络请求添加指数退避重试

7. **更好的错误上下文**: 使用 `anyhow::Context` 增强错误信息
   ```rust
   .with_context(|| format!("failed to parse task details for {id}"))?
   ```
