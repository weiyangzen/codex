# review.rs 深入研究

## 场景与职责

`review.rs` 是 Codex Core 的集成测试文件，专门测试**代码审查（Code Review）**功能。该功能允许用户请求 AI 对代码变更进行审查，返回结构化的审查结果。

### 核心测试场景

1. **基础审查流程**：验证 `Op::Review` 提交后，系统进入审查模式并返回结构化审查结果
2. **纯文本回退**：验证当模型返回非 JSON 纯文本时，系统能正确回退处理
3. **事件过滤**：验证审查流程中正确过滤助手消息相关事件（AgentMessageContentDelta, AgentMessageDelta）
4. **结构化输出抑制助手消息**：验证结构化审查输出时只发送单一 AgentMessage
5. **自定义审查模型**：验证配置 `review_model` 时审查请求使用指定模型
6. **默认会话模型**：验证未配置 `review_model` 时审查使用会话当前模型
7. **历史隔离**：验证审查会话与父会话历史隔离，不继承父会话消息
8. **历史回传**：验证审查完成后历史正确回传到父会话
9. **覆盖 CWD 的基准分支审查**：验证审查使用当前工作目录（包括运行时覆盖）解析基准分支

---

## 功能点目的

### 1. 代码审查模式

独立的审查会话流程：
- **隔离执行**：审查在子会话中执行，不影响父会话
- **结构化输出**：支持 JSON 格式的审查结果
- **纯文本回退**：非 JSON 响应作为整体解释处理
- **生命周期事件**：EnteredReviewMode -> 审查执行 -> ExitedReviewMode -> TurnComplete

### 2. 审查目标类型

```rust
pub enum ReviewTarget {
    /// 与基准分支比较（Git diff 审查）
    BaseBranch { branch: String },
    /// 与特定提交比较
    Commit { sha: String, title: Option<String> },
    /// 自定义审查指令
    Custom { instructions: String },
}
```

### 3. 审查输出结构

```rust
pub struct ReviewOutputEvent {
    pub findings: Vec<ReviewFinding>,           // 发现问题列表
    pub overall_correctness: String,            // 整体正确性评估
    pub overall_explanation: String,            // 整体解释
    pub overall_confidence_score: f32,          // 置信度分数
}

pub struct ReviewFinding {
    pub title: String,                          // 问题标题
    pub body: String,                           // 问题详细描述
    pub confidence_score: f32,                  // 置信度
    pub priority: i32,                          // 优先级
    pub code_location: ReviewCodeLocation,      // 代码位置
}
```

---

## 具体技术实现

### 关键数据结构

```rust
// 审查请求
pub struct ReviewRequest {
    pub target: ReviewTarget,
    pub user_facing_hint: Option<String>,  // 用户提示
}

// 审查操作
pub enum Op {
    // ... 其他变体
    Review { review_request: ReviewRequest },
    // ...
}

// 审查生命周期事件
pub enum EventMsg {
    EnteredReviewMode(ReviewRequest),           // 进入审查模式
    ExitedReviewMode(ExitedReviewModeEvent),    // 退出审查模式
    // ...
}

pub struct ExitedReviewModeEvent {
    pub review_output: Option<ReviewOutputEvent>,
}
```

### 审查流程架构

```
┌─────────────────────────────────────────────────────────────────┐
│                      代码审查流程                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  父会话                                                          │
│  ┌─────────────┐                                                │
│  │ 提交 Review │───> Op::Review { review_request }               │
│  └─────────────┘                                                │
│         │                                                       │
│         ▼                                                       │
│  EventMsg::EnteredReviewMode(ReviewRequest)                     │
│         │                                                       │
│         ▼                                                       │
│  ┌─────────────┐     子会话（隔离）     ┌─────────────┐         │
│  │  创建审查   │──────────────────────>│ 审查执行    │         │
│  │   子任务    │                       │             │         │
│  └─────────────┘                       └─────────────┘         │
│                                               │                 │
│                                               ▼                 │
│  ┌─────────────┐                       模型调用（SSE）          │
│  │  审查结果   │<────────────────────── 返回审查结果            │
│  │  回传父会话 │                                                │
│  └─────────────┘                                                │
│         │                                                       │
│         ▼                                                       │
│  EventMsg::ExitedReviewMode(ExitedReviewModeEvent {             │
│      review_output: Some(ReviewOutputEvent)                     │
│  })                                                             │
│         │                                                       │
│         ▼                                                       │
│  EventMsg::TurnComplete(_)                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 测试 1：基础审查流程

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn review_op_emits_lifecycle_and_review_output() {
    skip_if_no_network!();
    
    // 1. 构造结构化审查 JSON
    let review_json = serde_json::json!({
        "findings": [{
            "title": "Prefer Stylize helpers",
            "body": "Use .dim()/.bold() chaining instead of manual Style where possible.",
            "confidence_score": 0.9,
            "priority": 1,
            "code_location": {
                "absolute_file_path": "/tmp/file.rs",
                "line_range": {"start": 10, "end": 20}
            }
        }],
        "overall_correctness": "good",
        "overall_explanation": "All good with some improvements suggested.",
        "overall_confidence_score": 0.8
    }).to_string();
    
    // 2. 构造 SSE 模板
    let sse_template = r#"[
        {"type":"response.output_item.done", "item":{
            "type":"message", "role":"assistant",
            "content":[{"type":"output_text","text":__REVIEW__}]
        }},
        {"type":"response.completed", "response": {"id": "__ID__"}}
    ]"#;
    let review_json_escaped = serde_json::to_string(&review_json).unwrap();
    let sse_raw = sse_template.replace("__REVIEW__", &review_json_escaped);
    
    // 3. 启动 Mock Server 并创建会话
    let (server, _request_log) = start_responses_server_with_sse(&sse_raw, 1).await;
    let codex = new_conversation_for_server(&server, codex_home.clone(), |_| {}).await;
    
    // 4. 提交审查请求
    codex.submit(Op::Review {
        review_request: ReviewRequest {
            target: ReviewTarget::Custom {
                instructions: "Please review my changes".to_string(),
            },
            user_facing_hint: None,
        },
    }).await.unwrap();
    
    // 5. 验证生命周期事件
    let _entered = wait_for_event(&codex, |ev| matches!(ev, EventMsg::EnteredReviewMode(_))).await;
    let closed = wait_for_event(&codex, |ev| matches!(ev, EventMsg::ExitedReviewMode(_))).await;
    let review = match closed {
        EventMsg::ExitedReviewMode(ev) => ev.review_output.expect("expected review output"),
        other => panic!("expected ExitedReviewMode(..), got {other:?}"),
    };
    
    // 6. 验证审查结果
    let expected = ReviewOutputEvent {
        findings: vec![ReviewFinding { ... }],
        overall_correctness: "good".to_string(),
        overall_explanation: "All good with some improvements suggested.".to_string(),
        overall_confidence_score: 0.8,
    };
    assert_eq!(expected, review);
    
    // 7. 验证 rollout 记录
    let path = codex.rollout_path().expect("rollout path");
    let text = std::fs::read_to_string(&path).expect("read rollout file");
    // 验证包含审查标题和格式化发现行
    assert!(saw_header);  // "full review output from reviewer model"
    assert!(saw_finding_line);  // "- Prefer Stylize helpers — /tmp/file.rs:10-20"
}
```

### 测试 2：纯文本回退

```rust
#[tokio::test]
async fn review_op_with_plain_text_emits_review_fallback() {
    skip_if_no_network!();
    
    // 模型返回纯文本而非 JSON
    let sse_raw = r#"[
        {"type":"response.output_item.done", "item":{
            "type":"message", "role":"assistant",
            "content":[{"type":"output_text","text":"just plain text"}]
        }},
        {"type":"response.completed", "response": {"id": "__ID__"}}
    ]"#;
    
    // 验证回退到结构化格式，整体解释包含纯文本
    let expected = ReviewOutputEvent {
        overall_explanation: "just plain text".to_string(),
        ..Default::default()
    };
    assert_eq!(expected, review);
}
```

### 测试 3：事件过滤

```rust
#[tokio::test]
async fn review_filters_agent_message_related_events() {
    skip_if_no_network!();
    
    // SSE 包含打字效果和增量更新
    let sse_raw = r#"[
        {"type":"response.output_item.added", "item":{...}},
        {"type":"response.output_text.delta", "delta":"Hi"},
        {"type":"response.output_text.delta", "delta":" there"},
        {"type":"response.output_item.done", "item":{...}},
        {"type":"response.completed", "response": {"id": "__ID__"}}
    ]"#;
    
    // 验证这些事件被过滤，不会 surfaced 到客户端
    wait_for_event(&codex, |event| match event {
        EventMsg::TurnComplete(_) => true,
        EventMsg::AgentMessageContentDelta(_) => {
            panic!("unexpected AgentMessageContentDelta surfaced during review")
        }
        EventMsg::AgentMessageDelta(_) => {
            panic!("unexpected AgentMessageDelta surfaced during review")
        }
        _ => false,
    }).await;
}
```

### 测试 4：结构化输出抑制助手消息

```rust
#[tokio::test]
async fn review_does_not_emit_agent_message_on_structured_output() {
    skip_if_no_network!();
    
    // 模型返回结构化 JSON
    let review_json = serde_json::json!({...}).to_string();
    
    // 验证只看到一个 AgentMessage
    let mut agent_messages = 0;
    wait_for_event(&codex, |event| match event {
        EventMsg::TurnComplete(_) => true,
        EventMsg::AgentMessage(_) => { agent_messages += 1; false }
        ...
    }).await;
    assert_eq!(1, agent_messages, "expected exactly one AgentMessage event");
}
```

### 测试 5 & 6：审查模型选择

```rust
// 测试 5：使用自定义 review_model
#[tokio::test]
async fn review_uses_custom_review_model_from_config() {
    let codex = new_conversation_for_server(&server, codex_home.clone(), |cfg| {
        cfg.model = Some("gpt-4.1".to_string());        // 会话模型
        cfg.review_model = Some("gpt-5.1".to_string()); // 审查模型
    }).await;
    
    // 验证请求使用 gpt-5.1
    let body = request.body_json();
    assert_eq!(body["model"].as_str().unwrap(), "gpt-5.1");
}

// 测试 6：使用会话模型
#[tokio::test]
async fn review_uses_session_model_when_review_model_unset() {
    let codex = new_conversation_for_server(&server, codex_home.clone(), |cfg| {
        cfg.model = Some("gpt-4.1".to_string());
        cfg.review_model = None;
    }).await;
    
    // 验证请求使用 gpt-4.1
    assert_eq!(body["model"].as_str().unwrap(), "gpt-4.1");
}
```

### 测试 7：历史隔离

```rust
#[tokio::test]
async fn review_input_isolated_from_parent_history() {
    // 1. 创建带有历史记录的父会话
    let session_file = codex_home.path().join("resume.jsonl");
    // 写入 session_meta + user message + assistant message
    
    // 2. 从该文件恢复会话
    let codex = resume_conversation_for_server(&server, codex_home.clone(), session_file, |_| {}).await;
    
    // 3. 提交审查请求
    codex.submit(Op::Review { ... }).await?;
    
    // 4. 验证审查请求 input 只包含环境上下文和审查提示
    let input = body["input"].as_array().expect("input array");
    // 验证不包含父会话历史
    // 验证包含 ENVIRONMENT_CONTEXT_OPEN_TAG
    // 验证包含审查提示文本
    
    // 5. 验证 instructions 等于 REVIEW_PROMPT
    assert_eq!(instructions, REVIEW_PROMPT);
}
```

### 测试 8：历史回传

```rust
#[tokio::test]
async fn review_history_surfaces_in_parent_session() {
    // 1. 运行审查（产生 "review assistant output"）
    codex.submit(Op::Review { ... }).await?;
    wait_for_event(&codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;
    
    // 2. 在父会话继续对话
    codex.submit(Op::UserInput { items: vec![...] }).await?;
    wait_for_event(&codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;
    
    // 3. 验证第二次请求 input 包含审查相关内容
    let contains_review_rollout_user = input.iter().any(|msg| {
        msg["content"][0]["text"].as_str().unwrap_or_default()
            .contains("User initiated a review task.")
    });
    let contains_review_assistant = input.iter().any(|msg| {
        msg["content"][0]["text"].as_str().unwrap_or_default()
            .contains("review assistant output")
    });
}
```

### 测试 9：覆盖 CWD 的基准分支审查

```rust
#[tokio::test]
async fn review_uses_overridden_cwd_for_base_branch_merge_base() {
    // 1. 创建 Git 仓库
    let repo_dir = TempDir::new().unwrap();
    run_git(repo_path, &["init", "-b", "main"]);
    run_git(repo_path, &["commit", "-m", "initial"]);
    let head_sha = ...; // 获取 HEAD SHA
    
    // 2. 创建会话，初始 CWD 为临时目录
    let codex = new_conversation_for_server(&server, codex_home.clone(), |config| {
        config.cwd = initial_cwd_path;  // 非仓库目录
    }).await;
    
    // 3. 覆盖 CWD 为仓库目录
    codex.submit(Op::OverrideTurnContext {
        cwd: Some(repo_path.to_path_buf()),
        ...
    }).await?;
    
    // 4. 提交基准分支审查请求
    codex.submit(Op::Review {
        review_request: ReviewRequest {
            target: ReviewTarget::BaseBranch { branch: "main".to_string() },
            ...
        },
    }).await?;
    
    // 5. 验证审查提示包含 merge-base SHA
    let saw_merge_base_sha = input.iter()
        .filter_map(|msg| msg["content"][0]["text"].as_str())
        .any(|text| text.contains(&head_sha));
}
```

---

## 关键代码路径与文件引用

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/suite/review.rs` | 本测试文件 |
| `codex-rs/core/tests/common/lib.rs` | 测试支持库 |
| `codex-rs/core/tests/common/responses.rs` | SSE Mock 响应工具 |

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/protocol/src/protocol.rs` | ReviewRequest, ReviewTarget, ReviewOutputEvent, ReviewFinding, ExitedReviewModeEvent |
| `codex-rs/core/src/client_common.rs` | REVIEW_PROMPT |
| `codex-rs/core/src/review_format.rs` | render_review_output_text |

### 核心类型定义

```rust
// codex-rs/protocol/src/protocol.rs
pub enum ReviewTarget {
    BaseBranch { branch: String },
    Commit { sha: String, title: Option<String> },
    Custom { instructions: String },
}

pub struct ReviewRequest {
    pub target: ReviewTarget,
    pub user_facing_hint: Option<String>,
}

pub struct ReviewOutputEvent {
    pub findings: Vec<ReviewFinding>,
    pub overall_correctness: String,
    pub overall_explanation: String,
    pub overall_confidence_score: f32,
}

pub struct ReviewFinding {
    pub title: String,
    pub body: String,
    pub confidence_score: f32,
    pub priority: i32,
    pub code_location: ReviewCodeLocation,
}

pub struct ReviewCodeLocation {
    pub absolute_file_path: PathBuf,
    pub line_range: ReviewLineRange,
}

pub struct ReviewLineRange {
    pub start: u32,
    pub end: u32,
}
```

### 测试辅助函数

```rust
// 启动带 SSE 的 Mock Server
async fn start_responses_server_with_sse(
    sse_raw: &str,
    expected_requests: usize,
) -> (MockServer, ResponseMock) {
    let server = start_mock_server().await;
    let sse = load_sse_fixture_with_id_from_str(sse_raw, &Uuid::new_v4().to_string());
    let responses = vec![sse; expected_requests];
    let request_log = mount_sse_sequence(&server, responses).await;
    (server, request_log)
}

// 创建新会话
async fn new_conversation_for_server<F>(
    server: &MockServer,
    codex_home: Arc<TempDir>,
    mutator: F,
) -> Arc<CodexThread>

// 恢复会话
async fn resume_conversation_for_server<F>(
    server: &MockServer,
    codex_home: Arc<TempDir>,
    resume_path: PathBuf,
    mutator: F,
) -> Arc<CodexThread>
```

---

## 依赖与外部交互

### 测试依赖

```rust
// 核心依赖
codex_core::CodexThread
codex_core::REVIEW_PROMPT
codex_core::config::Config
codex_core::review_format::render_review_output_text
codex_protocol::models::{ContentItem, ResponseItem}
codex_protocol::protocol::{
    EventMsg, ExitedReviewModeEvent, Op, ReviewCodeLocation, ReviewFinding,
    ReviewLineRange, ReviewOutputEvent, ReviewRequest, ReviewTarget,
    RolloutItem, RolloutLine, ENVIRONMENT_CONTEXT_OPEN_TAG,
}
codex_protocol::user_input::UserInput

// 测试支持
core_test_support::load_sse_fixture_with_id_from_str
core_test_support::responses::*
core_test_support::skip_if_no_network!
core_test_support::test_codex::test_codex
core_test_support::wait_for_event
```

### Git 操作

```rust
fn run_git(repo_path: &std::path::Path, args: &[&str]) {
    let output = std::process::Command::new("git")
        .arg("-C").arg(repo_path)
        .args(args)
        .output()
        .expect("spawn git");
    assert!(output.status.success(), ...);
}
```

---

## 风险、边界与改进建议

### 当前限制

1. **平台特定**：Windows 测试使用更多工作线程（4 vs 2）
2. **网络依赖**：所有测试都需要网络
3. **Git 依赖**：`review_uses_overridden_cwd_for_base_branch_merge_base` 需要 Git

### 边界情况

1. **JSON 解析失败**：非 JSON 响应回退到纯文本处理
2. **空审查结果**：应返回空 findings 列表
3. **模型不可用**：如果 `review_model` 无效，应有错误处理
4. **并发审查**：多个审查请求同时提交的处理

### 改进建议

1. **增加错误场景测试**：
   - 模型返回无效 JSON
   - 审查超时
   - 网络中断恢复

2. **性能测试**：
   - 大文件审查性能
   - 多 finding 处理

3. **测试稳定性**：
   - 减少 Windows 特定代码
   - 统一工作线程配置

4. **文档改进**：
   - 说明审查子会话的生命周期
   - 说明历史隔离的实现机制

### 相关测试

- `request_permissions_tool.rs` - 权限请求测试
- `request_user_input.rs` - 用户输入测试
- `resume.rs` - 会话恢复测试

### 审查提示常量

```rust
// codex-rs/core/src/client_common.rs
pub const REVIEW_PROMPT: &str = "...";  // 审查提示模板
```
