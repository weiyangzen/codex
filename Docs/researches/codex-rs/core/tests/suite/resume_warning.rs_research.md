# resume_warning.rs 深入研究

## 场景与职责

`resume_warning.rs` 是 Codex Core 的集成测试文件，专门测试**会话恢复时的警告提示**功能。当用户尝试恢复一个使用不同模型创建的会话时，系统会发出警告通知用户模型已变更。

### 核心测试场景

1. **模型不匹配警告**：当恢复会话时，如果当前配置的模型与之前会话使用的模型不同，系统应发出包含两个模型名称的警告事件

### 警告触发条件

```
┌─────────────────────────────────────────────────────────────────┐
│                    模型不匹配警告触发条件                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  恢复前配置                    历史会话状态                      │
│  ┌─────────────┐               ┌─────────────┐                  │
│  │ model:      │               │ model:      │                  │
│  │ "current-   │      !=       │ "previous-  │  ──> 触发警告    │
│  │  model"     │               │  model"     │                  │
│  └─────────────┘               └─────────────┘                  │
│                                                                 │
│  警告内容示例：                                                  │
│  "Model changed from previous-model to current-model"           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 1. 模型变更检测

在会话恢复时检测模型配置变更：
- **历史模型**：从 `InitialHistory` 的 `TurnContextItem` 中读取
- **当前模型**：从当前 `Config` 配置中读取
- **比较逻辑**：字符串比较，不同则触发警告

### 2. 用户通知

通过 `EventMsg::Warning` 事件通知用户：
- **警告级别**：非致命，会话继续
- **信息内容**：包含前后模型名称
- **UI 展示**：前端可据此显示警告横幅

---

## 具体技术实现

### 关键数据结构

```rust
// 恢复历史结构
pub enum InitialHistory {
    Fresh(FreshHistory),      // 新会话
    Resumed(ResumedHistory),  // 恢复会话
}

pub struct ResumedHistory {
    pub conversation_id: ThreadId,
    pub history: Vec<RolloutItem>,  // 历史事件列表
    pub rollout_path: PathBuf,      // rollout 文件路径
}

// Turn 上下文项（包含模型信息）
pub struct TurnContextItem {
    pub turn_id: Option<String>,
    pub model: String,              // 历史会话使用的模型
    pub approval_policy: AskForApproval,
    pub sandbox_policy: SandboxPolicy,
    pub effort: Option<ReasoningEffort>,
    pub summary: ReasoningSummary,
    // ... 其他字段
}
```

### 测试架构

```
┌─────────────────────────────────────────────────────────────────┐
│                      测试执行流程                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 创建临时目录作为 codex_home                                  │
│     let home = TempDir::new().expect("tempdir");                │
│                                                                 │
│  2. 加载默认配置并设置当前模型                                   │
│     config.model = Some("current-model".to_string());           │
│                                                                 │
│  3. 构造恢复历史（使用不同模型）                                 │
│     let initial_history = resume_history(&config, "previous-model", ...);
│                                                                 │
│  4. 创建 ThreadManager 并恢复会话                                │
│     let NewThread { thread: conversation, .. } =                │
│         thread_manager.resume_thread_with_history(...).await?;  │
│                                                                 │
│  5. 等待并验证警告事件                                           │
│     let warning = wait_for_event(&conversation, |ev| {          │
│         matches!(ev, EventMsg::Warning(WarningEvent { message }) │
│             if message.contains("previous-model") &&              │
│                message.contains("current-model")                  │
│     }).await;                                                   │
│                                                                 │
│  6. 验证警告内容                                                 │
│     assert!(message.contains("previous-model"));                │
│     assert!(message.contains("current-model"));                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 测试实现代码

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn emits_warning_when_resumed_model_differs() {
    // 1. 准备测试环境
    let home = TempDir::new().expect("tempdir");
    let mut config = load_default_config_for_test(&home).await;
    config.model = Some("current-model".to_string());
    assert!(config.cwd.is_absolute());

    // 2. 创建 rollout 文件占位符
    let rollout_path = home.path().join("rollout.jsonl");
    std::fs::write(&rollout_path, "").expect("create rollout placeholder");

    // 3. 构造恢复历史（使用 "previous-model"）
    let initial_history = resume_history(&config, "previous-model", &rollout_path);

    // 4. 创建 ThreadManager
    let thread_manager = codex_core::test_support::thread_manager_with_models_provider(
        CodexAuth::from_api_key("test"),
        config.model_provider.clone(),
    );
    let auth_manager =
        codex_core::test_support::auth_manager_from_auth(CodexAuth::from_api_key("test"));

    // 5. 恢复会话
    let NewThread {
        thread: conversation,
        ..
    } = thread_manager
        .resume_thread_with_history(config, initial_history, auth_manager, false, None)
        .await
        .expect("resume conversation");

    // 6. 验证警告事件
    let warning = wait_for_event(&conversation, |ev| {
        matches!(
            ev,
            EventMsg::Warning(WarningEvent { message })
                if message.contains("previous-model") && message.contains("current-model")
        )
    })
    .await;
    
    let EventMsg::Warning(WarningEvent { message }) = warning else {
        panic!("expected warning event");
    };
    assert!(message.contains("previous-model"));
    assert!(message.contains("current-model"));

    // 7. 等待任务清理
    tokio::time::sleep(Duration::from_millis(50)).await;
}
```

### 恢复历史构造函数

```rust
fn resume_history(
    config: &codex_core::config::Config,
    previous_model: &str,           // 历史会话使用的模型
    rollout_path: &std::path::Path,
) -> InitialHistory {
    let turn_id = "resume-warning-seed-turn".to_string();
    
    // 构造 Turn 上下文（包含历史模型信息）
    let turn_ctx = TurnContextItem {
        turn_id: Some(turn_id.clone()),
        trace_id: None,
        cwd: config.cwd.clone(),
        current_date: None,
        timezone: None,
        approval_policy: config.permissions.approval_policy.value(),
        sandbox_policy: config.permissions.sandbox_policy.get().clone(),
        network: None,
        model: previous_model.to_string(),  // <-- 历史模型
        personality: None,
        collaboration_mode: None,
        realtime_active: None,
        effort: config.model_reasoning_effort,
        summary: config.model_reasoning_summary.unwrap_or(ReasoningSummary::Auto),
        user_instructions: None,
        developer_instructions: None,
        final_output_json_schema: None,
        truncation_policy: None,
    };

    // 构造恢复历史
    InitialHistory::Resumed(ResumedHistory {
        conversation_id: ThreadId::default(),
        history: vec![
            RolloutItem::EventMsg(EventMsg::TurnStarted(TurnStartedEvent {
                turn_id: turn_id.clone(),
                model_context_window: None,
                collaboration_mode_kind: ModeKind::Default,
            })),
            RolloutItem::EventMsg(EventMsg::UserMessage(UserMessageEvent {
                message: "seed".to_string(),
                images: None,
                local_images: vec![],
                text_elements: vec![],
            })),
            RolloutItem::TurnContext(turn_ctx),  // <-- 包含历史模型
            RolloutItem::EventMsg(EventMsg::TurnComplete(TurnCompleteEvent {
                turn_id,
                last_agent_message: None,
            })),
        ],
        rollout_path: rollout_path.to_path_buf(),
    })
}
```

---

## 关键代码路径与文件引用

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/suite/resume_warning.rs` | 本测试文件 |
| `codex-rs/core/tests/common/lib.rs` | 测试支持库（wait_for_event） |

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/protocol/src/protocol.rs` | EventMsg::Warning, WarningEvent, InitialHistory, ResumedHistory, TurnContextItem |
| `codex-rs/protocol/src/config_types.rs` | ModeKind, ReasoningSummary |
| `codex-rs/protocol/src/thread_id.rs` | ThreadId |

### 核心类型定义

```rust
// codex-rs/protocol/src/protocol.rs
pub enum EventMsg {
    // ... 其他变体
    Warning(WarningEvent),
    // ...
}

pub struct WarningEvent {
    pub message: String,
}

pub enum InitialHistory {
    Fresh(FreshHistory),
    Resumed(ResumedHistory),
}

pub struct ResumedHistory {
    pub conversation_id: ThreadId,
    pub history: Vec<RolloutItem>,
    pub rollout_path: PathBuf,
}

pub enum RolloutItem {
    EventMsg(EventMsg),
    TurnContext(TurnContextItem),
    ResponseItem(ResponseItem),
    // ...
}
```

### 核心恢复 API

```rust
// codex-rs/core/src/thread_manager.rs（推测）
pub struct ThreadManager { ... }

impl ThreadManager {
    pub async fn resume_thread_with_history(
        &self,
        config: Config,
        initial_history: InitialHistory,
        auth_manager: AuthManager,
        // ... 其他参数
    ) -> Result<NewThread> { ... }
}

pub struct NewThread {
    pub thread: Arc<CodexThread>,
    pub session_configured: SessionConfiguredEvent,
    // ...
}
```

---

## 依赖与外部交互

### 测试依赖

```rust
// 核心依赖
codex_core::CodexAuth
codex_core::NewThread
codex_protocol::ThreadId
codex_protocol::config_types::{ModeKind, ReasoningSummary}
codex_protocol::protocol::{
    EventMsg, InitialHistory, ResumedHistory, RolloutItem,
    TurnCompleteEvent, TurnContextItem, TurnStartedEvent,
    UserMessageEvent, WarningEvent,
}

// 测试支持
core_test_support::load_default_config_for_test
core_test_support::wait_for_event
```

### 测试支持函数

```rust
// 创建带模型提供者的 ThreadManager
codex_core::test_support::thread_manager_with_models_provider(
    auth: CodexAuth,
    model_provider: ModelProviderInfo,
) -> ThreadManager

// 从认证信息创建 AuthManager
codex_core::test_support::auth_manager_from_auth(
    auth: CodexAuth
) -> AuthManager
```

---

## 风险、边界与改进建议

### 当前限制

1. **单一测试场景**：仅测试模型不匹配警告，未覆盖其他警告类型
2. **硬编码模型名称**：使用 `"current-model"` 和 `"previous-model"` 作为测试数据
3. **无网络模拟**：测试不依赖网络，但未模拟网络恢复场景

### 边界情况

1. **相同模型**：如果当前模型与历史模型相同，不应触发警告
2. **空模型**：如果历史或当前模型为空，应有默认处理
3. **模型别名**：同一模型的不同别名（如 `gpt-4` 和 `gpt-4-0613`）是否应视为不同
4. **多轮历史**：如果历史包含多个不同模型的轮次，应使用哪一个进行比较

### 改进建议

1. **扩展测试覆盖**：
   ```rust
   // 建议添加的测试
   #[tokio::test]
   async fn no_warning_when_model_unchanged() { ... }
   
   #[tokio::test]
   async fn warning_with_multiple_model_transitions() { ... }
   
   #[tokio::test]
   async fn warning_with_empty_model_in_history() { ... }
   ```

2. **使用真实模型名称**：
   - 使用类似 `"gpt-5.2"` 和 `"gpt-5.2-codex"` 的真实模型名称
   - 增加测试的可读性和可维护性

3. **验证警告格式**：
   ```rust
   // 不仅验证包含模型名称，还验证完整格式
   assert!(message.matches("previous-model").count() == 1);
   assert!(message.matches("current-model").count() == 1);
   ```

4. **并发安全**：
   - 当前使用 `multi_thread`，考虑是否可以使用 `current_thread` 简化

5. **文档改进**：
   - 说明警告消息的生成逻辑
   - 说明模型比较的规则

### 相关测试

- `resume.rs` - 基础恢复功能测试
- `compact_resume_fork.rs` - 压缩和恢复测试
- `model_switching.rs` - 模型切换测试

### 警告事件处理模式

```rust
// 通用的警告事件等待模式
let warning = wait_for_event(&conversation, |ev| {
    matches!(ev, EventMsg::Warning(WarningEvent { message })
        if condition(message)
    )
}).await;

// 确保消费完所有事件避免测试间干扰
tokio::time::sleep(Duration::from_millis(50)).await;
```
