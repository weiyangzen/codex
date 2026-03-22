# control_tests.rs 研究文档

## 场景与职责

`control_tests.rs` 是 `control.rs` 的配套测试模块，包含 30+ 个单元测试和集成测试，全面验证 `AgentControl` 的功能。测试覆盖以下核心场景：

1. **基础操作测试**：验证在没有 manager 时的错误处理
2. **状态管理测试**：验证状态转换和订阅机制
3. **代理生命周期测试**：创建、发送输入、关闭代理
4. **Fork 模式测试**：验证历史继承和输出注入
5. **资源限制测试**：验证 max_threads 限制和槽位释放
6. **恢复测试**：验证从 rollout 文件恢复代理
7. **父子代理协调测试**：验证完成通知机制
8. **昵称管理测试**：验证角色特定昵称和随机分配

## 功能点目的

### 1. 错误处理测试
验证在异常情况下（如 manager 被释放、线程不存在）系统的正确行为：
- `send_input_errors_when_manager_dropped`
- `get_status_returns_not_found_without_manager`
- `spawn_agent_errors_when_manager_dropped`
- `send_input_errors_when_thread_missing`

### 2. 状态转换测试
验证从各种事件正确派生代理状态：
- `on_event_updates_status_from_task_started`
- `on_event_updates_status_from_task_complete`
- `on_event_updates_status_from_error`
- `on_event_updates_status_from_turn_aborted`
- `on_event_updates_status_from_shutdown_complete`

### 3. 代理生命周期测试
验证完整的代理创建、通信、关闭流程：
- `spawn_agent_creates_thread_and_sends_prompt`
- `send_input_submits_user_message`
- `subscribe_status_updates_on_shutdown`

### 4. Fork 模式测试
验证 fork 功能的正确性：
- `spawn_agent_can_fork_parent_thread_history`: 验证历史继承
- `spawn_agent_fork_injects_output_for_parent_spawn_call`: 验证输出注入
- `spawn_agent_fork_flushes_parent_rollout_before_loading_history`: 验证 rollout 刷新顺序

### 5. 资源限制测试
验证 max_threads 限制的强制执行：
- `spawn_agent_respects_max_threads_limit`
- `spawn_agent_releases_slot_after_shutdown`
- `spawn_agent_limit_shared_across_clones`
- `resume_agent_respects_max_threads_limit`
- `resume_agent_releases_slot_after_resume_failure`

### 6. 恢复测试
验证从 rollout 文件恢复代理：
- `resume_agent_errors_when_manager_dropped`
- `resume_thread_subagent_restores_stored_nickname_and_role`

### 7. 父子代理协调测试
验证子代理完成时通知父代理：
- `spawn_child_completion_notifies_parent_history`
- `completion_watcher_notifies_parent_when_child_is_missing`

### 8. 昵称管理测试
验证昵称分配逻辑：
- `spawn_thread_subagent_gets_random_nickname_in_session_source`
- `spawn_thread_subagent_uses_role_specific_nickname_candidates`

## 具体技术实现

### 测试基础设施

#### AgentControlHarness

一个测试辅助结构体，封装了测试所需的资源：

```rust
struct AgentControlHarness {
    _home: TempDir,           // 临时目录，保持存活
    config: Config,           // 测试配置
    manager: ThreadManager,   // 线程管理器
    control: AgentControl,    // 被测对象
}

impl AgentControlHarness {
    async fn new() -> Self {
        let (home, config) = test_config().await;
        let manager = ThreadManager::with_models_provider_and_home_for_tests(
            CodexAuth::from_api_key("dummy"),
            config.model_provider.clone(),
            config.codex_home.clone(),
        );
        let control = manager.agent_control();
        Self { _home: home, config, manager, control }
    }
    
    async fn start_thread(&self) -> (ThreadId, Arc<CodexThread>) {
        let new_thread = self.manager.start_thread(self.config.clone()).await.expect("start thread");
        (new_thread.thread_id, new_thread.thread)
    }
}
```

#### 配置辅助函数

```rust
async fn test_config() -> (TempDir, Config) {
    test_config_with_cli_overrides(Vec::new()).await
}

async fn test_config_with_cli_overrides(
    cli_overrides: Vec<(String, TomlValue)>
) -> (TempDir, Config) {
    let home = TempDir::new().expect("create temp dir");
    let config = ConfigBuilder::default()
        .codex_home(home.path().to_path_buf())
        .cli_overrides(cli_overrides)
        .loader_overrides(LoaderOverrides { ... })
        .build()
        .await
        .expect("load default test config");
    (home, config)
}
```

#### 输入辅助函数

```rust
fn text_input(text: &str) -> Vec<UserInput> {
    vec![UserInput::Text {
        text: text.to_string(),
        text_elements: Vec::new(),
    }]
}
```

### 关键测试模式

#### 1. 验证操作捕获

使用 `ThreadManager` 的测试模式捕获提交的操作：

```rust
let expected = (
    thread_id,
    Op::UserInput {
        items: vec![UserInput::Text { text: "spawned".to_string(), text_elements: Vec::new() }],
        final_output_json_schema: None,
    },
);
let captured = harness.manager.captured_ops()
    .into_iter()
    .find(|entry| *entry == expected);
assert_eq!(captured, Some(expected));
```

#### 2. 等待子代理通知

```rust
async fn wait_for_subagent_notification(parent_thread: &Arc<CodexThread>) -> bool {
    let wait = async {
        loop {
            let history_items = parent_thread.codex.session.clone_history()
                .await.raw_items().to_vec();
            if has_subagent_notification(&history_items) {
                return true;
            }
            sleep(Duration::from_millis(25)).await;
        }
    };
    timeout(Duration::from_secs(2), wait).await.is_ok()
}
```

#### 3. 历史内容验证

```rust
fn history_contains_text(history_items: &[ResponseItem], needle: &str) -> bool {
    history_items.iter().any(|item| {
        let ResponseItem::Message { content, .. } = item else { return false };
        content.iter().any(|content_item| match content_item {
            ContentItem::InputText { text } | ContentItem::OutputText { text } => {
                text.contains(needle)
            }
            ContentItem::InputImage { .. } => false,
        })
    })
}
```

### Fork 测试详解

#### `spawn_agent_can_fork_parent_thread_history`

测试 fork 模式的核心流程：

```rust
async fn spawn_agent_can_fork_parent_thread_history() {
    // 1. 创建父线程并添加历史
    let (parent_thread_id, parent_thread) = harness.start_thread().await;
    parent_thread.inject_user_message_without_turn("parent seed context".to_string()).await;
    
    // 2. 创建 turn 上下文和 spawn 调用记录
    let turn_context = parent_thread.codex.session.new_default_turn().await;
    let parent_spawn_call_id = "spawn-call-history".to_string();
    let parent_spawn_call = ResponseItem::FunctionCall { ... };
    parent_thread.codex.session.record_conversation_items(turn_context.as_ref(), &[parent_spawn_call]).await;
    
    // 3. 确保 rollout 已刷新
    parent_thread.codex.session.ensure_rollout_materialized().await;
    parent_thread.codex.session.flush_rollout().await;
    
    // 4. Fork 创建子代理
    let child_thread_id = harness.control.spawn_agent_with_options(
        harness.config.clone(),
        text_input("child task"),
        Some(SessionSource::SubAgent(SubAgentSource::ThreadSpawn { ... })),
        SpawnAgentOptions { fork_parent_spawn_call_id: Some(parent_spawn_call_id) },
    ).await.expect("forked spawn should succeed");
    
    // 5. 验证子代理包含父代理历史
    let child_thread = harness.manager.get_thread(child_thread_id).await.expect("child thread should be registered");
    let history = child_thread.codex.session.clone_history().await;
    assert!(history_contains_text(history.raw_items(), "parent seed context"));
}
```

### 资源限制测试详解

#### `spawn_agent_respects_max_threads_limit`

验证 max_threads 限制的强制执行：

```rust
async fn spawn_agent_respects_max_threads_limit() {
    let max_threads = 1usize;
    let (_home, config) = test_config_with_cli_overrides(vec![
        ("agents.max_threads".to_string(), TomlValue::Integer(max_threads as i64)),
    ]).await;
    
    // 创建一个线程占用槽位
    let _ = manager.start_thread(config.clone()).await.expect("start thread");
    
    // 第一个代理应该成功
    let first_agent_id = control.spawn_agent(config.clone(), text_input("hello"), None)
        .await.expect("spawn_agent should succeed");
    
    // 第二个代理应该失败，达到限制
    let err = control.spawn_agent(config, text_input("hello again"), None)
        .await.expect_err("spawn_agent should respect max threads");
    
    let CodexErr::AgentLimitReached { max_threads: seen_max_threads } = err else {
        panic!("expected CodexErr::AgentLimitReached");
    };
    assert_eq!(seen_max_threads, max_threads);
}
```

## 关键代码路径与文件引用

### 测试模块结构

| 测试类别 | 测试函数 | 行号范围 |
|----------|----------|----------|
| 错误处理 | `*_errors_when_manager_dropped` | 147-246 |
| 状态转换 | `on_event_updates_status_*` | 173-218 |
| 基础操作 | `send_input_*`, `get_status_*`, `subscribe_status_*` | 247-346 |
| 代理创建 | `spawn_agent_*` | 348-463 |
| Fork 测试 | `spawn_agent_fork_*` | 379-616 |
| 资源限制 | `*_respects_max_threads_*`, `*_releases_slot_*` | 618-806 |
| 父子协调 | `spawn_child_completion_*`, `completion_watcher_*` | 808-877 |
| 昵称管理 | `spawn_thread_subagent_*`, `resume_thread_subagent_*` | 879-1095 |

### 辅助函数

| 函数 | 位置 | 用途 |
|------|------|------|
| `test_config` | 50-52 行 | 创建默认测试配置 |
| `test_config_with_cli_overrides` | 31-48 行 | 创建带 CLI 覆盖的配置 |
| `text_input` | 54-59 行 | 创建文本输入 |
| `AgentControlHarness` | 61-93 行 | 测试辅助结构体 |
| `has_subagent_notification` | 95-110 行 | 检查子代理通知 |
| `history_contains_text` | 113-125 行 | 检查历史内容 |
| `wait_for_subagent_notification` | 127-144 行 | 等待子代理通知 |

## 依赖与外部交互

### 内部模块依赖

```rust
use super::*;  // 导入 control.rs 的所有内容
use crate::CodexAuth;
use crate::CodexThread;
use crate::ThreadManager;
use crate::agent::agent_status_from_event;
use crate::config::AgentRoleConfig;
use crate::config::Config;
use crate::config::ConfigBuilder;
use crate::config_loader::LoaderOverrides;
use crate::contextual_user_message::SUBAGENT_NOTIFICATION_OPEN_TAG;
use crate::features::Feature;
```

### 外部 crate 依赖

```rust
use assert_matches::assert_matches;
use codex_protocol::config_types::ModeKind;
use codex_protocol::models::ContentItem;
use codex_protocol::models::ResponseItem;
use codex_protocol::protocol::*;
use pretty_assertions::assert_eq;
use tempfile::TempDir;
use tokio::time::Duration;
use tokio::time::sleep;
use tokio::time::timeout;
use toml::Value as TomlValue;
```

### 测试框架

- **tokio**: 异步运行时，使用 `#[tokio::test]` 宏
- **tempfile**: 创建临时目录用于测试隔离
- **pretty_assertions**: 提供更清晰的断言失败输出
- **assert_matches**: 模式匹配断言

## 风险、边界与改进建议

### 当前风险

1. **测试超时**：
   - `wait_for_subagent_notification` 使用 2 秒超时
   - 在慢速机器或高负载下可能不稳定
   - `resume_thread_subagent_restores_stored_nickname_and_role` 使用 5 秒超时

2. **状态竞争**：
   - 多个测试可能同时访问 SQLite 数据库
   - `state_db` 的并发访问可能导致测试不稳定

3. **测试顺序依赖**：
   - 虽然 Rust 测试默认并行运行，但某些测试可能隐式依赖文件系统状态
   - 使用 `TempDir` 可以缓解，但需要确保每个测试有独立的目录

4. **硬编码超时**：
   - 超时值（2秒、5秒）是硬编码的
   - 在 CI 环境中可能需要调整

### 边界情况

1. **空输入处理**：
   - `text_input` 函数不验证空字符串
   - 测试中没有覆盖空输入的场景

2. **并发创建代理**：
   - 没有测试多个线程同时创建代理的场景
   - `spawn_agent_limit_shared_across_clones` 测试了克隆，但不是真正的并发

3. **错误恢复**：
   - 大多数测试验证成功路径
   - 错误恢复路径的覆盖相对较少

4. **资源泄漏**：
   - `AgentControlHarness` 使用 `_home` 保持 `TempDir` 存活
   - 如果测试 panic，`TempDir` 的 Drop 实现确保清理

### 改进建议

1. **参数化超时**：
   ```rust
   const TEST_TIMEOUT_SECS: u64 = std::option_env!("TEST_TIMEOUT")
       .map(|s| s.parse().unwrap())
       .unwrap_or(2);
   ```

2. **增加并发测试**：
   - 添加压力测试，同时创建大量代理
   - 验证 Guards 的线程安全性

3. **完善错误场景**：
   - 测试 rollout 文件损坏时的恢复行为
   - 测试磁盘满时的错误处理

4. **使用 rstest 参数化**：
   ```rust
   use rstest::rstest;
   
   #[rstest]
   #[case(1)]
   #[case(5)]
   #[case(10)]
   async fn spawn_agent_respects_max_threads(#[case] max_threads: usize) {
       // 测试不同 max_threads 值
   }
   ```

5. **添加性能基准**：
   - 测量代理创建和关闭的时间
   - 检测性能回归

6. **改进测试文档**：
   - 为复杂测试添加更详细的注释
   - 说明测试的前置条件和预期结果

7. **使用快照测试**：
   - 对于复杂的输出验证，考虑使用 `insta` 快照测试
   - 便于检测意外的输出变更
