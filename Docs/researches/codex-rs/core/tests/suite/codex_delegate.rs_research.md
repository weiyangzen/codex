# codex_delegate.rs 研究文档

## 文件基本信息

- **文件路径**: `codex-rs/core/tests/suite/codex_delegate.rs`
- **文件大小**: ~8.8KB (245 行)
- **所属模块**: `codex-core` 集成测试套件
- **测试类型**: 端到端集成测试
- **当前状态**: 部分测试被标记为 `#[ignore]`，等待 delegate 功能完善

## 场景与职责

### 核心职责

`codex_delegate.rs` 是 Codex 项目中 **Delegate (委托/子代理)** 功能的集成测试文件。Delegate 是一种特殊的子代理机制，允许父代理将特定任务委托给子代理执行，同时保持对关键操作（如执行命令、应用补丁）的审批控制。

### 测试场景覆盖

1. **执行审批转发**: 验证子代理的执行审批请求能够正确转发给父代理
2. **补丁审批转发**: 验证子代理的补丁应用审批请求能够正确转发
3. **旧版事件兼容**: 验证 delegate 能够正确处理旧版 reasoning delta 事件

### Delegate 架构角色

```
┌─────────────────────────────────────────────────────────────────┐
│                     Delegate 架构                               │
├─────────────────────────────────────────────────────────────────┤
│  Parent Agent   │  接收用户输入，管理整体会话                    │
│                 │  处理子代理转发的审批请求                      │
├─────────────────────────────────────────────────────────────────┤
│  Delegate Layer │  子代理执行具体任务                            │
│                 │  遇到需要审批的操作时转发给父代理              │
├─────────────────────────────────────────────────────────────────┤
│  Review Mode    │  审批模式，处理 ExecApprovalRequest            │
│                 │  和 ApplyPatchApprovalRequest                  │
└─────────────────────────────────────────────────────────────────┘
```

### 与其他测试的关系

| 测试文件 | 关系 |
|---------|------|
| `code_mode.rs` | Code Mode 也涉及子代理概念，但 Delegate 更关注审批转发 |
| `review.rs` | Review 模式测试，Delegate 测试继承并扩展了审批流程 |
| `approvals.rs` | 基础审批测试，Delegate 在此基础上添加子代理场景 |
| `hierarchical_agents.rs` | 层级代理测试，Delegate 是层级代理的一种特殊形式 |

## 功能点目的

### 1. 执行审批转发测试

**测试函数**: `codex_delegate_forwards_exec_approval_and_proceeds_on_approval`

**状态**: `#[ignore = "TODO once we have a delegate that can ask for approvals"]`

**目的**:
- 验证子代理在执行需要审批的命令时，能够将 `ExecApprovalRequest` 转发给父代理
- 验证父代理批准后，子代理能够继续执行
- 测试完整的生命周期：EnteredReviewMode → ExecApprovalRequest → ExitedReviewMode → TurnComplete

**测试流程**:
```rust
// 1. 子代理第一轮：发出 shell_command 函数调用（需要审批）
let sse1 = sse(vec![
    ev_response_created("resp-1"),
    ev_function_call(call_id, "shell_command", &args),
    ev_completed("resp-1"),
]);

// 2. 子代理第二轮：返回审查结果
let sse2 = sse(vec![
    ev_response_created("resp-2"),
    ev_assistant_message("msg-1", &review_json),
    ev_completed("resp-2"),
]);

// 3. 父代理配置为需要审批
config.permissions.approval_policy = Constrained::allow_any(AskForApproval::OnRequest);

// 4. 提交 Review 操作启动子代理
test.codex.submit(Op::Review { ... }).await;

// 5. 等待并处理审批事件
wait_for_event(|ev| matches!(ev, EventMsg::ExecApprovalRequest(_))).await;

// 6. 父代理提交审批决定
test.codex.submit(Op::ExecApproval { ... }).await;
```

### 2. 补丁审批转发测试

**测试函数**: `codex_delegate_forwards_patch_approval_and_proceeds_on_decision`

**状态**: `#[ignore = "TODO once we have a delegate that can ask for approvals"]`

**目的**:
- 验证子代理在应用补丁时，能够将 `ApplyPatchApprovalRequest` 转发给父代理
- 验证父代理拒绝后，子代理能够正确处理并继续

**关键区别**:
- 使用 `Op::PatchApproval` 而非 `Op::ExecApproval`
- 测试拒绝场景（`ReviewDecision::Denied`）

### 3. 旧版事件兼容测试

**测试函数**: `codex_delegate_ignores_legacy_deltas`

**状态**: **已启用** (非 ignore)

**目的**:
- 验证 delegate 能够同时处理新版 `ReasoningContentDelta` 和旧版 `AgentReasoningDelta`
- 确保向后兼容性

**测试逻辑**:
```rust
// 统计两种 delta 事件的数量
let mut reasoning_delta_count = 0;
let mut legacy_reasoning_delta_count = 0;

loop {
    let ev = wait_for_event(&test.codex, |_| true).await;
    match ev {
        EventMsg::ReasoningContentDelta(_) => reasoning_delta_count += 1,
        EventMsg::AgentReasoningDelta(_) => legacy_reasoning_delta_count += 1,
        EventMsg::TurnComplete(_) => break,
        _ => {}
    }
}

// 验证各收到一种
assert_eq!(reasoning_delta_count, 1);
assert_eq!(legacy_reasoning_delta_count, 1);
```

## 具体技术实现

### 关键流程

#### 1. 审批转发流程

```rust
// 完整的审批转发测试流程
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn codex_delegate_forwards_exec_approval_and_proceeds_on_approval() {
    skip_if_no_network!();

    // 1. 准备子代理的两轮 SSE 响应
    // 第一轮：发出需要审批的 shell_command
    let call_id = "call-exec-1";
    let args = serde_json::json!({
        "command": "rm -rf delegated",
        "timeout_ms": 1000,
        "sandbox_permissions": SandboxPermissions::RequireEscalated,
    }).to_string();
    let sse1 = sse(vec![
        ev_response_created("resp-1"),
        ev_function_call(call_id, "shell_command", &args),
        ev_completed("resp-1"),
    ]);

    // 第二轮：返回审查结果
    let review_json = serde_json::json!({
        "findings": [],
        "overall_correctness": "ok",
        "overall_explanation": "delegate approved exec",
        "overall_confidence_score": 0.5
    }).to_string();
    let sse2 = sse(vec![
        ev_response_created("resp-2"),
        ev_assistant_message("msg-1", &review_json),
        ev_completed("resp-2"),
    ]);

    // 2. 启动 Mock 服务器
    let server = start_mock_server().await;
    mount_sse_sequence(&server, vec![sse1, sse2]).await;

    // 3. 构建需要审批的测试配置
    let mut builder = test_codex()
        .with_model("gpt-5.1")
        .with_config(|config| {
            config.permissions.approval_policy = 
                Constrained::allow_any(AskForApproval::OnRequest);
            config.permissions.sandbox_policy = 
                Constrained::allow_any(SandboxPolicy::new_read_only_policy());
        });
    let test = builder.build(&server).await.expect("build test codex");

    // 4. 启动 Review（触发子代理）
    test.codex.submit(Op::Review {
        review_request: ReviewRequest {
            target: ReviewTarget::Custom {
                instructions: "Please review".to_string(),
            },
            user_facing_hint: None,
        },
    }).await.expect("submit review");

    // 5. 验证生命周期事件
    wait_for_event(|ev| matches!(ev, EventMsg::EnteredReviewMode(_))).await;
    
    // 6. 获取并验证审批请求
    let approval_event = wait_for_event(|ev| {
        matches!(ev, EventMsg::ExecApprovalRequest(_))
    }).await;
    let EventMsg::ExecApprovalRequest(approval) = approval_event else {
        panic!("expected ExecApprovalRequest event");
    };

    // 7. 父代理提交审批决定
    test.codex.submit(Op::ExecApproval {
        id: approval.effective_approval_id(),
        turn_id: None,
        decision: ReviewDecision::Approved,
    }).await.expect("submit exec approval");

    // 8. 验证完成
    wait_for_event(|ev| matches!(ev, EventMsg::ExitedReviewMode(_))).await;
    wait_for_event(|ev| matches!(ev, EventMsg::TurnComplete(_))).await;
}
```

### 关键数据结构

#### 1. 审批相关类型

```rust
// 来自 codex_protocol::protocol
pub enum Op {
    Review { review_request: ReviewRequest },
    ExecApproval { id: String, turn_id: Option<String>, decision: ReviewDecision },
    PatchApproval { id: String, decision: ReviewDecision },
}

pub enum EventMsg {
    EnteredReviewMode(EnteredReviewModeEvent),
    ExecApprovalRequest(ExecApprovalRequestEvent),
    ApplyPatchApprovalRequest(ApplyPatchApprovalRequestEvent),
    ExitedReviewMode(ExitedReviewModeEvent),
    TurnComplete(TurnCompleteEvent),
    ReasoningContentDelta(ReasoningContentDeltaEvent),
    AgentReasoningDelta(AgentReasoningDeltaEvent),  // 旧版
}

pub enum ReviewDecision {
    Approved,
    Denied,
}

pub struct ReviewRequest {
    pub target: ReviewTarget,
    pub user_facing_hint: Option<String>,
}

pub enum ReviewTarget {
    Custom { instructions: String },
    // ... 其他变体
}
```

#### 2. 沙盒权限

```rust
// 来自 codex_core::sandboxing
pub enum SandboxPermissions {
    UseDefault,
    RequireEscalated,  // 需要审批的提升权限
    // ...
}
```

#### 3. 配置约束

```rust
// 来自 codex_core::config
pub struct Constrained<T> {
    value: T,
    allowed_values: Vec<T>,
}

impl<T> Constrained<T> {
    pub fn allow_any(value: T) -> Self {
        Self { value, allowed_values: vec![] }
    }
}
```

### 协议与命令

#### 1. SSE 事件构造

```rust
// 函数调用事件
pub fn ev_function_call(call_id: &str, name: &str, arguments: &str) -> Value {
    serde_json::json!({
        "type": "response.output_item.done",
        "item": {
            "type": "function_call",
            "call_id": call_id,
            "name": name,
            "arguments": arguments
        }
    })
}

// 应用补丁函数调用
pub fn ev_apply_patch_function_call(call_id: &str, patch: &str) -> Value {
    let arguments = serde_json::json!({ "input": patch });
    let arguments = serde_json::to_string(&arguments)
        .expect("serialize apply_patch arguments");
    
    serde_json::json!({
        "type": "response.output_item.done",
        "item": {
            "type": "function_call",
            "name": "apply_patch",
            "arguments": arguments,
            "call_id": call_id
        }
    })
}

// Reasoning 项添加
pub fn ev_reasoning_item_added(id: &str, summary: &[&str]) -> Value {
    let summary_entries: Vec<Value> = summary
        .iter()
        .map(|text| serde_json::json!({"type": "summary_text", "text": text}))
        .collect();
    
    serde_json::json!({
        "type": "response.output_item.added",
        "item": {
            "type": "reasoning",
            "id": id,
            "summary": summary_entries,
        }
    })
}

// Reasoning delta
pub fn ev_reasoning_summary_text_delta(delta: &str) -> Value {
    serde_json::json!({
        "type": "response.reasoning_summary_text.delta",
        "delta": delta,
        "summary_index": 0,
    })
}
```

#### 2. 序列化 SSE 序列

```rust
// 顺序挂载多个 SSE 响应
pub async fn mount_sse_sequence(
    server: &MockServer,
    sequences: Vec<String>,
) -> ResponseMock {
    // 依次响应每个序列
    for (i, body) in sequences.into_iter().enumerate() {
        mount_sse_once_match(
            server,
            move |req: &wiremock::Request| {
                // 根据请求次数匹配
            },
            body,
        ).await;
    }
}
```

## 关键代码路径与文件引用

### 被测试的核心代码

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/codex.rs` | Codex 主逻辑，处理 Op::Review 和审批操作 |
| `codex-rs/core/src/review/` | Review 模式实现 |
| `codex-rs/core/src/approvals/` | 审批流程处理 |
| `codex-rs/core/src/delegate/` | Delegate 子代理实现（待完善） |
| `codex-rs/core/src/sandboxing.rs` | 沙盒权限管理 |

### 测试依赖

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/common/lib.rs` | 测试公共库入口 |
| `codex-rs/core/tests/common/responses.rs` | Mock SSE 响应服务器 |
| `codex-rs/core/tests/common/test_codex.rs` | TestCodex 测试辅助结构 |

### 关键类型引用

```rust
// 配置相关
codex_core::config::Constrained<T>
codex_core::sandboxing::SandboxPermissions

// 协议相关
codex_protocol::protocol::AskForApproval
codex_protocol::protocol::EventMsg
codex_protocol::protocol::Op
codex_protocol::protocol::ReviewDecision
codex_protocol::protocol::ReviewRequest
codex_protocol::protocol::ReviewTarget

// 测试辅助
core_test_support::responses::ev_apply_patch_function_call
core_test_support::responses::ev_assistant_message
core_test_support::responses::ev_completed
core_test_support::responses::ev_function_call
core_test_support::responses::ev_reasoning_item_added
core_test_support::responses::ev_reasoning_summary_text_delta
core_test_support::responses::ev_response_created
core_test_support::responses::mount_sse_sequence
core_test_support::responses::sse
core_test_support::responses::start_mock_server
core_test_support::skip_if_no_network
core_test_support::test_codex::test_codex
core_test_support::wait_for_event
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `wiremock` | HTTP Mock 服务器 |
| `tokio` | 异步运行时 |
| `serde_json` | JSON 序列化/反序列化 |
| `pretty_assertions` | 更好的测试断言输出 |

### 内部模块依赖

```
codex_delegate.rs
├── core_test_support (测试公共库)
│   ├── responses (Mock SSE 服务器)
│   ├── test_codex (测试辅助)
│   └── wait_for_event (事件等待)
├── codex_core (核心库)
│   ├── config (配置)
│   ├── sandboxing (沙盒权限)
│   └── review/approvals (审批流程)
└── codex_protocol (协议定义)
    └── protocol (事件/操作)
```

### 网络依赖

测试使用 `skip_if_no_network!` 宏检查网络可用性：

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn codex_delegate_ignores_legacy_deltas() {
    skip_if_no_network!();  // 无网络时跳过
    ...
}
```

## 风险、边界与改进建议

### 当前风险

1. **功能未完成**
   - 两个主要测试被标记为 `#[ignore]`，等待 delegate 功能完善
   - 测试代码已写好但无法验证实际功能

2. **测试覆盖不足**
   - 只有 3 个测试函数，其中 2 个被忽略
   - 缺少边界情况测试（如网络中断、超时等）

3. **审批流程复杂性**
   - 涉及多个事件类型和状态转换
   - 容易出错，需要更完善的测试覆盖

### 边界情况

1. **审批超时**
   - 父代理长时间不响应审批请求
   - 子代理应该如何处理

2. **多次审批**
   - 单个子代理会话中多次需要审批
   - 审批状态管理

3. **父代理终止**
   - 审批过程中父代理被终止
   - 子代理的清理和恢复

4. **并发审批**
   - 多个子代理同时请求审批
   - 审批队列管理

### 改进建议

1. **启用被忽略的测试**
   ```rust
   // 当前状态
   #[ignore = "TODO once we have a delegate that can ask for approvals"]
   
   // 建议：创建 tracking issue 并关联 TODO
   #[ignore = "TODO(#1234): enable once delegate approvals are implemented"]
   ```

2. **增加测试覆盖**
   ```rust
   // 建议添加的测试
   async fn codex_delegate_handles_approval_timeout() { }
   async fn codex_delegate_handles_parent_termination() { }
   async fn codex_delegate_handles_multiple_approvals() { }
   async fn codex_delegate_forwards_cancelled_approval() { }
   ```

3. **测试文档化**
   ```rust
   /// Test: Delegate forwards exec approval and proceeds on approval
   /// 
   /// Scenario:
   /// 1. Parent agent starts a review (spawns delegate)
   /// 2. Delegate encounters a shell command requiring approval
   /// 3. Delegate forwards ExecApprovalRequest to parent
   /// 4. Parent approves
   /// 5. Delegate continues and completes
   /// 
   /// Expected Events:
   /// - EnteredReviewMode
   /// - ExecApprovalRequest
   /// - ExitedReviewMode
   /// - TurnComplete
   ```

4. **提取公共测试模式**
   ```rust
   // 建议：提取审批测试的公共模式
   async fn run_approval_test(
       approval_type: ApprovalType,
       decision: ReviewDecision,
   ) -> Result<Vec<EventMsg>> { ... }
   ```

5. **与 Code Mode 集成测试**
   - Code Mode 也涉及子代理概念
   - 建议添加 Code Mode + Delegate 的集成测试

### 相关 TODO 跟踪

| TODO | 优先级 | 状态 |
|-----|-------|------|
| 实现 delegate 的审批请求功能 | 高 | 待开发 |
| 启用 `codex_delegate_forwards_exec_approval_and_proceeds_on_approval` | 高 | 等待功能 |
| 启用 `codex_delegate_forwards_patch_approval_and_proceeds_on_decision` | 高 | 等待功能 |
| 添加更多边界测试 | 中 | 待规划 |

### 与相关功能的对比

| 功能 | 与 Delegate 的关系 |
|-----|-------------------|
| Code Mode | 都涉及子代理，但 Code Mode 关注代码执行，Delegate 关注审批转发 |
| Review Mode | Delegate 使用 Review Mode 作为基础，添加子代理能力 |
| Hierarchical Agents | Delegate 是层级代理的一种特殊形式，更专注于审批场景 |
| Approvals | Delegate 扩展了审批系统，支持跨代理审批 |
