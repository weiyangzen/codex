# mock.rs 研究文档

## 场景与职责

`mock.rs` 是 `codex-cloud-tasks-client` crate 的 Mock 实现模块，提供了 `CloudBackend` trait 的内存实现 `MockClient`。它主要用于：

- **单元测试**: 为依赖 `CloudBackend` 的代码提供可预测的测试替身
- **离线开发**: 允许开发者在无网络环境下进行 UI/逻辑开发
- **快速原型**: 无需真实后端即可验证客户端集成逻辑

主要使用场景：
- `codex-cloud-tasks` crate 的单元测试
- TUI 组件的独立开发和测试
- CI 环境中避免真实网络调用

## 功能点目的

### 1. MockClient 结构体

```rust
#[derive(Clone, Default)]
pub struct MockClient;
```

零成本、无状态的 Mock 实现，所有数据都在方法中硬编码或动态生成。

### 2. CloudBackend Trait 实现

为 `MockClient` 实现完整的 `CloudBackend` trait，提供以下方法的 Mock 行为：

| 方法 | Mock 行为 |
|------|-----------|
| `list_tasks` | 根据 env 参数返回不同的硬编码任务列表 |
| `get_task_summary` | 从 `list_tasks` 结果中查找匹配的任务 |
| `get_task_diff` | 返回硬编码的 unified diff 字符串 |
| `get_task_messages` | 返回固定的 Mock 消息 |
| `get_task_text` | 返回固定的 Mock 文本数据 |
| `apply_task` | 返回成功结果（模拟应用成功） |
| `apply_task_preflight` | 返回预检通过结果 |
| `list_sibling_attempts` | 为特定任务 ID (T-1000) 返回 Mock 尝试数据 |
| `create_task` | 生成基于时间戳的任务 ID |

### 3. 环境感知的数据

`list_tasks` 根据 `env` 参数返回不同数据：

```rust
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
```

## 具体技术实现

### 任务列表生成

```rust
async fn list_tasks(
    &self,
    _env: Option<&str>,
    _limit: Option<i64>,
    _cursor: Option<&str>,
) -> Result<crate::TaskListPage> {
    // 1. 根据 env 选择数据源
    let rows = match _env { ... };
    
    // 2. 构建环境元数据
    let environment_id = _env.map(str::to_string);
    let environment_label = match _env { ... };
    
    // 3. 为每个任务生成完整数据
    let mut out = Vec::new();
    for (id_str, title, status) in rows {
        let id = TaskId(id_str.to_string());
        let diff = mock_diff_for(&id);  // 生成 diff
        let (a, d) = count_from_unified(&diff);  // 统计增删行
        out.push(TaskSummary {
            id,
            title: title.to_string(),
            status,
            updated_at: Utc::now(),
            environment_id: environment_id.clone(),
            environment_label: environment_label.clone(),
            summary: DiffSummary { files_changed: 1, lines_added: a, lines_removed: d },
            is_review: false,
            attempt_total: Some(if id_str == "T-1000" { 2 } else { 1 }),
        });
    }
    
    Ok(crate::TaskListPage { tasks: out, cursor: None })
}
```

### 硬编码 Diff 生成

```rust
fn mock_diff_for(id: &TaskId) -> String {
    match id.0.as_str() {
        "T-1000" => "diff --git a/README.md b/README.md\n...".to_string(),
        "T-1001" => "diff --git a/core/src/lib.rs b/core/src/lib.rs\n...".to_string(),
        _ => "diff --git a/CONTRIBUTING.md b/CONTRIBUTING.md\n...".to_string(),
    }
}
```

### Diff 统计计算

使用 `diffy` crate 解析 unified diff：

```rust
fn count_from_unified(diff: &str) -> (usize, usize) {
    if let Ok(patch) = diffy::Patch::from_str(diff) {
        // 使用 diffy 解析
        patch.hunks().iter()
            .flat_map(diffy::Hunk::lines)
            .fold((0, 0), |(a, d), l| match l {
                diffy::Line::Insert(_) => (a + 1, d),
                diffy::Line::Delete(_) => (a, d + 1),
                _ => (a, d),
            })
    } else {
        // 回退到简单行解析
        let mut a = 0;
        let mut d = 0;
        for l in diff.lines() {
            // 跳过元数据行，统计 +/- 行
        }
        (a, d)
    }
}
```

### Best-of-N Mock 数据

为 `T-1000` 任务提供特殊的兄弟尝试数据：

```rust
async fn list_sibling_attempts(
    &self,
    task: TaskId,
    _turn_id: String,
) -> Result<Vec<TurnAttempt>> {
    if task.0 == "T-1000" {
        return Ok(vec![TurnAttempt {
            turn_id: "T-1000-attempt-2".to_string(),
            attempt_placement: Some(1),
            created_at: Some(Utc::now()),
            status: AttemptStatus::Completed,
            diff: Some(mock_diff_for(&task)),
            messages: vec!["Mock alternate attempt".to_string()],
        }]);
    }
    Ok(Vec::new())
}
```

### 任务创建

生成基于毫秒时间戳的唯一 ID：

```rust
async fn create_task(
    &self,
    env_id: &str,
    prompt: &str,
    git_ref: &str,
    qa_mode: bool,
    best_of_n: usize,
) -> Result<crate::CreatedTask> {
    let _ = (env_id, prompt, git_ref, qa_mode, best_of_n);  // 忽略参数
    let id = format!("task_local_{}", chrono::Utc::now().timestamp_millis());
    Ok(crate::CreatedTask { id: TaskId(id) })
}
```

## 关键代码路径与文件引用

```
codex-rs/cloud-tasks-client/src/mock.rs
├── 导入 (lines 1-12)
│   ├── 从 crate 导入 CloudBackend trait 和类型
│   └── chrono::Utc 用于时间戳
├── MockClient 定义 (lines 14-15)
│   └── #[derive(Clone, Default)]
├── CloudBackend 实现 (lines 17-158)
│   ├── list_tasks() (lines 19-70)
│   │   ├── 环境感知数据选择 (lines 26-37)
│   │   ├── 环境元数据构建 (lines 38-44)
│   │   └── TaskSummary 列表构建 (lines 45-69)
│   ├── get_task_summary() (lines 72-81)
│   │   └── 从 list_tasks 结果查找
│   ├── get_task_diff() (lines 83-85)
│   │   └── 调用 mock_diff_for()
│   ├── get_task_messages() (lines 87-91)
│   ├── get_task_text() (lines 93-102)
│   ├── apply_task() (lines 104-112)
│   ├── apply_task_preflight() (lines 114-126)
│   ├── list_sibling_attempts() (lines 128-144)
│   │   └── T-1000 特殊处理
│   └── create_task() (lines 146-158)
│       └── 时间戳 ID 生成
├── mock_diff_for() (lines 160-172)
│   └── 硬编码 diff 数据
└── count_from_unified() (lines 174-200)
    ├── diffy 解析路径 (lines 175-185)
    └── 简单行解析回退 (lines 186-199)
```

### 依赖文件

| 文件 | 用途 |
|------|------|
| `api.rs` | CloudBackend trait 和类型定义 |

### 调用方

| crate | 用途 |
|-------|------|
| `codex-cloud-tasks` | 单元测试中使用 MockClient |
| `codex-cloud-tasks-client` | 自身测试（如有） |

## 依赖与外部交互

### Cargo.toml 配置

```toml
[features]
mock = []  # 无额外依赖，纯内部实现

[dependencies]
diffy = "0.4.2"  # 用于 diff 解析统计
```

### 外部依赖

| crate | 用途 |
|-------|------|
| `diffy` | 解析 unified diff 计算增删行数 |
| `chrono` | 时间戳生成 |

## 风险、边界与改进建议

### 当前风险

1. **数据硬编码**: 任务 ID、标题、diff 内容都是硬编码，扩展性有限
2. **状态不持久**: `create_task` 创建的任务无法通过 `get_task_summary` 查询
3. **并发问题**: 虽然 `MockClient` 是 `Send + Sync`，但内部无状态共享，多线程安全但行为可能不一致
4. **时间戳依赖**: `create_task` 使用系统时间，测试可能因时间变化而不稳定

### 边界情况

1. **未知任务 ID**: `get_task_summary` 返回错误（从列表中找不到）
2. **空环境过滤**: `_env = None` 返回默认任务列表
3. **Diff 解析失败**: `count_from_unified` 有回退逻辑，但统计可能不准确
4. **参数忽略**: `create_task` 忽略所有参数，仅生成 ID

### 改进建议

1. **可配置 Mock 数据**:
   ```rust
   pub struct MockClient {
       tasks: Arc<Mutex<Vec<TaskSummary>>>,
       config: MockConfig,
   }
   
   pub struct MockConfig {
       pub default_tasks: Vec<MockTask>,
       pub simulate_latency: Option<Duration>,
       pub failure_rate: f64,  // 模拟随机失败
   }
   ```

2. **状态持久化**: 让 `create_task` 创建的任务可查询
   ```rust
   async fn create_task(&self, ...) -> Result<CreatedTask> {
       let task = CreatedTask { id: TaskId(id.clone()) };
       self.tasks.lock().unwrap().push(create_mock_task(&id, ...));
       Ok(task)
   }
   ```

3. **延迟模拟**: 添加可选的异步延迟，模拟真实网络
   ```rust
   async fn list_tasks(&self, ...) -> Result<TaskListPage> {
       if let Some(delay) = self.simulate_latency {
           tokio::time::sleep(delay).await;
       }
       // ...
   }
   ```

4. **错误注入**: 支持模拟各种错误场景
   ```rust
   pub enum MockBehavior {
       Success,
       NetworkError,
       Timeout,
       InvalidResponse,
   }
   ```

5. **使用 Builder 模式**:
   ```rust
   let client = MockClient::builder()
       .with_task(TaskId("T-1".to_string()), "Title", TaskStatus::Ready)
       .with_latency(Duration::from_millis(100))
       .build();
   ```

6. **快照测试支持**: 集成 `insta` 进行 Mock 数据快照验证

7. **文档示例**: 添加使用示例
   ```rust
   /// # Example
   /// ```
   /// use codex_cloud_tasks_client::{MockClient, CloudBackend};
   /// 
   /// let client = MockClient::default();
   /// let tasks = client.list_tasks(None, None, None).await?;
   /// assert!(!tasks.tasks.is_empty());
   /// ```
   ```
