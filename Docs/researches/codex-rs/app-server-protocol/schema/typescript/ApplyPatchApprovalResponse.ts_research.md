# ApplyPatchApprovalResponse.ts 研究文档

## 场景与职责

`ApplyPatchApprovalResponse.ts` 定义了补丁应用审批响应的类型，用于客户端向服务端返回用户对文件变更审批请求的决定。这是文件变更审批流程的响应端类型，与 `ApplyPatchApprovalParams` 构成完整的请求-响应周期。

**核心职责：**
- 封装用户对文件变更审批的决策
- 支持多种审批结果（批准、拒绝、中止等）
- 支持策略修正（如添加执行策略例外）

## 功能点目的

1. **审批决策传递**
   - 将用户的审批决策从客户端传递回服务端
   - 支持简单的批准/拒绝，以及更复杂的策略修正

2. **策略修正支持**
   - 用户可以选择批准并添加执行策略修正
   - 未来类似操作可以自动批准，减少重复交互

3. **会话级授权**
   - 支持 `approved_for_session` 决策，允许会话期间自动批准类似操作

4. **流程控制**
   - `abort` 决策可以立即中断当前操作序列

## 具体技术实现

### 类型定义

```typescript
import type { ReviewDecision } from "./ReviewDecision";

export type ApplyPatchApprovalResponse = { decision: ReviewDecision, };
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `decision` | `ReviewDecision` | 用户的审批决策 |

### 关联类型

- **`ReviewDecision`**: 审批决策枚举类型，包含以下变体：
  - `"approved"`: 批准当前操作
  - `{ "approved_execpolicy_amendment": { proposed_execpolicy_amendment: ExecPolicyAmendment } }`: 批准并添加执行策略修正
  - `"approved_for_session"`: 批准当前操作，并允许会话期间自动批准
  - `{ "network_policy_amendment": { network_policy_amendment: NetworkPolicyAmendment } }`: 网络策略修正
  - `"denied"`: 拒绝当前操作
  - `"abort"`: 拒绝并中止当前流程

### 生成信息

- **生成工具**: [ts-rs](https://github.com/Aleph-Alpha/ts-rs)
- **源文件**: `codex-rs/app-server-protocol/src/protocol/v1.rs`
- **Rust 类型**: `ApplyPatchApprovalResponse`

## 关键代码路径与文件引用

### Rust 源类型定义

```rust
// codex-rs/app-server-protocol/src/protocol/v1.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase")]
pub struct ApplyPatchApprovalResponse {
    pub decision: ReviewDecision,
}
```

### 在 ServerRequest 中的使用

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_request_definitions! {
    ApplyPatchApproval {
        params: v1::ApplyPatchApprovalParams,
        response: v1::ApplyPatchApprovalResponse,
    },
    // ...
}
```

### 关联类型定义

- **`ReviewDecision`**: 审批决策枚举（`./ReviewDecision.ts`）
- **`ExecPolicyAmendment`**: 执行策略修正（`./ExecPolicyAmendment.ts`）
- **`NetworkPolicyAmendment`**: 网络策略修正（`./NetworkPolicyAmendment.ts`）

## 依赖与外部交互

### 上游依赖

| 依赖 | 路径 | 说明 |
|------|------|------|
| `ReviewDecision` | `./ReviewDecision` | 审批决策类型 |

### 下游使用者

- **ServerRequest**: 作为 `applyPatchApproval` 方法的响应类型
- **服务端处理逻辑**: 解析决策并执行相应操作
- **策略管理器**: 处理策略修正的持久化

### 序列化格式示例

```json
// 简单批准
{
  "decision": "approved"
}

// 批准并添加执行策略修正
{
  "decision": {
    "approved_execpolicy_amendment": {
      "proposed_execpolicy_amendment": ["git", "status"]
    }
  }
}

// 拒绝
{
  "decision": "denied"
}

// 中止
{
  "decision": "abort"
}
```

## 风险、边界与改进建议

### 风险点

1. **策略修正的持久化**
   - 执行策略修正需要正确持久化到配置文件
   - 错误的持久化可能导致安全策略被意外绕过

2. **决策验证**
   - 服务端需要验证决策的合法性
   - 防止客户端伪造或篡改决策

3. **并发审批**
   - 多个审批请求并发时的处理顺序
   - 策略修正的并发写入问题

### 边界情况

1. **未知决策值**
   - 如何处理无法识别的决策值
   - 应该明确拒绝还是使用默认值

2. **空响应**
   - 缺失 `decision` 字段的处理
   - 需要明确的错误处理机制

3. **策略修正冲突**
   - 多个策略修正之间的冲突处理
   - 新旧策略的优先级

### 改进建议

1. **添加时间戳**
   - 记录用户做出决策的时间
   - 支持审计和超时重试

2. **添加用户标识**
   - 记录做出决策的用户身份
   - 支持多用户场景下的责任追溯

3. **决策理由**
   - 允许用户输入拒绝或修正的理由
   - 帮助 AI 理解用户意图，改进后续建议

4. **决策确认**
   - 对于高风险操作（如删除文件），要求二次确认
   - 提供决策预览，让用户确认理解后果

5. **与 v2 API 对齐**
   - 当前类型属于 v1 API
   - 考虑在 v2 API 中使用更统一的审批响应模式
