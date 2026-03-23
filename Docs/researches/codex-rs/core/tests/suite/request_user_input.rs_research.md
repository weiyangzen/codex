# request_user_input.rs 深入研究

## 场景与职责

`request_user_input.rs` 是 Codex Core 的集成测试文件，专门测试 **request_user_input** 工具的功能。该工具允许 AI 模型在需要用户确认或输入时向用户发起交互式提问。

### 核心测试场景

1. **用户输入请求往返流程**：验证模型发起 `request_user_input` 工具调用后，用户可以通过 `Op::UserInputAnswer` 提交答案，整个流程能够正确完成
2. **模式限制测试**：验证 `request_user_input` 在不同协作模式（Collaboration Mode）下的可用性限制
3. **特性开关测试**：验证 `DefaultModeRequestUserInput` 特性开关对功能可用性的控制

### 协作模式支持矩阵

| 模式 | 默认状态 | 特性开关 | 测试结果 |
|------|---------|---------|---------|
| Plan | 支持 | 无需 | ✅ 可用 |
| Default | 禁用 | `DefaultModeRequestUserInput` | ⚠️ 需启用特性 |
| Execute | 禁用 | 无 | ❌ 永远拒绝 |
| Pair Programming | 禁用 | 无 | ❌ 永远拒绝 |

---

## 功能点目的

### 1. request_user_input 工具

允许模型向用户发起结构化提问，支持：
- **多问题支持**：一次请求可包含多个问题
- **选项式回答**：预定义选项供用户选择
- **自由文本回答**：支持 "Other" 选项的自由输入
- **机密输入**：支持密码等敏感输入（`is_secret`）

### 2. 协作模式控制

不同协作模式对 `request_user_input` 的支持策略：
- **Plan 模式**：完全支持，用于计划确认和决策点
- **Default 模式**：默认禁用，需显式启用特性
- **Execute/Pair Programming 模式**：始终拒绝，保持非交互性

---

## 具体技术实现

### 关键数据结构

```rust
// 问题定义
codex_protocol::request_user_input::RequestUserInputQuestion {
    id: "confirm_path".to_string(),
    header: "Confirm".to_string(),
    question: "Proceed with the plan?".to_string(),
    is_other: true,  // 允许自由文本回答
    is_secret: false,
    options: Some(vec![
        RequestUserInputQuestionOption {
            label: "Yes (Recommended)".to_string(),
            description: "Continue the current plan.".to_string(),
        },
        RequestUserInputQuestionOption {
            label: "No".to_string(),
            description: "Stop and revisit the approach.".to_string(),
        },
    ]),
}

// 答案结构
RequestUserInputAnswer {
    answers: vec!["yes".to_string()],
}

RequestUserInputResponse {
    answers: HashMap<String, RequestUserInputAnswer>,
}
```

### 测试流程架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    用户输入请求测试流程                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    1. 发起请求    ┌─────────────────────┐     │
│  │   模型      │ ────────────────> │  request_user_input │     │
│  │  (Mock)     │                   │     工具调用         │     │
│  └─────────────┘                   └─────────────────────┘     │
│                                           │                     │
│                                           ▼                     │
│  ┌─────────────┐    2. 等待事件    ┌─────────────────────┐     │
│  │   测试      │ <──────────────── │ RequestUserInputEvent│     │
│  │   代码      │                   │   (通过 EventMsg)    │     │
│  └─────────────┘                   └─────────────────────┘     │
│                                           │                     │
│                                           ▼                     │
│  ┌─────────────┐    3. 提交答案    ┌─────────────────────┐     │
│  │   测试      │ ────────────────> │ Op::UserInputAnswer │     │
│  │   代码      │                   │   (通过 codex.submit)│     │
│  └─────────────┘                   └─────────────────────┘     │
│                                           │                     │
│                                           ▼                     │
│  ┌─────────────┐    4. 验证输出    ┌─────────────────────┐     │
│  │   测试      │ <──────────────── │ function_call_output │     │
│  │   代码      │                   │  (包含用户答案 JSON) │     │
│  └─────────────┘                   └─────────────────────┘     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 主测试流程

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn request_user_input_round_trip_resolves_pending() -> anyhow::Result<()> {
    request_user_input_round_trip_for_mode(ModeKind::Plan).await
}

async fn request_user_input_round_trip_for_mode(mode: ModeKind) -> anyhow::Result<()> {
    skip_if_no_network!(Ok(()));
    
    let server = start_mock_server().await;
    let builder = test_codex();
    
    // 配置特性开关（仅 Default 模式需要）
    let TestCodex { codex, cwd, session_configured, .. } = builder
        .with_config(move |config| {
            if mode == ModeKind::Default {
                config.features.enable(Feature::DefaultModeRequestUserInput).expect("...");
            }
        })
        .build(&server)
        .await?;
    
    // 1. 挂载 SSE 响应：包含 request_user_input 函数调用
    let first_response = sse(vec![
        ev_response_created("resp-1"),
        ev_function_call(call_id, "request_user_input", &request_args),
        ev_completed("resp-1"),
    ]);
    responses::mount_sse_once(&server, first_response).await;
    
    // 2. 挂载第二轮 SSE 响应
    let second_mock = responses::mount_sse_once(&server, second_response).await;
    
    // 3. 提交 UserTurn
    codex.submit(Op::UserTurn { ... }).await?;
    
    // 4. 等待 RequestUserInput 事件
    let request = wait_for_event_match(&codex, |event| match event {
        EventMsg::RequestUserInput(request) => Some(request.clone()),
        _ => None,
    }).await;
    
    // 5. 构造并提交答案
    let mut answers = HashMap::new();
    answers.insert("confirm_path".to_string(), RequestUserInputAnswer {
        answers: vec!["yes".to_string()],
    });
    let response = RequestUserInputResponse { answers };
    codex.submit(Op::UserInputAnswer {
        id: request.turn_id.clone(),
        response,
    }).await?;
    
    // 6. 验证输出
    let req = second_mock.single_request();
    let output_text = call_output(&req, call_id);
    assert_eq!(output_json, json!({
        "answers": {
            "confirm_path": { "answers": ["yes"] }
        }
    }));
    
    Ok(())
}
```

### 拒绝测试流程

```rust
async fn assert_request_user_input_rejected<F>(mode_name: &str, build_mode: F) -> anyhow::Result<()>
where
    F: FnOnce(String) -> CollaborationMode,
{
    // ... 设置测试环境 ...
    
    // 提交请求
    codex.submit(Op::UserTurn { ... }).await?;
    
    // 等待 TurnComplete（不应收到 RequestUserInput 事件）
    wait_for_event(&codex, |event| matches!(event, EventMsg::TurnComplete(_))).await;
    
    // 验证返回拒绝消息
    let req = second_mock.single_request();
    let (output, success) = call_output_content_and_success(&req, &call_id);
    assert_eq!(success, None);
    assert_eq!(output, format!("request_user_input is unavailable in {mode_name} mode"));
    
    Ok(())
}
```

---

## 关键代码路径与文件引用

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/suite/request_user_input.rs` | 本测试文件 |
| `codex-rs/core/tests/common/lib.rs` | 测试支持库（wait_for_event 等） |
| `codex-rs/core/tests/common/responses.rs` | SSE Mock 响应工具 |
| `codex-rs/core/tests/common/test_codex.rs` | TestCodex 构建器 |

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/protocol/src/request_user_input.rs` | 用户输入请求协议类型 |
| `codex-rs/protocol/src/protocol.rs` | Op 枚举（UserInputAnswer） |
| `codex-rs/protocol/src/config_types.rs` | CollaborationMode, ModeKind |

### 核心类型定义

```rust
// codex-rs/protocol/src/request_user_input.rs
pub struct RequestUserInputQuestion {
    pub id: String,
    pub header: String,
    pub question: String,
    pub is_other: bool,
    pub is_secret: bool,
    pub options: Option<Vec<RequestUserInputQuestionOption>>,
}

pub struct RequestUserInputEvent {
    pub call_id: String,
    pub turn_id: String,
    pub questions: Vec<RequestUserInputQuestion>,
}

pub struct RequestUserInputResponse {
    pub answers: HashMap<String, RequestUserInputAnswer>,
}

pub struct RequestUserInputAnswer {
    pub answers: Vec<String>,
}
```

### 协作模式定义

```rust
// codex-rs/protocol/src/config_types.rs
pub enum ModeKind {
    Plan,
    Default,
    Execute,
    PairProgramming,
}

pub struct CollaborationMode {
    pub mode: ModeKind,
    pub settings: Settings,
}
```

### 协议 Op 枚举

```rust
// codex-rs/protocol/src/protocol.rs
pub enum Op {
    // ... 其他变体
    UserInputAnswer {
        id: String,
        response: RequestUserInputResponse,
    },
    // ...
}
```

---

## 依赖与外部交互

### 测试依赖

```rust
// 核心依赖
codex_core::features::Feature
codex_protocol::config_types::{CollaborationMode, ModeKind, Settings}
codex_protocol::protocol::{AskForApproval, EventMsg, Op, SandboxPolicy}
codex_protocol::request_user_input::{RequestUserInputAnswer, RequestUserInputResponse}
codex_protocol::user_input::UserInput

// 测试支持
core_test_support::responses::*
core_test_support::skip_if_no_network!
core_test_support::test_codex::{TestCodex, test_codex}
core_test_support::wait_for_event
core_test_support::wait_for_event_match
```

### Mock Server 交互

测试使用 `responses::mount_sse_once` 挂载单次 SSE 响应：

```rust
// 第一轮响应：触发 request_user_input
let first_response = sse(vec![
    ev_response_created("resp-1"),
    ev_function_call(call_id, "request_user_input", &request_args),
    ev_completed("resp-1"),
]);
responses::mount_sse_once(&server, first_response).await;

// 第二轮响应：接收答案后的处理
let second_response = sse(vec![
    ev_assistant_message("msg-1", "thanks"),
    ev_completed("resp-2"),
]);
let second_mock = responses::mount_sse_once(&server, second_response).await;
```

---

## 风险、边界与改进建议

### 当前限制

1. **网络依赖**：需要真实网络环境（Mock Server 本地运行但仍需网络）
2. **多线程要求**：使用 `multi_thread` 运行时，增加测试复杂度
3. **模式硬编码**：新增协作模式需要更新测试

### 边界情况

1. **问题 ID 匹配**：
   - 答案中的问题 ID 必须与请求中的 ID 完全匹配
   - 使用 `HashMap<String, RequestUserInputAnswer>` 存储答案

2. **多答案支持**：
   ```rust
   pub struct RequestUserInputAnswer {
       pub answers: Vec<String>,  // 支持多选
   }
   ```

3. **is_other 标志**：
   - 当 `is_other: true` 时，用户可以提供不在选项中的自定义答案
   - 测试验证 `assert_eq!(request.questions[0].is_other, true)`

### 改进建议

1. **增加边界测试**：
   - 空答案处理
   - 无效问题 ID 处理
   - 超时处理
   - 并发请求处理

2. **扩展模式覆盖**：
   - 测试所有协作模式的组合
   - 验证模式切换时的行为

3. **测试稳定性**：
   - 当前使用 `worker_threads = 2`，考虑减少为单线程以简化调试
   - 增加更明确的事件顺序断言

4. **文档改进**：
   - 增加流程图说明事件顺序
   - 说明 `is_secret` 的使用场景

### 相关测试

- `request_permissions_tool.rs` - 权限请求测试（类似模式）
- `collaboration_instructions.rs` - 协作模式测试
- `plan_tool.rs` - Plan 模式相关测试

### 特性开关依赖

```rust
// 需要启用的特性
codex_core::features::Feature::DefaultModeRequestUserInput
```

特性配置示例：
```rust
config.features.enable(Feature::DefaultModeRequestUserInput)
    .expect("test config should allow feature update");
```
