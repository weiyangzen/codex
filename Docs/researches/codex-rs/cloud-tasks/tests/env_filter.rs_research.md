# 研究文档: `codex-rs/cloud-tasks/tests/env_filter.rs`

## 1. 场景与职责

### 1.1 文件定位

`env_filter.rs` 是 `codex-cloud-tasks` crate 的集成测试文件，位于 `codex-rs/cloud-tasks/tests/` 目录下。该测试文件专门验证 **Cloud Tasks TUI 应用的环境过滤功能** 在 Mock 后端下的正确行为。

### 1.2 所属模块上下文

```
codex-rs/
├── cloud-tasks/              # Cloud Tasks TUI 应用主 crate
│   ├── src/
│   │   ├── lib.rs           # 主入口，包含后端初始化、命令处理、事件循环
│   │   ├── app.rs           # TUI 应用状态管理 (App, DiffOverlay, AppEvent)
│   │   ├── cli.rs           # 命令行参数定义
│   │   ├── env_detect.rs    # 环境自动检测与列表获取
│   │   ├── ui.rs            # 界面渲染
│   │   └── util.rs          # 工具函数
│   └── tests/
│       └── env_filter.rs    # <-- 本研究目标
├── cloud-tasks-client/       # Cloud Tasks 客户端 crate
│   ├── src/
│   │   ├── lib.rs           # 模块导出
│   │   ├── api.rs           # CloudBackend trait 与数据类型定义
│   │   ├── mock.rs          # MockClient 实现
│   │   └── http.rs          # HttpClient 实现 (online feature)
```

### 1.3 职责概述

该测试文件的核心职责是：

1. **验证环境过滤参数传递**: 确保 `CloudBackend::list_tasks()` 方法的 `env` 参数能够正确传递给后端
2. **验证 Mock 后端的环境感知能力**: 确认 `MockClient` 能根据传入的 `env` 参数返回不同的任务列表
3. **作为集成测试示例**: 展示如何使用 `MockClient` 进行 Cloud Tasks 功能的测试

### 1.4 业务场景

在 Cloud Tasks TUI 应用中，用户可以通过以下方式过滤任务：

- **TUI 界面**: 按 `o` 键打开环境选择模态框，选择特定环境
- **CLI 命令**: `codex cloud list --env=<ENV_ID>` 指定环境
- **自动检测**: 启动时自动检测当前 Git 仓库关联的环境

本测试确保这些过滤机制在后端 API 调用层面正确工作。

---

## 2. 功能点目的

### 2.1 测试目标

测试函数 `mock_backend_varies_by_env` 验证以下功能点：

| 功能点 | 描述 |
|--------|------|
| **无环境过滤** | 当 `env=None` 时，返回所有任务（跨环境） |
| **环境 A 过滤** | 当 `env=Some("env-A")` 时，仅返回环境 A 的任务 |
| **环境 B 过滤** | 当 `env=Some("env-B")` 时，仅返回环境 B 的任务 |
| **数据隔离性** | 不同环境返回的任务集合互不相交 |

### 2.2 测试覆盖的断言

```rust
// 1. 无环境过滤时返回默认任务列表（包含 "Update README"）
assert!(root.iter().any(|t| t.title.contains("Update README")));

// 2. env-A 只返回 1 个任务，标题为 "A: First"
assert_eq!(a.len(), 1);
assert_eq!(a[0].title, "A: First");

// 3. env-B 返回 2 个任务，第一个标题以 "B: " 开头
assert_eq!(b.len(), 2);
assert!(b[0].title.starts_with("B: "));
```

### 2.3 与生产代码的关联

该测试直接验证 `codex-rs/cloud-tasks/src/lib.rs` 中的 `run_list_command` 函数的核心逻辑：

```rust
// lib.rs:510-523
async fn run_list_command(args: crate::cli::ListCommand) -> anyhow::Result<()> {
    let ctx = init_backend("codex_cloud_tasks_list").await?;
    let env_filter = if let Some(env) = args.environment {
        Some(resolve_environment_id(&ctx, &env).await?)
    } else {
        None
    };
    let page = codex_cloud_tasks_client::CloudBackend::list_tasks(
        &*ctx.backend,
        env_filter.as_deref(),  // <-- 本测试验证的参数
        Some(args.limit),
        args.cursor.as_deref(),
    )
    .await?;
    // ...
}
```

---

## 3. 具体技术实现

### 3.1 测试架构

```
┌─────────────────────────────────────────────────────────────┐
│                    env_filter.rs (测试)                      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  #[tokio::test]                                       │  │
│  │  async fn mock_backend_varies_by_env()                │  │
│  │    ├─ 创建 MockClient                                 │  │
│  │    ├─ 调用 CloudBackend::list_tasks(&client, env)    │  │
│  │    └─ 断言返回结果                                    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              codex-cloud-tasks-client crate                 │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  MockClient (mock.rs)                                 │  │
│  │    ├─ 实现 CloudBackend trait                         │  │
│  │    └─ list_tasks() 根据 env 参数返回不同数据          │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 MockClient 的环境感知实现

`codex-rs/cloud-tasks-client/src/mock.rs` 中的 `list_tasks` 方法实现了环境感知逻辑：

```rust
#[async_trait::async_trait]
impl CloudBackend for MockClient {
    async fn list_tasks(
        &self,
        _env: Option<&str>,
        _limit: Option<i64>,
        _cursor: Option<&str>,
    ) -> Result<crate::TaskListPage> {
        // 根据 env 参数返回不同的模拟数据
        let rows = match _env {
            Some("env-A") => vec![("T-2000", "A: First", TaskStatus::Ready)],
            Some("env-B") => vec![
                ("T-3000", "B: One", TaskStatus::Ready),
                ("T-3001", "B: Two", TaskStatus::Pending),
            ],
            _ => vec![
                ("T-1000", "Update README formatting", TaskStatus::Ready),
                ("T-1001", "Fix clippy warnings in core", TaskStatus::Pending),
                ("T-1002", "Add contributing guide", TaskStatus::Ready),
            ],
        };
        // ... 构建 TaskSummary 列表
    }
}
```

### 3.3 CloudBackend Trait 定义

`codex-rs/cloud-tasks-client/src/api.rs` 定义了核心 trait：

```rust
#[async_trait::async_trait]
pub trait CloudBackend: Send + Sync {
    async fn list_tasks(
        &self,
        env: Option<&str>,      // 环境过滤参数
        limit: Option<i64>,     // 分页限制
        cursor: Option<&str>,   // 分页游标
    ) -> Result<TaskListPage>;
    
    // 其他方法: get_task_summary, get_task_diff, apply_task, etc.
}
```

### 3.4 关键数据结构

#### TaskListPage
```rust
pub struct TaskListPage {
    pub tasks: Vec<TaskSummary>,
    pub cursor: Option<String>,  // 分页游标
}
```

#### TaskSummary
```rust
pub struct TaskSummary {
    pub id: TaskId,
    pub title: String,
    pub status: TaskStatus,          // Pending | Ready | Applied | Error
    pub updated_at: DateTime<Utc>,
    pub environment_id: Option<String>,
    pub environment_label: Option<String>,
    pub summary: DiffSummary,
    pub is_review: bool,
    pub attempt_total: Option<usize>,
}
```

### 3.5 测试执行流程

```rust
#[tokio::test]
async fn mock_backend_varies_by_env() {
    // 1. 创建 MockClient（空结构体，无状态）
    let client = MockClient;

    // 2. 测试无环境过滤（全局任务列表）
    let root = CloudBackend::list_tasks(&client, None, None, None)
        .await
        .unwrap()
        .tasks;
    // 验证: 包含 "Update README" 的任务

    // 3. 测试 env-A 过滤
    let a = CloudBackend::list_tasks(&client, Some("env-A"), None, None)
        .await
        .unwrap()
        .tasks;
    // 验证: 仅 1 个任务，标题为 "A: First"

    // 4. 测试 env-B 过滤
    let b = CloudBackend::list_tasks(&client, Some("env-B"), None, None)
        .await
        .unwrap()
        .tasks;
    // 验证: 2 个任务，标题以 "B: " 开头
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试文件

| 路径 | 行数 | 说明 |
|------|------|------|
| `codex-rs/cloud-tasks/tests/env_filter.rs` | 27 | 本研究目标文件 |

### 4.2 被测试代码

| 路径 | 关键内容 |
|------|----------|
| `codex-rs/cloud-tasks-client/src/mock.rs` | `MockClient::list_tasks()` 环境感知实现 (行 19-70) |
| `codex-rs/cloud-tasks-client/src/api.rs` | `CloudBackend` trait 定义 (行 133-170) |
| `codex-rs/cloud-tasks-client/src/lib.rs` | 模块导出与 feature gate (行 18-28) |

### 4.3 调用方代码

| 路径 | 关键内容 |
|------|----------|
| `codex-rs/cloud-tasks/src/lib.rs` | `run_list_command()` (行 510-575), `load_tasks()` 调用 (行 830) |
| `codex-rs/cloud-tasks/src/app.rs` | `load_tasks()` 函数定义 (行 121-134) |
| `codex-rs/cloud-tasks/src/cli.rs` | `ListCommand` 结构体定义 (行 82-98) |

### 4.4 代码依赖图

```
env_filter.rs (测试)
    │
    ├──► CloudBackend::list_tasks() ───────┐
    │                                       │
    │   ┌───────────────────────────────────┘
    │   │
    │   ├──► MockClient::list_tasks() [mock.rs:19]
    │   │       └── 根据 env 参数匹配返回不同数据
    │   │
    │   └──► HttpClient::list_tasks() [http.rs] (online feature)
    │           └── 实际 HTTP API 调用
    │
    └──► TaskListPage, TaskSummary [api.rs:98-50]

Production Call Path:
    cli.rs:ListCommand
        └──► lib.rs:run_list_command()
                └──► CloudBackend::list_tasks(env_filter.as_deref(), ...)
                        └──► app.rs:load_tasks() (TUI 模式)
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖

```toml
# codex-rs/cloud-tasks/Cargo.toml [dependencies]
codex-cloud-tasks-client = { path = "../cloud-tasks-client", features = ["mock", "online"] }
```

### 5.2 依赖链

```
env_filter.rs
    ├──► codex-cloud-tasks-client (本地 path 依赖)
    │       ├──► api.rs (数据类型与 trait)
    │       ├──► mock.rs (MockClient 实现, feature = "mock")
    │       └──► http.rs (HttpClient 实现, feature = "online")
    │
    ├──► tokio (异步运行时, #[tokio::test])
    │
    └──► 标准库 (assert!, assert_eq!)
```

### 5.3 Feature Flags

| Feature | 说明 | 测试中使用 |
|---------|------|-----------|
| `mock` | 启用 `MockClient` | ✅ 是 |
| `online` | 启用 `HttpClient` | ❌ 否（测试使用 Mock） |

### 5.4 无外部网络交互

本测试为纯本地 Mock 测试，不涉及：
- 网络 HTTP 请求
- 文件系统 I/O
- 环境变量读取
- 数据库访问

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 风险 1: Mock 数据与真实 API 不同步
- **描述**: `MockClient` 返回的模拟数据可能与真实后端 API 响应格式不一致
- **影响**: 测试通过但生产环境可能失败
- **缓解**: 定期对比 `mock.rs` 和 `http.rs` 的数据解析逻辑

#### 风险 2: 测试覆盖不完整
- **描述**: 仅测试了 `list_tasks` 的环境过滤，未测试其他方法
- **影响**: 其他 `CloudBackend` 方法的环境处理可能存在 bug
- **当前状态**: `app.rs` 中的单元测试补充了部分覆盖（`load_tasks_uses_env_parameter`）

#### 风险 3: 硬编码环境名称
- **描述**: 测试使用硬编码的 `"env-A"` 和 `"env-B"`
- **影响**: 如果 `MockClient` 修改了环境名称匹配逻辑，测试可能失效

### 6.2 边界情况

| 边界情况 | 当前处理 | 说明 |
|----------|----------|------|
| `env = Some("")` | 未测试 | 空字符串环境 ID 行为未定义 |
| `env = Some("nonexistent")` | 返回默认列表 | Mock 回退到 `_` 分支 |
| 特殊字符环境名 | 未测试 | 如 `"env/A"`, `"env A"` 等 |
| 大小写敏感 | 精确匹配 | `"env-a"` 不会匹配 `"env-A"` |

### 6.3 改进建议

#### 建议 1: 增加边界测试
```rust
// 建议添加的测试用例
#[tokio::test]
async fn mock_backend_empty_env_returns_all() {
    let client = MockClient;
    let empty = CloudBackend::list_tasks(&client, Some(""), None, None)
        .await
        .unwrap()
        .tasks;
    // 验证空字符串是否被视为无过滤
}

#[tokio::test]
async fn mock_backend_unknown_env_returns_default() {
    let client = MockClient;
    let unknown = CloudBackend::list_tasks(&client, Some("unknown-env"), None, None)
        .await
        .unwrap()
        .tasks;
    // 验证未知环境的行为
}
```

#### 建议 2: 文档化 Mock 数据约定
在 `mock.rs` 中添加文档注释，说明：
- 支持的环境名称列表
- 每个环境返回的任务数据
- 默认（无环境）返回的数据

#### 建议 3: 考虑参数化测试
使用 `rstest` 或类似的参数化测试框架：
```rust
#[rstest]
#[case(None, 3, "Update README")]
#[case(Some("env-A"), 1, "A: First")]
#[case(Some("env-B"), 2, "B: ")]
#[tokio::test]
async fn mock_backend_varies_by_env_parametrized(
    #[case] env: Option<&str>,
    #[case] expected_count: usize,
    #[case] expected_contains: &str,
) { ... }
```

#### 建议 4: 与 HTTP 客户端的契约测试
考虑添加契约测试，确保 `MockClient` 和 `HttpClient` 对相同输入产生语义等价的输出。

#### 建议 5: 环境 ID 验证测试
测试 `resolve_environment_id` 函数（`lib.rs:183-226`）与 `MockClient` 的集成：
- 验证环境 ID 解析逻辑
- 验证环境标签匹配逻辑

### 6.4 相关测试补充

`app.rs` 中已存在类似的单元测试（行 490-511）：

```rust
#[tokio::test]
async fn load_tasks_uses_env_parameter() {
    // 使用 FakeBackend 测试 load_tasks 函数
    let mut by_env = std::collections::HashMap::new();
    by_env.insert(None, vec!["root-1", "root-2"]);
    by_env.insert(Some("env-A".to_string()), vec!["A-1"]);
    // ...
}
```

这表明测试策略是分层进行的：
- `env_filter.rs`: 集成测试，验证 `MockClient` 行为
- `app.rs` 单元测试: 验证 `load_tasks` 函数逻辑

---

## 7. 总结

`env_filter.rs` 是一个简洁但重要的集成测试，它验证了 Cloud Tasks 客户端 Mock 实现的环境过滤功能。该测试：

1. **职责明确**: 专注于 `CloudBackend::list_tasks` 的环境参数处理
2. **架构清晰**: 利用 `MockClient` 实现无外部依赖的测试
3. **覆盖关键路径**: 验证了 TUI 和 CLI 共用的核心过滤逻辑

改进空间主要在于增加边界测试和文档化 Mock 数据约定，以提高测试的健壮性和可维护性。
