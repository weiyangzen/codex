# ApprovalsReviewer.ts 研究文档

## 场景与职责

`ApprovalsReviewer.ts` 定义了审批请求路由的目标类型，用于配置 Codex 中各类审批请求（如沙箱逃逸、网络访问阻塞、MCP 审批提示、ARC 升级等）的审核者。

该类型是 Codex 安全审批系统的核心配置项，决定了当系统需要用户确认或审批时，请求应该被路由到哪里进行处理。

## 功能点目的

### 核心功能

1. **审批路由配置**：指定审批请求的处理方式
2. **自动化审批支持**：支持通过子代理（guardian_subagent）进行自动化风险评估
3. **安全策略执行**：根据配置的安全级别决定审批流程

### 类型定义

```typescript
/**
 * Configures who approval requests are routed to for review. Examples
 * include sandbox escapes, blocked network access, MCP approval prompts, and
 * ARC escalations. Defaults to `user`. `guardian_subagent` uses a carefully
 * prompted subagent to gather relevant context and apply a risk-based
 * decision框架 before approving or denying the request.
 */
export type ApprovalsReviewer = "user" | "guardian_subagent";
```

### 枚举值说明

| 值 | 说明 |
|----|------|
| `user` | 将审批请求路由给实际用户，由人工进行决策（默认行为） |
| `guardian_subagent` | 使用精心提示的子代理自动收集相关上下文并应用基于风险的决策框架 |

## 具体技术实现

### 代码生成来源

**Rust 源码位置**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 267-296)

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
/// Configures who approval requests are routed to for review. Examples
/// include sandbox escapes, blocked network access, MCP approval prompts, and
/// ARC escalations. Defaults to `user`. `guardian_subagent` uses a carefully
/// prompted subagent to gather relevant context and apply a risk-based
/// decision framework before approving or denying the request.
pub enum ApprovalsReviewer {
    User,
    GuardianSubagent,
}

impl ApprovalsReviewer {
    pub fn to_core(self) -> CoreApprovalsReviewer {
        match self {
            ApprovalsReviewer::User => CoreApprovalsReviewer::User,
            ApprovalsReviewer::GuardianSubagent => CoreApprovalsReviewer::GuardianSubagent,
        }
    }
}

impl From<CoreApprovalsReviewer> for ApprovalsReviewer {
    fn from(value: CoreApprovalsReviewer) -> Self {
        match value {
            CoreApprovalsReviewer::User => ApprovalsReviewer::User,
            CoreApprovalsReviewer::GuardianSubagent => ApprovalsReviewer::GuardianSubagent,
        }
    }
}
```

### 核心协议映射

该类型与 `codex_protocol::config_types::ApprovalsReviewer` 进行双向转换：

| API v2 | Core Protocol |
|--------|---------------|
| `User` | `CoreApprovalsReviewer::User` |
| `GuardianSubagent` | `CoreApprovalsReviewer::GuardianSubagent` |

## 关键代码路径与文件引用

### 使用位置

| 文件 | 字段 | 说明 |
|------|------|------|
| `Config.ts` | `approvals_reviewer` | 全局默认审批者配置 |
| `ProfileV2.ts` | `approvals_reviewer` | 配置文件级别的覆盖 |
| `ThreadStartParams.ts` | `approvals_reviewer` | 线程启动时的覆盖 |
| `ThreadResumeParams.ts` | `approvals_reviewer` | 线程恢复时的覆盖 |
| `ThreadForkParams.ts` | `approvals_reviewer` | 线程分叉时的覆盖 |

### 实验性标记

该字段在多个 API 中被标记为实验性（`[UNSTABLE]`）：
- `config/read.approvalsReviewer`
- 配置文件中支持，但 API 稳定性待验证

## 依赖与外部交互

### Guardian Subagent 机制

当设置为 `guardian_subagent` 时：

1. **上下文收集**：子代理自动收集与请求相关的上下文信息
2. **风险评估**：应用基于风险的决策框架
3. **自动决策**：根据风险评分自动批准或拒绝请求
4. **风险等级**：与 `GuardianRiskLevel`（low/medium/high）配合使用

### 审批场景

该配置影响以下审批类型：
- **沙箱逃逸**：当代码尝试突破沙箱限制时
- **网络访问阻塞**：当请求被网络策略阻止时
- **MCP 审批提示**：MCP 服务器需要用户确认时
- **ARC 升级**：自动资源控制升级请求

### 配置层级

审批者配置遵循层级覆盖原则：
1. 全局配置默认值（`Config.approvals_reviewer`）
2. 配置文件覆盖（`ProfileV2.approvals_reviewer`）
3. 线程级覆盖（`ThreadStartParams.approvals_reviewer`）

## 风险、边界与改进建议

### 潜在风险

1. **自动化风险**：`guardian_subagent` 模式虽然提高了效率，但可能存在误判风险
2. **安全责任**：自动化审批将安全决策委托给 AI，需要明确责任边界
3. **配置传播**：线程级配置需要正确传播到子线程和分叉线程

### 边界情况

1. **无效配置**：如果配置了未知的审批者值，将回退到 `user` 模式
2. **子代理故障**：当 guardian_subagent 不可用时，应有降级策略
3. **混合场景**：同一线程中不同类型的审批可能需要不同的审批者

### 改进建议

1. **细粒度控制**：建议支持按审批类型配置不同的审批者
   ```typescript
   // 建议的增强类型
   type ApprovalsReviewerConfig = {
     default: ApprovalsReviewer;
     sandboxEscape?: ApprovalsReviewer;
     networkAccess?: ApprovalsReviewer;
     mcpPrompt?: ApprovalsReviewer;
   }
   ```

2. **风险阈值配置**：为 guardian_subagent 模式添加可配置的风险阈值

3. **审计日志**：增强自动化审批的审计追踪能力

4. **用户覆盖**：即使在 guardian_subagent 模式下，也应允许用户随时接管审批

### 版本兼容性

- 当前版本：v2
- 稳定性：**UNSTABLE**（实验性）
- 引入时间：较新版本中添加
- 变更风险：API 形状可能发生变化

### 相关类型

- `GuardianApprovalReview.ts`：guardian_subagent 的审批结果
- `GuardianRiskLevel.ts`：风险等级评估
- `GuardianApprovalReviewStatus.ts`：审批状态跟踪
