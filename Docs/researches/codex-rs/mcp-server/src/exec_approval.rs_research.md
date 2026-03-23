# exec_approval.rs 研究文档

## 场景与职责

`exec_approval.rs` 处理 Codex MCP 服务器中的命令执行审批流程。当 Codex 需要执行可能不安全的 shell 命令时（如 `rm -rf /`），该模块负责将审批请求转发给 MCP 客户端，等待用户决策，并将结果返回给 Codex 核心。

**核心职责：**
1. 构造执行审批请求（Elicitation），包含命令详情和上下文
2. 通过 MCP `elicitation/create` 请求向客户端请求审批
3. 异步等待客户端响应
4. 将用户决策（批准/拒绝）提交回 Codex 核心

## 功能点目的

### 1. 执行审批请求参数

```rust
pub struct ExecApprovalElicitRequestParams {
    pub message: String,                      // 显示给用户的消息
    pub requested_schema: Value,              // 请求的响应 schema
    pub thread_id: ThreadId,                  // Codex 线程 ID
    pub codex_elicitation: String,            // "exec-approval"
    pub codex_mcp_tool_call_id: String,       // MCP 工具调用 ID
    pub codex_event_id: String,               // Codex 事件 ID
    pub codex_call_id: String,                // Codex 调用 ID
    pub codex_command: Vec<String>,           // 待执行的命令
    pub codex_cwd: PathBuf,                   // 工作目录
    pub codex_parsed_cmd: Vec<ParsedCommand>, // 解析后的命令结构
}
```

### 2. 执行审批响应

```rust
pub struct ExecApprovalResponse {
    pub decision: ReviewDecision,  // Approved 或 Denied
}
```

### 3. 审批处理流程

**阶段 1：构造请求**
- 使用 `shlex::try_join` 转义命令参数
- 构造用户友好的提示消息："Allow Codex to run `{command}` in `{cwd}`?"

**阶段 2：发送 Elicitation**
- 通过 `outgoing.send_request("elicitation/create", ...)` 发送请求
- 获取 oneshot receiver 等待响应

**阶段 3：异步等待响应**
- 在独立任务中等待 `receiver.await`
- 不阻塞主事件循环

**阶段 4：提交决策**
- 解析响应为 `ExecApprovalResponse`
- 通过 `codex.submit(Op::ExecApproval { ... })` 提交决策

## 具体技术实现

### 主处理函数

```rust
#[allow(clippy::too_many_arguments)]
pub(crate) async fn handle_exec_approval_request(
    command: Vec<String>,
    cwd: PathBuf,
    outgoing: Arc<OutgoingMessageSender>,
    codex: Arc<CodexThread>,
    request_id: RequestId,        // MCP 请求 ID
    tool_call_id: String,         // 工具调用 ID
    event_id: String,             // Codex 事件 ID
    call_id: String,              // Codex 调用 ID
    approval_id: String,          // 审批 ID
    codex_parsed_cmd: Vec<ParsedCommand>,
    thread_id: ThreadId,
)
```

### 消息构造

```rust
let escaped_command =
    shlex::try_join(command.iter().map(String::as_str))
        .unwrap_or_else(|_| command.join(" "));
let message = format!(
    "Allow Codex to run `{escaped_command}` in `{cwd}`?",
    cwd = cwd.to_string_lossy()
);

let params = ExecApprovalElicitRequestParams {
    message,
    requested_schema: json!({"type":"object","properties":{}}),
    thread_id,
    codex_elicitation: "exec-approval".to_string(),
    codex_mcp_tool_call_id: tool_call_id.clone(),
    codex_event_id: event_id.clone(),
    codex_call_id: call_id,
    codex_command: command,
    codex_cwd: cwd,
    codex_parsed_cmd,
};
```

### 响应处理

```rust
async fn on_exec_approval_response(
    approval_id: String,
    event_id: String,
    receiver: tokio::sync::oneshot::Receiver<serde_json::Value>,
    codex: Arc<CodexThread>,
) {
    let response = receiver.await;
    let value = match response {
        Ok(value) => value,
        Err(err) => {
            error!("request failed: {err:?}");
            return;  // 接收失败，不提交决策（Codex 会超时）
        }
    };

    // 反序列化响应，失败时保守地拒绝
    let response = serde_json::from_value::<ExecApprovalResponse>(value)
        .unwrap_or_else(|err| {
            error!("failed to deserialize ExecApprovalResponse: {err}");
            ExecApprovalResponse {
                decision: ReviewDecision::Denied,
            }
        });

    // 提交决策
    if let Err(err) = codex
        .submit(Op::ExecApproval {
            id: approval_id,
            turn_id: Some(event_id),
            decision: response.decision,
        })
        .await
    {
        error!("failed to submit ExecApproval: {err}");
    }
}
```

## 关键代码路径与文件引用

### 内部依赖

| 依赖 | 路径 | 用途 |
|------|------|------|
| `CodexThread` | `codex_core` | 提交审批决策 |
| `ThreadId` | `codex_protocol` | 线程标识 |
| `ParsedCommand` | `codex_protocol::parse_command` | 解析后的命令结构 |
| `Op` | `codex_protocol::protocol` | 操作类型（ExecApproval） |
| `ReviewDecision` | `codex_protocol::protocol` | 审批决策枚举 |
| `OutgoingMessageSender` | `crate::outgoing_message` | 发送 elicitation 请求 |
| `ErrorData` | `rmcp::model` | MCP 错误数据 |
| `RequestId` | `rmcp::model` | MCP 请求 ID |

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `shlex` | 命令参数转义 |
| `serde::{Deserialize, Serialize}` | 序列化/反序列化 |
| `serde_json::Value` | JSON 值处理 |
| `tracing::error` | 错误日志 |

### 调用关系

```
codex_tool_runner.rs::run_codex_tool_session_inner()
    └─> EventMsg::ExecApprovalRequest(ev)
        └─> exec_approval::handle_exec_approval_request()
            ├─> outgoing.send_request("elicitation/create", ...)
            └─> tokio::spawn(async move {
                    on_exec_approval_response(...)
                    ├─> receiver.await
                    └─> codex.submit(Op::ExecApproval { ... })
                })
```

## 依赖与外部交互

### MCP Elicitation 协议

**发送请求：**
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "elicitation/create",
    "params": {
        "message": "Allow Codex to run `touch file.txt` in `/home/user`?",
        "requestedSchema": {"type": "object", "properties": {}},
        "threadId": "...",
        "codex_elicitation": "exec-approval",
        "codex_mcp_tool_call_id": "...",
        "codex_event_id": "...",
        "codex_call_id": "...",
        "codex_command": ["touch", "file.txt"],
        "codex_cwd": "/home/user",
        "codex_parsed_cmd": [...]
    }
}
```

**接收响应：**
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "decision": "approved"
    }
}
```

### 与 Codex 核心交互

**提交审批决策：**
```rust
codex.submit(Op::ExecApproval {
    id: approval_id,           // 关联原始请求
    turn_id: Some(event_id),   // 关联事件
    decision: response.decision,  // Approved 或 Denied
})
```

## 风险、边界与改进建议

### 已知风险

1. **响应格式不匹配**：代码注释指出 `ExecApprovalResponse` 不符合 MCP Elicitation 响应规范
   ```rust
   // TODO(mbolin): ExecApprovalResponse does not conform to ElicitResult.
   // It should have "action" and "content" fields.
   ```
   当前实现使用 `decision` 字段，但规范要求 `action` 和 `content`。

2. **序列化失败处理**：如果 `ExecApprovalElicitRequestParams` 序列化失败，发送错误响应但不中断会话
   ```rust
   let params_json = match serde_json::to_value(&params) {
       Ok(value) => value,
       Err(err) => {
           outgoing.send_error(...).await;
           return;
       }
   };
   ```

3. **响应接收失败**：如果 oneshot channel 关闭（客户端断开），静默返回，Codex 核心将等待超时

### 边界情况

| 场景 | 行为 |
|------|------|
| 命令包含特殊字符 | `shlex::try_join` 处理，失败时回退到简单拼接 |
| 响应反序列化失败 | 保守拒绝（`ReviewDecision::Denied`） |
| 提交决策失败 | 记录错误日志，不重试 |
| 工作目录包含非 UTF-8 字符 | `to_string_lossy` 处理，替换无效字符 |

### 改进建议

1. **规范合规**：更新 `ExecApprovalResponse` 以符合 MCP Elicitation 规范
   ```rust
   pub struct ExecApprovalResponse {
       pub action: String,   // "accept" 或 "reject"
       pub content: Value,   // 额外内容
   }
   ```

2. **超时处理**：添加 elicitation 超时机制，避免无限期等待

3. **重试机制**：在提交决策失败时实施有限重试

4. **取消支持**：支持客户端发送取消通知，中断等待中的审批

5. **丰富上下文**：在请求中包含更多安全上下文（如命令风险等级、历史执行记录）

6. **批量审批**：支持一次 elicitation 审批多个相关命令

### 测试覆盖

集成测试在 `tests/suite/codex_tool.rs` 中：
- `test_shell_command_approval_triggers_elicitation`：验证完整执行审批流程

测试要点：
1. 验证 elicitation 请求格式
2. 验证响应后命令执行
3. 验证文件副作用（创建测试文件）
