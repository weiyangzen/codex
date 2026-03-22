# ExecCommandApprovalResponse.json 研究文档

## 场景与职责

`ExecCommandApprovalResponse` 是 Codex App-Server 协议 v1 中用于**响应执行命令审批请求**的结构。这是 v1 API 的遗留响应类型，用于向后兼容旧的命令审批流程。

该类型属于 **Client → Server** 的响应流，是 `ExecCommandApproval` 请求的预期响应类型。

### 使用场景

1. **遗留 API 响应**：响应 v1 的 `execCommandApproval` 请求
2. **迁移过渡期**：在客户端从 v1 迁移到 v2 期间保持兼容性

### 与 v2 的关系

v2 引入了 `CommandExecutionRequestApprovalResponse` 作为替代，两者的主要差异在于决策枚举的命名：
- v1: `ReviewDecision`
- v2: `CommandExecutionApprovalDecision`

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `decision` | ReviewDecision | ✅ | 用户的审批决策 |

### 决策类型（ReviewDecision）

`ReviewDecision` 是一个复杂的 `oneOf` 类型，支持以下变体：

#### 1. 简单字符串决策

| 值 | 描述 |
|------|------|
| `"approved"` | 用户批准执行命令 |
| `"approved_for_session"` | 批准执行，同一会话中的后续提示自动执行 |
| `"denied"` | 用户拒绝执行，Agent 继续回合 |
| `"abort"` | 用户拒绝执行，立即中断回合 |

#### 2. 带策略修正的对象决策

**ApprovedExecpolicyAmendment**：
```json
{
  "approved_execpolicy_amendment": {
    "proposed_execpolicy_amendment": ["string"]
  }
}
```

**NetworkPolicyAmendment**：
```json
{
  "network_policy_amendment": {
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
// codex-rs/app-server-protocol/src/protocol/v1.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
pub struct ExecCommandApprovalResponse {
    pub decision: ReviewDecision,
}
```

### ReviewDecision 定义

```rust
// 来自 codex_protocol::protocol
pub enum ReviewDecision {
    Approved,
    ApprovedExecpolicyAmendment {
        proposed_execpolicy_amendment: ExecPolicyAmendment,
    },
    ApprovedForSession,
    NetworkPolicyAmendment {
        network_policy_amendment: NetworkPolicyAmendment,
    },
    Denied,
    Abort,
}
```

### 与 v2 决策的映射关系

| v1 (ReviewDecision) | v2 (CommandExecutionApprovalDecision) |
|---------------------|--------------------------------------|
| `approved` | `accept` |
| `approved_execpolicy_amendment` | `acceptWithExecpolicyAmendment` |
| `approved_for_session` | `acceptForSession` |
| `network_policy_amendment` | `applyNetworkPolicyAmendment` |
| `denied` | `decline` |
| `abort` | `cancel` |

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v1.rs` | 主类型定义（行 158-160） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 注册（行 786-789） |

### 依赖类型

| 文件 | 说明 |
|------|------|
| `codex_protocol::protocol::ReviewDecision` | 核心决策枚举 |

---

## 依赖与外部交互

### 依赖类型

```rust
use codex_protocol::protocol::ReviewDecision;
```

### 命名风格差异

v1 使用 `snake_case` 风格的决策名称：
- `approved_for_session`
- `approved_execpolicy_amendment`
- `network_policy_amendment`

v2 使用 `camelCase` 风格：
- `acceptForSession`
- `acceptWithExecpolicyAmendment`
- `applyNetworkPolicyAmendment`

---

## 风险、边界与改进建议

### 已知风险

1. **命名不一致**：v1 和 v2 的决策命名差异可能导致客户端混淆
   - `denied` vs `decline`
   - `abort` vs `cancel`

2. **弃用状态**：该类型已被标记为 DEPRECATED

### 边界情况

1. **空修正案**：`proposed_execpolicy_amendment` 为空数组时的行为
2. **无效主机格式**：`NetworkPolicyAmendment.host` 的格式验证

### 改进建议

1. **统一命名**：考虑在 v1 响应中同时接受新旧命名（兼容性别名）

2. **自动转换**：服务器端可以自动将 v1 响应转换为 v2 格式：
   ```rust
   impl From<v1::ExecCommandApprovalResponse> for v2::CommandExecutionRequestApprovalResponse {
       fn from(v1: v1::ExecCommandApprovalResponse) -> Self {
           Self { decision: v1.decision.into() }
       }
   }
   ```

3. **弃用警告**：当检测到 v1 API 使用时，服务器可以发送弃用警告通知

4. **迁移工具**：提供自动迁移工具，将客户端代码从 v1 升级到 v2
