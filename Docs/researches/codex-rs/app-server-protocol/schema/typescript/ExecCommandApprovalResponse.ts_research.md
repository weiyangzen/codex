# ExecCommandApprovalResponse Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`ExecCommandApprovalResponse` 是 Codex 应用服务器协议中用于**响应命令执行审批请求**的返回类型。当客户端收到服务器发送的 `ExecCommandApproval` 请求后，使用此类型封装用户的审批决策并返回给服务器。

**典型使用场景：**
- 用户在 UI 中点击"批准"或"拒绝"执行某个命令
- 用户选择"批准并添加到允许列表"（execpolicy amendment）
- 用户选择"批准本次会话的所有类似命令"
- 用户选择"中止"当前任务

**职责：**
- 封装用户对命令执行审批的最终决策
- 支持多种审批决策类型（批准、拒绝、中止、策略修正等）
- 作为 JSON-RPC 响应的 payload 返回给服务器

## 2. 功能点目的 (Purpose of This Type)

该类型的设计目的是：

1. **统一审批响应**：为所有命令执行审批场景提供统一的响应格式
2. **支持复杂决策**：不仅支持简单的批准/拒绝，还支持策略修正等高级决策
3. **双向通信**：完成服务器-客户端之间的审批请求-响应循环
4. **与 ReviewDecision 解耦**：通过包装 `ReviewDecision` 提供扩展性

## 3. 具体技术实现 (Technical Implementation Details)

### TypeScript 定义

```typescript
export type ExecCommandApprovalResponse = { 
  decision: ReviewDecision, 
};
```

### Rust 定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
pub struct ExecCommandApprovalResponse {
    pub decision: ReviewDecision,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `decision` | `ReviewDecision` | 用户的审批决策，支持多种决策类型 |

### ReviewDecision 类型详解

```typescript
export type ReviewDecision = 
  | "approved" 
  | { "approved_execpolicy_amendment": { proposed_execpolicy_amendment: ExecPolicyAmendment } }
  | "approved_for_session" 
  | { "network_policy_amendment": { network_policy_amendment: NetworkPolicyAmendment } }
  | "denied" 
  | "abort";
```

**决策类型说明：**

| 决策值 | 含义 |
|--------|------|
| `"approved"` | 批准执行此命令 |
| `"approved_execpolicy_amendment"` | 批准并添加 execpolicy 前缀规则 |
| `"approved_for_session"` | 批准并允许本次会话的类似请求 |
| `"network_policy_amendment"` | 批准并添加网络策略规则 |
| `"denied"` | 拒绝执行此命令，但继续会话 |
| `"abort"` | 拒绝并中止当前任务 |

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 类型定义
- **TypeScript**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/ExecCommandApprovalResponse.ts`
- **Rust**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v1.rs` (lines 158-161)

### 相关类型
- `ReviewDecision` - 审批决策枚举（protocol crate）
- `ExecPolicyAmendment` - 执行策略修正
- `NetworkPolicyAmendment` - 网络策略修正

### 请求-响应流程
```
ServerRequest::ExecCommandApproval (params: ExecCommandApprovalParams)
  ↓
Client 显示审批 UI
  ↓
ClientResponse (response: ExecCommandApprovalResponse)
```

### 使用位置
- 定义在 `common.rs` 的 `server_request_definitions!` 宏中
- 与 `ExecCommandApprovalParams` 配对使用

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖类型
```typescript
import type { ReviewDecision } from "./ReviewDecision";
```

### ReviewDecision 的依赖
```typescript
import type { ExecPolicyAmendment } from "./ExecPolicyAmendment";
import type { NetworkPolicyAmendment } from "./NetworkPolicyAmendment";
```

### 协议集成
- 属于 **v1 API**（已标记为 DEPRECATED）
- 作为 `ServerRequest::ExecCommandApproval` 的响应类型
- 使用 JSON-RPC 响应格式

### 服务器处理
服务器收到响应后：
1. 解析 `decision` 字段
2. 根据决策类型执行相应操作
3. 对于 `approved_execpolicy_amendment`，更新 execpolicy 配置
4. 对于 `network_policy_amendment`，更新网络策略配置

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **已弃用状态**：该类型属于 v1 API，已被标记为 DEPRECATED
   - v2 替代：`CommandExecutionRequestApprovalResponse`

2. **决策有效性**：某些决策可能不适用于特定场景
   - 例如，非网络命令不应提供 `network_policy_amendment` 选项
   - 服务器通过 `available_decisions` 字段告知客户端允许的决策

3. **决策序列化复杂性**：`ReviewDecision` 是 tagged union 类型，需要正确处理序列化

4. **错误处理**：如果客户端返回无效的决策，服务器可能无法正确处理

### 改进建议

1. **迁移到 v2 API**：新客户端应实现 v2 的审批响应类型

2. **决策验证**：客户端应验证决策是否在服务器提供的 `available_decisions` 列表中

3. **用户确认**：对于 `approved_execpolicy_amendment` 和 `network_policy_amendment`，建议 UI 显示确认对话框，明确告知用户正在添加持久化规则

4. **添加元数据**：考虑添加可选的 `metadata` 字段，允许客户端传递额外的上下文信息

### 测试建议
- 验证所有决策类型的正确序列化和反序列化
- 测试无效决策的处理
- 验证与 execpolicy 和网络策略的集成
- 测试会话级批准（`approved_for_session`）的持久化

### 安全考虑
- `approved_execpolicy_amendment` 会永久修改执行策略，需要谨慎处理
- 建议 UI 对策略修正类决策提供额外的确认步骤
- 考虑添加审批决策的审计日志
