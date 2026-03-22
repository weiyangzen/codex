# CommandExecutionRequestApprovalResponse.json 研究文档

## 场景与职责

`CommandExecutionRequestApprovalResponse` 是 Codex App-Server 协议中用于**响应命令执行审批请求**的结构。当客户端收到 `item/commandExecution/requestApproval` 请求后，通过此结构向服务器返回用户的审批决策。

该类型属于 **Client → Server** 的响应流，是 `CommandExecutionRequestApproval` 请求的预期响应类型。

### 使用场景

1. **用户批准执行**：用户同意执行请求的命令
2. **用户批准并应用策略修正**：用户同意执行并添加 execpolicy 或网络策略规则
3. **用户拒绝执行**：用户拒绝执行命令（可选择继续或中断回合）
4. **会话级自动批准**：用户批准当前命令及同一会话中的后续类似请求

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `decision` | CommandExecutionApprovalDecision | ✅ | 用户的审批决策 |

### 决策类型详解

`CommandExecutionApprovalDecision` 是一个复杂的 `oneOf` 类型，支持以下变体：

#### 1. 简单字符串决策

| 值 | 描述 |
|------|------|
| `"accept"` | 用户批准执行命令 |
| `"acceptForSession"` | 批准执行，同一会话中的后续提示自动执行 |
| `"decline"` | 用户拒绝执行，Agent 继续回合 |
| `"cancel"` | 用户拒绝执行，立即中断回合 |

#### 2. 带策略修正的对象决策

**AcceptWithExecpolicyAmendment**：
```json
{
  "acceptWithExecpolicyAmendment": {
    "execpolicy_amendment": ["string"]
  }
}
```

**ApplyNetworkPolicyAmendment**：
```json
{
  "applyNetworkPolicyAmendment": {
    "network_policy_amendment": {
      "action": "allow" | "deny",
      "host": "string"
    }
  }
}
```

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum CommandExecutionApprovalDecision {
    /// User approved the command.
    Accept,
    /// User approved the command and future prompts in the same session-scoped
    /// approval cache should run without prompting.
    AcceptForSession,
    /// User approved the command, and wants to apply the proposed execpolicy amendment so future
    /// matching commands can run without prompting.
    AcceptWithExecpolicyAmendment {
        execpolicy_amendment: ExecPolicyAmendment,
    },
    /// User chose a persistent network policy rule (allow/deny) for this host.
    ApplyNetworkPolicyAmendment {
        network_policy_amendment: NetworkPolicyAmendment,
    },
    /// User denied the command. The agent will continue the turn.
    Decline,
    /// User denied the command. The turn will also be immediately interrupted.
    Cancel,
}
```

### 从 Core ReviewDecision 的转换

```rust
impl From<CoreReviewDecision> for CommandExecutionApprovalDecision {
    fn from(value: CoreReviewDecision) -> Self {
        match value {
            CoreReviewDecision::Approved => Self::Accept,
            CoreReviewDecision::ApprovedExecpolicyAmendment { ... } => Self::AcceptWithExecpolicyAmendment { ... },
            CoreReviewDecision::ApprovedForSession => Self::AcceptForSession,
            CoreReviewDecision::NetworkPolicyAmendment { ... } => Self::ApplyNetworkPolicyAmendment { ... },
            CoreReviewDecision::Abort => Self::Cancel,
            CoreReviewDecision::Denied => Self::Decline,
        }
    }
}
```

### 策略修正类型

```rust
#[serde(transparent)]
#[ts(type = "Array<string>", export_to = "v2/")]
pub struct ExecPolicyAmendment {
    pub command: Vec<String>,
}

pub struct NetworkPolicyAmendment {
    pub host: String,
    pub action: NetworkPolicyRuleAction,  // Allow | Deny
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 主类型定义（行 5098-5103） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | CommandExecutionApprovalDecision 枚举（行 962-984） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 注册（行 736-739） |

### 使用方

| 文件 | 说明 |
|------|------|
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | TUI 处理审批响应 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 聊天组件构造响应 |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 服务器处理响应 |

---

## 依赖与外部交互

### 依赖类型

```rust
// 来自 codex_protocol crate
use codex_protocol::approvals::ExecPolicyAmendment as CoreExecPolicyAmendment;
use codex_protocol::approvals::NetworkPolicyAmendment as CoreNetworkPolicyAmendment;
use codex_protocol::protocol::ReviewDecision as CoreReviewDecision;
```

### 与 v1 API 的对比

| v1 (ReviewDecision) | v2 (CommandExecutionApprovalDecision) | 说明 |
|---------------------|--------------------------------------|------|
| `approved` | `accept` | 语义一致，命名不同 |
| `approved_execpolicy_amendment` | `acceptWithExecpolicyAmendment` | 结构一致，命名风格变化 |
| `approved_for_session` | `acceptForSession` | 语义一致 |
| `network_policy_amendment` | `applyNetworkPolicyAmendment` | 结构一致，命名风格变化 |
| `denied` | `decline` | 语义一致，命名不同 |
| `abort` | `cancel` | 语义一致，命名不同 |

### 序列化特性

- 使用 `#[serde(rename_all = "camelCase")]` 确保 JSON 字段名为 camelCase
- 使用 `#[serde(untagged)]` 或显式 tag 处理变体序列化

---

## 风险、边界与改进建议

### 已知风险

1. **命名不一致风险**：v1 和 v2 的决策命名差异可能导致客户端混淆
   - v1 使用 `denied`，v2 使用 `decline`
   - v1 使用 `abort`，v2 使用 `cancel`

2. **策略修正格式**：`ExecPolicyAmendment` 使用透明序列化（`transparent`），在 JSON 中直接表现为字符串数组，可能与其他数组类型混淆

### 边界情况

1. **空修正案处理**：当 `execpolicy_amendment` 为空数组时，行为未明确定义
2. **无效主机格式**：`NetworkPolicyAmendment.host` 的格式验证由上层处理
3. **重复策略**：相同的策略修正案重复应用的行为未定义

### 改进建议

1. **命名统一**：考虑在文档中明确标注 v1/v2 命名映射关系，减少迁移成本

2. **增强验证**：在反序列化层添加策略修正格式的验证：
   ```rust
   // 建议添加验证
   impl ExecPolicyAmendment {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.command.is_empty() {
               return Err(ValidationError::EmptyCommand);
           }
           Ok(())
       }
   }
   ```

3. **响应元数据**：考虑添加可选的 `metadata` 字段，允许客户端传递额外的上下文信息（如用户注释、审批时间戳）

4. **批量决策**：对于需要审批多个命令的场景，考虑支持批量响应格式

5. **决策理由**：考虑添加可选的 `reason` 字段，允许用户解释其决策（特别是拒绝时）
