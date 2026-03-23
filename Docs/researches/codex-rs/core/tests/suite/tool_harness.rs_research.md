# tool_harness.rs 研究文档

## 场景与职责

`tool_harness.rs` 是 Codex Core 的集成测试套件，专注于验证核心工具的执行和事件发射机制。该测试确保各种工具（shell、plan、apply_patch）能够正确执行、产生预期的事件流，并将结果正确返回给模型。

### 核心职责
1. **Shell 工具执行验证**：验证 shell 工具执行命令并流式输出结果
2. **Plan 工具事件验证**：验证 `update_plan` 工具产生正确的事件序列
3. **Plan 工具错误处理**：验证 malformed payload 被拒绝
4. **Apply Patch 工具验证**：验证补丁应用和事件发射
5. **Apply Patch 错误报告**：验证解析错误正确报告

## 功能点目的

### 1. Shell 工具执行 (`shell_tool_executes_command_and_streams_output`)
- **目的**：验证 shell 工具正确执行命令并返回输出
- **验证点**：
  - 命令 `/bin/echo tool harness` 被执行
  - 退出码为 0
  - 标准输出匹配预期正则 `r"(?s)^tool harness\n?$"`

### 2. Plan 工具事件 (`update_plan_tool_emits_plan_update_event`)
- **目的**：验证 `update_plan` 工具产生 `PlanUpdate` 事件
- **验证点**：
  - 收到 `PlanUpdate` 事件
  - 解释文本正确（"Tool harness check"）
  - 计划步骤数量和状态正确
  - 工具输出返回 "Plan updated"

### 3. Plan 工具错误处理 (`update_plan_tool_rejects_malformed_payload`)
- **目的**：验证 malformed plan payload 被拒绝且不产生事件
- **验证点**：
  - 未收到 `PlanUpdate` 事件
  - 错误消息包含 "failed to parse function arguments"
  - `success` 标志为 `false`

### 4. Apply Patch 执行 (`apply_patch_tool_executes_and_emits_patch_events`)
- **目的**：验证 `apply_patch` 工具正确应用补丁并发射事件
- **验证点**：
  - 收到 `PatchApplyBegin` 事件
  - 收到 `PatchApplyEnd` 事件且 `success` 为 `true`
  - 文件内容正确更新
  - 输出匹配预期格式

### 5. Apply Patch 错误报告 (`apply_patch_reports_parse_diagnostics`)
- **目的**：验证补丁解析错误正确报告
- **验证点**：
  - 输出包含 "apply_patch verification failed"
  - 输出包含 "invalid hunk"
  - `success` 标志为 `false`

## 具体技术实现

### 测试辅助函数
```rust
fn call_output(req: &ResponsesRequest, call_id: &str) -> (String, Option<bool>) {
    let raw = req.function_call_output(call_id);
    assert_eq!(
        raw.get("call_id").and_then(Value::as_str),
        Some(call_id),
        "mismatched call_id in function_call_output"
    );
    let (content_opt, success) = match req.function_call_output_content_and_success(call_id) {
        Some(values) => values,
        None => panic!("function_call_output present"),
    };
    let content = match content_opt {
        Some(c) => c,
        None => panic!("function_call_output content present"),
    };
    (content, success)
}
```

### Shell 工具测试流程
```rust
let call_id = "shell-tool-call";
let command = vec!["/bin/echo", "tool harness"];

// 1. 挂载第一次响应（包含 local_shell_call）
let first_response = sse(vec![
    ev_response_created("resp-1"),
    ev_local_shell_call(call_id, "completed", command),
    ev_completed("resp-1"),
]);
responses::mount_sse_once(&server, first_response).await;

// 2. 挂载第二次响应（确认完成）
let second_response = sse(vec![
    ev_assistant_message("msg-1", "all done"),
    ev_completed("resp-2"),
]);
let second_mock = responses::mount_sse_once(&server, second_response).await;

// 3. 提交用户回合
codex.submit(Op::UserTurn { ... }).await?;
wait_for_event(&codex, |event| matches!(event, EventMsg::TurnComplete(_))).await;

// 4. 验证输出
let req = second_mock.single_request();
let (output_text, _) = call_output(&req, call_id);
let exec_output: Value = serde_json::from_str(&output_text)?;
assert_eq!(exec_output["metadata"]["exit_code"], 0);
```

### Plan 工具测试流程
```rust
let call_id = "plan-tool-call";
let plan_args = json!({
    "explanation": "Tool harness check",
    "plan": [
        {"step": "Inspect workspace", "status": "in_progress"},
        {"step": "Report results", "status": "pending"},
    ],
});

// 挂载响应并提交
// ...

// 验证 PlanUpdate 事件
let mut saw_plan_update = false;
wait_for_event(&codex, |event| match event {
    EventMsg::PlanUpdate(update) => {
        saw_plan_update = true;
        assert_eq!(update.explanation.as_deref(), Some("Tool harness check"));
        assert_eq!(update.plan.len(), 2);
        assert_matches!(update.plan[0].status, StepStatus::InProgress);
        false // 继续等待 TurnComplete
    }
    EventMsg::TurnComplete(_) => true, // 停止等待
    _ => false,
}).await;
```

### Apply Patch 测试流程
```rust
// 启用 ApplyPatchFreeform 功能
let mut builder = test_codex().with_config(|config| {
    config.features.enable(Feature::ApplyPatchFreeform).expect(...);
});

let patch_content = format!(r#"*** Begin Patch
*** Add File: {file_name}
+Tool harness apply patch
*** End Patch"#);

// 挂载响应（包含 apply_patch 调用）
let first_response = sse(vec![
    ev_response_created("resp-1"),
    ev_apply_patch_function_call(call_id, &patch_content),
    ev_completed("resp-1"),
]);

// 提交并验证事件
let mut saw_patch_begin = false;
let mut patch_end_success = None;
wait_for_event(&codex, |event| match event {
    EventMsg::PatchApplyBegin(begin) => {
        saw_patch_begin = true;
        assert_eq!(begin.call_id, call_id);
        false
    }
    EventMsg::PatchApplyEnd(end) => {
        patch_end_success = Some(end.success);
        false
    }
    EventMsg::TurnComplete(_) => true,
    _ => false,
}).await;
```

## 关键代码路径与文件引用

### 被测代码路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/tools/handlers/shell.rs` | Shell 工具实现 |
| `codex-rs/core/src/tools/handlers/plan.rs` | Plan 工具实现 |
| `codex-rs/core/src/tools/handlers/apply_patch.rs` | Apply Patch 工具实现 |
| `codex-rs/core/src/features.rs` | `Feature::ApplyPatchFreeform` 功能标志 |
| `codex-rs/protocol/src/plan_tool.rs` | `StepStatus` 枚举定义 |

### 测试依赖路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/common/responses.rs` | SSE 事件构造器 |
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodex` 测试辅助 |
| `codex-rs/core/tests/common/lib.rs` | `wait_for_event` 和 `assert_regex_match` |

### 关键类型引用
```rust
// codex_protocol::plan_tool
pub enum StepStatus {
    Pending,
    InProgress,
    Completed,
    Failed,
}

pub struct PlanUpdateEvent {
    pub explanation: Option<String>,
    pub plan: Vec<PlanStep>,
}

pub struct PlanStep {
    pub step: String,
    pub status: StepStatus,
}

// codex_protocol::protocol
pub enum EventMsg {
    PlanUpdate(PlanUpdateEvent),
    PatchApplyBegin(PatchApplyBeginEvent),
    PatchApplyEnd(PatchApplyEndEvent),
    TurnComplete(TurnCompleteEvent),
    ...
}

pub struct PatchApplyBeginEvent {
    pub call_id: String,
}

pub struct PatchApplyEndEvent {
    pub call_id: String,
    pub success: bool,
}
```

## 依赖与外部交互

### 外部依赖
1. **wiremock**: HTTP Mock 服务器
2. **tokio**: 异步运行时
3. **serde_json**: JSON 处理
4. **assert_matches**: 模式匹配断言
5. **regex_lite**: 正则表达式匹配

### 内部依赖
1. **codex_core**: 核心库，提供工具实现
2. **codex_protocol**: 协议定义
3. **core_test_support**: 测试支持库

### 环境要求
- 网络访问（通过 `skip_if_no_network!` 宏在沙箱中跳过）
- 非 Windows 平台（`#![cfg(not(target_os = "windows"))]`）

## 风险、边界与改进建议

### 已知风险
1. **平台限制**：测试排除 Windows 平台，可能遗漏 Windows 特定问题
2. **Shell 依赖**：测试依赖 `/bin/echo`，在某些环境可能不可用
3. **正则脆弱性**：输出格式验证依赖正则表达式，格式变更可能导致测试失败

### 边界情况
1. **空输出**：未测试命令产生空输出的场景
2. **大输出**：未测试输出超过缓冲区限制的场景
3. **并发工具调用**：未测试同一回合多个工具调用的场景

### 改进建议
1. **跨平台支持**：使用 `std::process::Command` 替代硬编码 shell 路径
2. **参数化测试**：使用参数化测试覆盖不同命令和参数组合
3. **性能测试**：添加大文件补丁应用的性能基准
4. **并发测试**：添加同一回合多个工具调用的测试
5. **错误码覆盖**：添加更多退出码（非零）的测试场景

### 潜在缺陷
1. **硬编码路径**：`/bin/echo` 在某些系统可能不存在
2. **无超时测试**：未测试工具执行超时的场景
3. **无取消测试**：未测试工具执行被取消的场景
4. **有限的事件验证**：仅验证事件存在，未验证所有字段

### 相关测试
- `tools.rs`: 更全面的工具测试，包括权限和沙箱
- `apply_patch_cli.rs`: CLI 级别的补丁应用测试
- `shell_command.rs`: Shell 命令的专门测试
