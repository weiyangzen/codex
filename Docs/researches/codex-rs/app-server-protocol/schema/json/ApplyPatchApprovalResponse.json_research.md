# ApplyPatchApprovalResponse.json 研究文档

## 场景与职责

`ApplyPatchApprovalResponse` 是 Codex App Server Protocol v1 API 中用于**文件变更审批响应**的核心数据结构。当客户端收到 `ApplyPatchApproval` 请求后，通过此结构将用户的审批决策回传给服务器，决定是否执行 AI 提议的文件修改操作。

**关键场景：**
- 用户审阅 AI 生成的代码补丁（文件增删改）
- 用户在 UI 中选择批准、拒绝或中止操作
- 用户选择持久化审批策略（如自动批准同类操作）
- 网络策略修正（允许/拒绝特定主机访问）

## 功能点目的

### 1. 用户决策传递
支持多种审批决策类型：
- **approved**：批准当前文件变更操作
- **approved_execpolicy_amendment**：批准并更新执行策略，未来同类命令自动批准
- **approved_for_session**：批准并缓存，当前会话内同类操作自动批准
- **denied**：拒绝当前操作，但继续会话
- **abort**：拒绝并中止当前会话

### 2. 网络策略管理
支持通过 `network_policy_amendment` 持久化网络访问规则：
- **allow**：允许访问特定主机
- **deny**：拒绝访问特定主机

### 3. 策略学习
通过 `approved_execpolicy_amendment` 实现命令执行策略的自适应学习，减少重复审批打扰。

## 具体技术实现

### 数据结构定义

**JSON Schema 结构：**
```json
{
  "definitions": {
    "ReviewDecision": {
      "oneOf": [
        { "enum": ["approved"], "type": "string" },
        {
          "properties": {
            "approved_execpolicy_amendment": {
              "properties": {
                "proposed_execpolicy_amendment": { "items": { "type": "string" }, "type": "array" }
              },
              "required": ["proposed_execpolicy_amendment"]
            }
          },
          "required": ["approved_execpolicy_amendment"]
        },
        { "enum": ["approved_for_session"], "type": "string" },
        {
          "properties": {
            "network_policy_amendment": {
              "properties": {
                "network_policy_amendment": {
                  "properties": {
                    "action": { "$ref": "#/definitions/NetworkPolicyRuleAction" },
                    "host": { "type": "string" }
                  },
                  "required": ["action", "host"]
                }
              },
              "required": ["network_policy_amendment"]
            }
          },
          "required": ["network_policy_amendment"]
        },
        { "enum": ["denied"], "type": "string" },
        { "enum": ["abort"], "type": "string" }
      ]
    }
  },
  "properties": {
    "decision": { "$ref": "#/definitions/ReviewDecision" }
  },
  "required": ["decision"]
}
```

**Rust 源码定义**（`codex-rs/app-server-protocol/src/protocol/v1.rs`）：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct ApplyPatchApprovalResponse {
    pub decision: ReviewDecision,
}
```

**核心协议层 ReviewDecision 定义**（`codex-rs/protocol/src/protocol.rs`）：
```rust
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ReviewDecision {
    Approved,
    ApprovedExecpolicyAmendment { proposed_execpolicy_amendment: ExecPolicyAmendment },
    ApprovedForSession,
    NetworkPolicyAmendment { network_policy_amendment: NetworkPolicyAmendment },
    Denied,
    Abort,
}
```

### 关键流程

**1. 响应处理**（`bespoke_event_handling.rs` 中的 `on_patch_approval_response`）：
```rust
async fn on_patch_approval_response(
    call_id: String,
    rx: oneshot::Receiver<ClientRequestResult>,
    conversation: Arc<CodexThread>,
) {
    let result = rx.await;
    let decision = match result {
        Ok(Ok(value)) => {
            let response: ApplyPatchApprovalResponse = 
                serde_json::from_value(value).unwrap_or_default();
            response.decision
        }
        // 错误处理...
    };
    
    if let Err(err) = conversation
        .submit(Op::PatchApproval { id: call_id, decision })
        .await
    {
        error!("failed to submit PatchApproval: {err}");
    }
}
```

**2. 决策映射到核心操作**（`codex-rs/core/src/tools/runtimes/apply_patch.rs`）：
```rust
// ReviewDecision 转换为内部 PatchApproval 操作
Op::PatchApproval { id, decision }
```

### V2 API 演进

V2 API 使用 `FileChangeApprovalDecision` 替代，简化决策类型：
```rust
pub enum FileChangeApprovalDecision {
    Accept,
    AcceptForSession,
    Decline,
    Cancel,
}
```

V2 移除了 execpolicy 和 network policy 相关的复杂决策，这些功能移至专门的权限请求 API。

## 关键代码路径与文件引用

### 核心定义文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v1.rs` | Rust 结构定义（第 137-141 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 响应类型注册 |
| `codex-rs/protocol/src/protocol.rs` | 核心 `ReviewDecision` 定义 |
| `codex-rs/protocol/src/approvals.rs` | 审批相关类型定义 |

### 调用方实现
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 审批响应处理 |
| `codex-rs/app-server/src/outgoing_message.rs` | 响应路由基础设施 |

### 客户端处理
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | TUI 审批请求处理 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs` | 审批 UI 决策收集 |
| `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs` | TUI Server 审批覆盖层 |

### 生成文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/typescript/ApplyPatchApprovalResponse.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/ReviewDecision.ts` | ReviewDecision 类型定义 |
| `codex-rs/app-server-protocol/schema/json/ApplyPatchApprovalResponse.json` | JSON Schema 定义 |

## 依赖与外部交互

### 上游依赖
1. **codex_protocol::protocol::ReviewDecision** - 核心决策枚举
2. **codex_protocol::approvals::ExecPolicyAmendment** - 执行策略修正
3. **codex_protocol::approvals::NetworkPolicyAmendment** - 网络策略修正

### 下游消费者
1. **Core Codex** - 将决策转换为 `Op::PatchApproval` 操作
2. **Sandbox System** - 根据决策执行或阻止文件变更
3. **Policy Manager** - 持久化 execpolicy 和 network policy 修正

### 相关请求类型
- `ApplyPatchApprovalParams` - 对应的请求参数
- `ExecCommandApprovalResponse` - 命令执行审批响应（结构类似）

## 风险、边界与改进建议

### 已知限制
1. **V1 已弃用**：`ApplyPatchApprovalResponse` 仅用于遗留 API，新代码应使用 V2
2. **复杂决策类型**：`ReviewDecision` 的 oneOf 结构在部分语言绑定中难以处理
3. **策略持久化不透明**：客户端无法预知哪些决策会触发策略更新

### 安全风险
1. **策略注入**：`approved_execpolicy_amendment` 可能包含任意命令模式，需服务端严格验证
2. **网络策略绕过**：`network_policy_amendment` 可能允许恶意主机访问，需与全局策略合并校验

### 改进建议
1. **迁移到 V2**：新开发使用 `FileChangeApprovalDecision`，更简单且类型安全
2. **策略预览**：在响应中添加 `proposed_policy_changes` 字段，让客户端显示策略变更预览
3. **决策理由**：添加可选的 `reason` 字段，让用户说明拒绝或批准的原因（用于审计）
4. **批量决策**：支持多个文件变更的批量决策，减少用户操作次数

### 测试覆盖
- 决策序列化测试位于 `codex-rs/app-server-protocol/src/protocol/common.rs` 测试模块
- 端到端审批流程测试位于 `codex-rs/app-server/tests/`
- 策略持久化测试位于 `codex-rs/core/tests/suite/approvals.rs`
