# patch_approval.rs 研究文档

## 场景与职责

`patch_approval.rs` 处理 Codex MCP 服务器中的代码补丁应用审批流程。当 Codex 需要修改文件系统（如应用代码补丁）时，该模块负责将审批请求转发给 MCP 客户端，等待用户决策，并将结果返回给 Codex 核心。

**核心职责：**
1. 构造补丁审批请求（Elicitation），包含变更详情
2. 通过 MCP `elicitation/create` 请求向客户端请求审批
3. 异步等待客户端响应
4. 将用户决策（批准/拒绝）提交回 Codex 核心

## 功能点目的

### 1. 补丁审批请求参数

```rust
#[derive(Debug, Deserialize, Serialize)]
pub struct PatchApprovalElicitRequestParams {
    pub message: String,                      // 显示给用户的消息
    #[serde(rename = "requestedSchema")]
    pub requested_schema: Value,              // 请求的响应 schema
    #[serde(rename = "threadId")]
    pub thread_id: ThreadId,                  // Codex 线程 ID
    pub codex_elicitation: String,            // "patch-approval"
    pub codex_mcp_tool_call_id: String,       // MCP 工具调用 ID
    pub codex_event_id: String,               // Codex 事件 ID
    pub codex_call_id: String,                // Codex 调用 ID
    #[serde(skip_serializing_if = "Option::is_none")]
    pub codex_reason: Option<String>,         // 变更原因
    #[serde(skip_serializing_if = "Option::is_none")]
    pub codex_grant_root: Option<PathBuf>,    // 根目录授权
    pub codex_changes: HashMap<PathBuf, FileChange>,  // 文件变更映射
}
```

### 2. 补丁审批响应

```rust
#[derive(Debug, Deserialize, Serialize)]
pub struct PatchApprovalResponse {
    pub decision: ReviewDecision,  // Approved 或 Denied
}
```

### 3. 审批处理流程

**阶段 1：构造请求**
- 构建用户友好的提示消息
- 包含变更原因（如果有）
- 打包所有文件变更信息

**阶段 2：发送 Elicitation**
- 通过 `outgoing.send_request("elicitation/create", ...)` 发送请求
- 获取 oneshot receiver 等待响应

**阶段 3：异步等待响应**
- 在独立任务中等待 `receiver.await`
- 不阻塞主事件循环

**阶段 4：提交决策**
- 解析响应为 `PatchApprovalResponse`
- 通过 `codex.submit(Op::PatchApproval { ... })` 提交决策
- 如果接收失败或解析失败，保守地拒绝

## 具体技术实现

### 主处理函数

```rust
#[allow(clippy::too_many_arguments)]
pub(crate) async fn handle_patch_approval_request(
    call_id: String,
    reason: Option<String>,
    grant_root: Option<PathBuf>,
    changes: HashMap<PathBuf, FileChange>,
    outgoing: Arc<OutgoingMessageSender>,
    codex: Arc<CodexThread>,
    request_id: RequestId,        // MCP 请求 ID
    tool_call_id: String,         // 工具调用 ID
    event_id: String,             // Codex 事件 ID
    thread_id: ThreadId,
)
```

### 消息构造

```rust
let approval_id = call_id.clone();

// 构建消息行
let mut message_lines = Vec::new();
if let Some(r) = &reason {
    message_lines.push(r.clone());
}
message_lines.push("Allow Codex to apply proposed code changes?".to_string());

let params = PatchApprovalElicitRequestParams {
    message: message_lines.join("\n"),
    requested_schema: json!({"type":"object","properties":{}}),
    thread_id,
    codex_elicitation: "patch-approval".to_string(),
    codex_mcp_tool_call_id: tool_call_id.clone(),
    codex_event_id: event_id.clone(),
    codex_call_id: call_id,
    codex_reason: reason,
    codex_grant_root: grant_root,
    codex_changes: changes,
};
```

### 响应处理

```rust
pub(crate) async fn on_patch_approval_response(
    approval_id: String,
    receiver: tokio::sync::oneshot::Receiver<serde_json::Value>,
    codex: Arc<CodexThread>,
) {
    let response = receiver.await;
    let value = match response {
        Ok(value) => value,
        Err(err) => {
            error!("request failed: {err:?}");
            // 接收失败，保守拒绝
            if let Err(submit_err) = codex
                .submit(Op::PatchApproval {
                    id: approval_id.clone(),
                    decision: ReviewDecision::Denied,
                })
                .await
            {
                error!("failed to submit denied PatchApproval: {submit_err}");
            }
            return;
        }
    };

    // 反序列化响应，失败时保守拒绝
    let response = serde_json::from_value::<PatchApprovalResponse>(value)
        .unwrap_or_else(|err| {
            error!("failed to deserialize PatchApprovalResponse: {err}");
            PatchApprovalResponse {
                decision: ReviewDecision::Denied,
            }
        });

    // 提交决策
    if let Err(err) = codex
        .submit(Op::PatchApproval {
            id: approval_id,
            decision: response.decision,
        })
        .await
    {
        error!("failed to submit PatchApproval: {err}");
    }
}
```

## 关键代码路径与文件引用

### 内部依赖

| 依赖 | 路径 | 用途 |
|------|------|------|
| `CodexThread` | `codex_core` | 提交审批决策 |
| `ThreadId` | `codex_protocol` | 线程标识 |
| `FileChange` | `codex_protocol::protocol` | 文件变更类型 |
| `Op` | `codex_protocol::protocol` | 操作类型（PatchApproval） |
| `ReviewDecision` | `codex_protocol::protocol` | 审批决策枚举 |
| `OutgoingMessageSender` | `crate::outgoing_message` | 发送 elicitation 请求 |
| `ErrorData` | `rmcp::model` | MCP 错误数据 |
| `RequestId` | `rmcp::model` | MCP 请求 ID |

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `serde::{Deserialize, Serialize}` | 序列化/反序列化 |
| `serde_json::Value` | JSON 值处理 |
| `tracing::error` | 错误日志 |

### 调用关系

```
codex_tool_runner.rs::run_codex_tool_session_inner()
    └─> EventMsg::ApplyPatchApprovalRequest(ApplyPatchApprovalRequestEvent { ... })
        └─> patch_approval::handle_patch_approval_request()
            ├─> outgoing.send_request("elicitation/create", ...)
            └─> tokio::spawn(async move {
                    on_patch_approval_response(...)
                    ├─> receiver.await
                    ├─> 失败时: codex.submit(Op::PatchApproval { decision: Denied, ... })
                    └─> 成功时: codex.submit(Op::PatchApproval { decision: response.decision, ... })
                })
```

## 依赖与外部交互

### MCP Elicitation 协议

**发送请求：**
```json
{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "elicitation/create",
    "params": {
        "message": "Refactoring main function\nAllow Codex to apply proposed code changes?",
        "requestedSchema": {"type": "object", "properties": {}},
        "threadId": "...",
        "codex_elicitation": "patch-approval",
        "codex_mcp_tool_call_id": "...",
        "codex_event_id": "...",
        "codex_call_id": "...",
        "codex_reason": "Refactoring main function",
        "codex_grant_root": "/home/user/project",
        "codex_changes": {
            "/home/user/project/src/main.rs": {
                "type": "Update",
                "unified_diff": "@@ -1,5 +1,5 @@\n ...",
                "move_path": null
            }
        }
    }
}
```

**接收响应：**
```json
{
    "jsonrpc": "2.0",
    "id": 2,
    "result": {
        "decision": "approved"
    }
}
```

### 与 Codex 核心交互

**提交审批决策：**
```rust
codex.submit(Op::PatchApproval {
    id: approval_id,           // 关联原始请求
    decision: response.decision,  // Approved 或 Denied
})
```

### FileChange 类型

```rust
pub enum FileChange {
    Update {
        unified_diff: String,   // 统一 diff 格式
        move_path: Option<PathBuf>,  // 可选的移动目标
    },
    Delete,
}
```

## 风险、边界与改进建议

### 已知风险

1. **响应格式不匹配**：与 `exec_approval.rs` 类似，`PatchApprovalResponse` 可能不符合 MCP Elicitation 响应规范

2. **序列化失败处理**：如果 `PatchApprovalElicitRequestParams` 序列化失败，发送错误响应但不中断会话
   ```rust
   let params_json = match serde_json::to_value(&params) {
       Ok(value) => value,
       Err(err) => {
           outgoing.send_error(...).await;
           return;
       }
   };
   ```

3. **大变更集**：`codex_changes` 可能包含大量文件变更，导致请求体过大

4. **路径信息泄露**：`codex_changes` 包含完整文件路径，可能泄露敏感信息

### 边界情况

| 场景 | 行为 |
|------|------|
| 无变更原因 | 仅显示 "Allow Codex to apply proposed code changes?" |
| 空变更集 | 仍会发送请求（由调用方保证有效性） |
| 响应反序列化失败 | 保守拒绝（`ReviewDecision::Denied`） |
| 接收响应失败 | 提交拒绝决策 |
| 提交决策失败 | 记录错误日志，不重试 |
| 路径包含非 UTF-8 字符 | `PathBuf` 处理，序列化时可能失败 |

### 改进建议

1. **规范合规**：更新 `PatchApprovalResponse` 以符合 MCP Elicitation 规范
   ```rust
   pub struct PatchApprovalResponse {
       pub action: String,   // "accept" 或 "reject"
       pub content: Value,   // 额外内容
   }
   ```

2. **变更集限制**：添加变更数量和大小限制，防止请求过大
   ```rust
   if changes.len() > MAX_CHANGES {
       // 分批发送或使用摘要
   }
   ```

3. **路径脱敏**：提供选项脱敏或相对化路径
   ```rust
   let display_path = path.strip_prefix(&base_dir).unwrap_or(path);
   ```

4. **超时处理**：添加 elicitation 超时机制

5. **重试机制**：在提交决策失败时实施有限重试

6. **预览支持**：添加变更预览（diff 统计、影响文件数等）

7. **批量审批**：支持一次 elicitation 审批多个补丁

### 与 exec_approval.rs 的对比

| 方面 | exec_approval.rs | patch_approval.rs |
|------|------------------|-------------------|
| 审批对象 | Shell 命令 | 文件变更 |
| 关键数据 | command, cwd, parsed_cmd | changes, reason, grant_root |
| 消息格式 | 单命令行 | 可能多行（含原因） |
| 失败处理 | 静默返回 | 提交拒绝决策 |
| 保守策略 | 拒绝 | 拒绝 |

### 测试覆盖

集成测试在 `tests/suite/codex_tool.rs` 中：
- `test_patch_approval_triggers_elicitation`：验证完整补丁审批流程

测试要点：
1. 验证 elicitation 请求格式（包含 changes 映射）
2. 验证响应后补丁应用
3. 验证文件内容变更
4. Windows 平台跳过（PowerShell 补丁解析限制）

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn test_patch_approval_triggers_elicitation() {
    if cfg!(windows) {
        // powershell apply_patch shell calls are not parsed into apply patch approvals
        return Ok(());
    }
    // ... 测试逻辑
}
```
