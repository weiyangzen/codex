# turn_start.rs 研究文档

## 文件基本信息

- **文件路径**: `codex-rs/app-server/tests/suite/v2/turn_start.rs`
- **文件类型**: Rust 集成测试文件
- **所属模块**: app-server v2 API 测试套件
- **测试框架**: tokio::test + wiremock + tempfile

---

## 1. 场景与职责

### 1.1 核心职责

`turn_start.rs` 是 Codex App Server v2 API 的集成测试文件，专注于测试 `turn/start` JSON-RPC 方法的各种场景。该方法用于在已存在的线程（Thread）中启动一个新的对话回合（Turn）。

### 1.2 测试覆盖场景

| 场景类别 | 具体场景 | 测试函数 |
|---------|---------|---------|
| 基础功能 | 发送 originator header | `turn_start_sends_originator_header` |
| 输入处理 | 用户消息带 text elements | `turn_start_emits_user_message_item_with_text_elements` |
| 输入限制 | 文本长度限制（边界值） | `turn_start_accepts_text_at_limit_with_mention_item` |
| 输入验证 | 超大文本拒绝 | `turn_start_rejects_combined_oversized_text_input` |
| 状态管理 | 通知发送与模型覆盖 | `turn_start_emits_notifications_and_accepts_model_override` |
| 协作模式 | 协作模式覆盖 | `turn_start_accepts_collaboration_mode_override_v2` |
| 功能标志 | 线程功能覆盖 | `turn_start_uses_thread_feature_overrides_for_collaboration_mode_instructions_v2` |
| 人格设置 | 人格覆盖与变更 | `turn_start_accepts_personality_override_v2`, `turn_start_change_personality_mid_thread_v2` |
| 迁移场景 | 迁移的 pragmatic 人格 | `turn_start_uses_migrated_pragmatic_personality_without_override_v2` |
| 多模态 | 本地图片输入 | `turn_start_accepts_local_image_input` |
| 执行审批 | 审批开关切换 | `turn_start_exec_approval_toggle_v2` |
| 执行审批 | 拒绝执行 | `turn_start_exec_approval_decline_v2` |
| 沙盒管理 | 沙盒与 cwd 更新 | `turn_start_updates_sandbox_and_cwd_between_turns_v2` |
| 文件变更 | 文件变更审批 | `turn_start_file_change_approval_v2` |
| Agent 协作 | Spawn agent 元数据 | `turn_start_emits_spawn_agent_item_with_model_metadata_v2` |
| Agent 协作 | 角色模型元数据 | `turn_start_emits_spawn_agent_item_with_effective_role_model_metadata_v2` |
| 会话持久 | AcceptForSession 持久化 | `turn_start_file_change_approval_accept_for_session_persists_v2` |
| 文件变更 | 拒绝文件变更 | `turn_start_file_change_approval_decline_v2` |
| 进程管理 | 进程 ID 报告 | `command_execution_notifications_include_process_id` |

---

## 2. 功能点目的

### 2.1 turn/start API 的核心目的

`turn/start` 是 Codex App Server v2 协议中用于**启动对话回合**的核心 API。其设计目的包括：

1. **用户输入提交**: 接收用户的多模态输入（文本、图片、Mention 等）
2. **动态配置覆盖**: 允许每回合动态覆盖模型、沙盒策略、审批策略等配置
3. **状态生命周期管理**: 管理回合的启动、进行中、完成/失败状态转换
4. **协作模式支持**: 支持多 Agent 协作场景下的回合管理
5. **人格与指令**: 支持人格（Personality）和开发者指令的动态切换

### 2.2 测试的核心验证点

```rust
// TurnStartParams 核心字段
pub struct TurnStartParams {
    pub thread_id: String,           // 目标线程
    pub input: Vec<UserInput>,       // 用户输入（文本/图片/Mention）
    pub cwd: Option<PathBuf>,        // 工作目录覆盖
    pub approval_policy: Option<AskForApproval>,      // 审批策略覆盖
    pub approvals_reviewer: Option<ApprovalsReviewer>, // 审批人覆盖
    pub sandbox_policy: Option<SandboxPolicy>,        // 沙盒策略覆盖
    pub model: Option<String>,       // 模型覆盖
    pub service_tier: Option<Option<ServiceTier>>,    // 服务层级覆盖
    pub effort: Option<ReasoningEffort>,              // 推理努力度覆盖
    pub summary: Option<ReasoningSummary>,            // 推理摘要覆盖
    pub personality: Option<Personality>,             // 人格覆盖
    pub output_schema: Option<JsonValue>,             // 输出 Schema
    pub collaboration_mode: Option<CollaborationMode>, // 协作模式（实验性）
}
```

---

## 3. 具体技术实现

### 3.1 测试架构

```
┌─────────────────────────────────────────────────────────────┐
│                        Test Case                             │
├─────────────────────────────────────────────────────────────┤
│  1. Setup: 创建临时目录 + Mock 服务器 + 配置                   │
│     └─ TempDir::new()                                         │
│     └─ create_mock_responses_server_sequence()               │
│     └─ create_config_toml()                                   │
├─────────────────────────────────────────────────────────────┤
│  2. Init: 启动 MCP 进程并初始化                               │
│     └─ McpProcess::new()                                      │
│     └─ mcp.initialize()                                       │
├─────────────────────────────────────────────────────────────┤
│  3. Thread: 启动线程                                          │
│     └─ mcp.send_thread_start_request()                       │
│     └─ mcp.read_stream_until_response_message()              │
├─────────────────────────────────────────────────────────────┤
│  4. Action: 发送 turn/start 请求                              │
│     └─ mcp.send_turn_start_request()                         │
│     └─ 等待响应 + 通知                                        │
├─────────────────────────────────────────────────────────────┤
│  5. Assert: 验证结果                                          │
│     └─ 响应状态                                               │
│     └─ 通知消息（item/started, turn/completed 等）           │
│     └─ Mock 服务器请求内容                                    │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 关键数据结构

#### 3.2.1 UserInput 类型（V2 协议）

```rust
// codex-app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
pub enum UserInput {
    Text {
        text: String,
        text_elements: Vec<TextElement>,  // 富文本元素（高亮、引用等）
    },
    LocalImage {
        path: PathBuf,  // 本地图片路径
    },
    Mention {
        name: String,   // 提及的 App/Agent 名称
        path: String,   // App URI
    },
}
```

#### 3.2.2 Turn 状态

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct Turn {
    pub id: String,
    pub items: Vec<ThreadItem>,  // 回合中的项目（消息、工具调用等）
    pub status: TurnStatus,
    pub error: Option<TurnError>,
}

pub enum TurnStatus {
    Completed,
    Interrupted,
    Failed,
    InProgress,
}
```

### 3.3 关键流程

#### 3.3.1 输入长度验证流程

```rust
// codex_message_processor.rs
async fn turn_start(&self, request_id: ConnectionRequestId, params: TurnStartParams, ...) {
    // 1. 验证输入长度限制
    if let Err(error) = Self::validate_v2_input_limit(&params.input) {
        self.outgoing.send_error(request_id, error).await;
        return;
    }
    // ...
}

fn validate_v2_input_limit(input: &[UserInput]) -> Result<(), JSONRPCErrorError> {
    const MAX_USER_INPUT_TEXT_CHARS: usize = 100_000;  // 10万字符限制
    // 计算所有文本输入的总长度
    let total_chars = input.iter().map(|item| {
        match item {
            UserInput::Text { text, .. } => text.chars().count(),
            _ => 0,
        }
    }).sum::<usize>();
    
    if total_chars > MAX_USER_INPUT_TEXT_CHARS {
        return Err(JSONRPCErrorError {
            code: INVALID_PARAMS_ERROR_CODE,
            message: format!("Input exceeds the maximum length of {MAX_USER_INPUT_TEXT_CHARS} characters."),
            data: Some(json!({
                "input_error_code": INPUT_TOO_LARGE_ERROR_CODE,
                "max_chars": MAX_USER_INPUT_TEXT_CHARS,
                "actual_chars": total_chars,
            })),
        });
    }
    Ok(())
}
```

#### 3.3.2 配置覆盖流程

```rust
// 检测是否有任何覆盖配置
let has_any_overrides = params.cwd.is_some()
    || params.approval_policy.is_some()
    || params.approvals_reviewer.is_some()
    || params.sandbox_policy.is_some()
    || params.model.is_some()
    || params.service_tier.is_some()
    || params.effort.is_some()
    || params.summary.is_some()
    || collaboration_mode.is_some()
    || params.personality.is_some();

// 如果有覆盖，先发送 OverrideTurnContext Op
if has_any_overrides {
    let _ = self.submit_core_op(
        &request_id,
        thread.as_ref(),
        Op::OverrideTurnContext {
            cwd: params.cwd,
            approval_policy: params.approval_policy.map(AskForApproval::to_core),
            approvals_reviewer: params.approvals_reviewer.map(...),
            sandbox_policy: params.sandbox_policy.map(|p| p.to_core()),
            windows_sandbox_level: None,
            model: params.model,
            effort: params.effort.map(Some),
            summary: params.summary,
            service_tier: params.service_tier,
            collaboration_mode,
            personality: params.personality,
        },
    ).await;
}

// 然后发送用户输入
let turn_id = self.submit_core_op(
    &request_id,
    thread.as_ref(),
    Op::UserInput {
        items: mapped_items,
        final_output_json_schema: params.output_schema,
    },
).await;
```

### 3.4 Mock 服务器响应构建

```rust
// tests/common/responses.rs
pub fn create_final_assistant_message_sse_response(message: &str) -> anyhow::Result<String> {
    Ok(responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_assistant_message("msg-1", message),
        responses::ev_completed("resp-1"),
    ]))
}

pub fn create_shell_command_sse_response(
    command: Vec<String>,
    workdir: Option<&Path>,
    timeout_ms: Option<u64>,
    call_id: &str,
) -> anyhow::Result<String> {
    let command_str = shlex::try_join(command.iter().map(String::as_str))?;
    let tool_call_arguments = serde_json::to_string(&json!({
        "command": command_str,
        "workdir": workdir.map(|w| w.to_string_lossy()),
        "timeout_ms": timeout_ms
    }))?;
    Ok(responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_function_call(call_id, "shell_command", &tool_call_arguments),
        responses::ev_completed("resp-1"),
    ]))
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/app-server/src/codex_message_processor.rs:5928` | `turn_start` 方法实现 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3828` | `TurnStartParams` 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3937` | `TurnStartResponse` 定义 |
| `codex-rs/app-server/tests/common/mcp_process.rs:531` | `send_turn_start_request` 辅助方法 |

### 4.2 测试辅助文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/app-server/tests/common/lib.rs` | 测试库公共导出 |
| `codex-rs/app-server/tests/common/mcp_process.rs` | MCP 进程管理 |
| `codex-rs/app-server/tests/common/mock_model_server.rs` | Mock 模型服务器 |
| `codex-rs/app-server/tests/common/responses.rs` | SSE 响应构建器 |
| `codex-rs/app-server/tests/common/config.rs` | 测试配置生成 |

### 4.3 协议定义文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 协议类型定义 |
| `codex-rs/protocol/src/user_input.rs` | 用户输入核心类型 |
| `codex-rs/protocol/src/config_types.rs` | 配置类型（CollaborationMode, Personality 等） |

### 4.4 核心调用链

```
turn_start.rs (test)
    ↓
McpProcess::send_turn_start_request()
    ↓
JSON-RPC "turn/start" 请求
    ↓
CodexMessageProcessor::process_request()
    ↓
CodexMessageProcessor::turn_start() [line 5928]
    ↓
    ├─ validate_v2_input_limit()           // 输入验证
    ├─ load_thread()                       // 加载线程
    ├─ normalize_turn_start_collaboration_mode()  // 协作模式处理
    ├─ submit_core_op(OverrideTurnContext) // 配置覆盖
    └─ submit_core_op(UserInput)           // 提交输入
        ↓
    CodexThread::submit()
        ↓
    核心处理 + 通知发送
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 |
|-----|------|
| `wiremock` | Mock HTTP 服务器（模拟模型 API） |
| `tempfile::TempDir` | 临时测试目录 |
| `tokio::time::timeout` | 异步测试超时控制 |
| `serde_json` | JSON 序列化/反序列化 |
| `pretty_assertions` | 友好的断言输出 |

### 5.2 内部依赖模块

```rust
// 测试文件中的主要导入
use app_test_support::*;  // 测试辅助库
use codex_app_server_protocol::*;  // v2 协议类型
use codex_core::config::ConfigToml;  // 配置
use codex_core::features::{FEATURES, Feature};  // 功能标志
use codex_protocol::config_types::*;  // 协作模式、人格等
use core_test_support::responses;  // Mock 响应辅助
```

### 5.3 环境依赖

| 环境变量/条件 | 说明 |
|-------------|------|
| `CODEX_HOME` | 指向临时目录（包含 config.toml） |
| `skip_if_no_network!` | 部分测试需要网络，无网络时跳过 |
| `cfg(windows)` | Windows 平台特殊处理（超时、进程 ID） |

### 5.4 Mock 服务器交互

```rust
// Mock 服务器设置示例
let responses = vec![
    create_final_assistant_message_sse_response("Done")?,
];
let server = create_mock_responses_server_sequence_unchecked(responses).await;

// 验证请求
let requests = server.received_requests().await.unwrap();
for request in requests {
    let originator = request.headers.get("originator").expect("originator header missing");
    assert_eq!(originator.to_str()?, TEST_ORIGINATOR);
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 测试稳定性风险

| 风险 | 说明 | 缓解措施 |
|-----|------|---------|
| 网络依赖 | 部分测试需要真实网络连接 | 使用 `skip_if_no_network!` 宏 |
| 超时敏感 | Windows 平台超时更长（25s vs 10s） | 平台条件编译 `#[cfg(windows)]` |
| Mock 服务器竞争 | 多测试并行时端口冲突 | 使用 `responses::start_mock_server()` 自动分配端口 |
| 进程残留 | MCP 进程可能残留 | `kill_on_drop(true)` + `interrupt_turn_and_wait_for_aborted` |

#### 6.1.2 功能边界

```rust
// 输入长度限制边界
const MAX_USER_INPUT_TEXT_CHARS: usize = 100_000;

// 边界测试用例
let first = "x".repeat(MAX_USER_INPUT_TEXT_CHARS / 2);   // 50,000
let second = "y".repeat(MAX_USER_INPUT_TEXT_CHARS / 2 + 1);  // 50,001
// 总计 100,001 > 100,000，应该被拒绝
```

### 6.2 代码复杂度

| 指标 | 值 | 说明 |
|-----|---|------|
| 测试函数数量 | ~20 个 | 覆盖主要场景 |
| 代码行数 | ~2500 行 | 包含大量辅助逻辑 |
| 最大函数行数 | ~200 行 | `turn_start_file_change_approval_v2` |
| 嵌套深度 | 3-4 层 | 异步块 + match + if |

### 6.3 改进建议

#### 6.3.1 测试组织

```rust
// 建议：使用测试模块分组
mod input_validation {
    // turn_start_rejects_combined_oversized_text_input
    // turn_start_accepts_text_at_limit_with_mention_item
}

mod approval_flow {
    // turn_start_exec_approval_toggle_v2
    // turn_start_exec_approval_decline_v2
    // turn_start_file_change_approval_v2
}

mod configuration_override {
    // turn_start_accepts_collaboration_mode_override_v2
    // turn_start_accepts_personality_override_v2
}
```

#### 6.3.2 辅助函数提取

当前大量重复的测试设置代码可以提取：

```rust
// 建议提取的辅助函数
async fn setup_test_thread(
    mcp: &mut McpProcess,
    server_uri: &str,
    model: &str,
) -> Result<Thread> {
    // 统一线程设置逻辑
}

async fn wait_for_turn_completion(
    mcp: &mut McpProcess,
    thread_id: &str,
    turn_id: &str,
) -> Result<()> {
    // 统一等待 turn/completed 逻辑
}
```

#### 6.3.3 错误处理增强

```rust
// 当前：简单的 panic
let server_req = timeout(..., mcp.read_stream_until_request_message()).await??;
let ServerRequest::FileChangeRequestApproval { ... } = server_req else {
    panic!("expected FileChangeRequestApproval request")
};

// 建议：更详细的错误信息
let ServerRequest::FileChangeRequestApproval { ... } = server_req else {
    return Err(anyhow::anyhow!(
        "expected FileChangeRequestApproval, got {:?}", 
        server_req
    ));
};
```

#### 6.3.4 并发测试支持

当前测试串行执行，可以考虑：

```rust
// 使用不同的 CODEX_HOME 目录实现测试隔离
let codex_home = TempDir::new()?;  // 已支持

// 使用不同的 Mock 服务器端口
let server = responses::start_mock_server().await;  // 已支持自动分配
```

### 6.4 技术债务

| 项目 | 说明 | 优先级 |
|-----|------|-------|
| 硬编码超时 | `DEFAULT_READ_TIMEOUT` 是常量 | 低 |
| 测试数据分散 | Mock 响应分散在多个文件 | 中 |
| 重复的模式匹配 | 大量类似的 `loop { match notification }` | 中 |
| 缺少负面测试 | 主要是成功场景，错误场景较少 | 高 |

---

## 7. 附录

### 7.1 测试执行命令

```bash
# 运行所有 turn_start 测试
cargo test -p codex-app-server turn_start

# 运行特定测试
cargo test -p codex-app-server turn_start_rejects_combined_oversized_text_input

# 带输出运行
cargo test -p codex-app-server turn_start -- --nocapture
```

### 7.2 相关文档

- `codex-rs/app-server-protocol/README.md` - v2 API 协议文档
- `codex-rs/app-server/README.md` - App Server 架构文档
- `AGENTS.md` - 开发规范与约定

### 7.3 版本历史

| 日期 | 变更 |
|-----|------|
| 2024-Q4 | 初始实现 |
| 2025-Q1 | 添加协作模式测试 |
| 2025-Q1 | 添加人格覆盖测试 |
| 2025-Q1 | 添加文件变更审批测试 |
