# orchestrator.rs 深度研究文档

## 场景与职责

`orchestrator.rs` 是 Codex 工具执行的核心编排器，负责协调工具调用的完整生命周期：

1. **审批管理 (Approval)**：根据配置策略决定是否需要在执行前获得用户审批
2. **沙箱选择 (Sandbox Selection)**：为工具调用选择适当的沙箱环境
3. **执行重试 (Retry Semantics)**：当沙箱执行失败时，支持升级到无沙箱模式重试
4. **网络审批集成 (Network Approval)**：管理工具执行期间的网络访问审批流程

该模块是工具运行时 (`ToolRuntime`) 的中央协调点，确保所有工具调用都遵循安全策略和用户体验要求。

## 功能点目的

### 1. 工具编排器 (ToolOrchestrator)

```rust
pub(crate) struct ToolOrchestrator {
    sandbox: SandboxManager,
}
```

- **目的**：提供统一的工具执行入口，封装复杂的审批和沙箱逻辑
- **核心方法**：`run()` - 执行完整的工具调用流程

### 2. 执行审批要求 (ExecApprovalRequirement)

```rust
pub(crate) enum ExecApprovalRequirement {
    Skip { bypass_sandbox: bool, proposed_execpolicy_amendment: Option<ExecPolicyAmendment> },
    NeedsApproval { reason: Option<String>, proposed_execpolicy_amendment: Option<ExecPolicyAmendment> },
    Forbidden { reason: String },
}
```

- **Skip**：无需审批，可直接执行
- **NeedsApproval**：需要用户审批，可能附带建议的 execpolicy 修正
- **Forbidden**：根据策略禁止执行

### 3. 沙箱尝试 (SandboxAttempt)

封装单次执行尝试的沙箱配置：
- 沙箱类型（None、MacosSeatbelt、LinuxSeccomp、WindowsRestrictedToken）
- 文件系统和网络策略
- 是否强制执行托管网络
- 平台特定的配置（如 Windows 沙箱级别）

### 4. 执行结果封装 (OrchestratorRunResult)

```rust
pub(crate) struct OrchestratorRunResult<Out> {
    pub output: Out,
    pub deferred_network_approval: Option<DeferredNetworkApproval>,
}
```

支持延迟网络审批模式，允许工具先执行，网络访问请求稍后处理。

## 具体技术实现

### 核心执行流程

```
┌─────────────────────────────────────────────────────────────────┐
│                     ToolOrchestrator::run()                      │
├─────────────────────────────────────────────────────────────────┤
│ 1. 审批阶段 (Approval)                                           │
│    ├─ 获取 ExecApprovalRequirement                              │
│    ├─ Skip → 直接继续                                            │
│    ├─ Forbidden → 返回错误                                       │
│    └─ NeedsApproval → 调用 start_approval_async()               │
│       ├─ 用户拒绝 → ToolError::Rejected                         │
│       └─ 用户批准 → 继续执行                                     │
├─────────────────────────────────────────────────────────────────┤
│ 2. 首次尝试 (First Attempt)                                      │
│    ├─ 选择初始沙箱类型                                           │
│    │  └─ SandboxOverride::BypassSandboxFirstAttempt?            │
│    ├─ 构建 SandboxAttempt                                       │
│    └─ 调用 run_attempt()                                         │
│       ├─ 开始网络审批 (begin_network_approval)                  │
│       ├─ 执行工具 (tool.run())                                  │
│       └─ 完成网络审批 (finish_immediate/deferred)               │
├─────────────────────────────────────────────────────────────────┤
│ 3. 成功路径                                                      │
│    └─ 返回 OrchestratorRunResult                                 │
├─────────────────────────────────────────────────────────────────┤
│ 4. 失败重试路径 (仅当 escalate_on_failure=true)                 │
│    ├─ 检查是否为沙箱拒绝错误                                     │
│    ├─ 检查是否需要重新审批                                       │
│    ├─ 构建升级沙箱 (SandboxType::None)                          │
│    └─ 第二次尝试 (Second Attempt)                               │
└─────────────────────────────────────────────────────────────────┘
```

### 关键代码路径

#### 审批决策逻辑

```rust
// orchestrator.rs:117-165
let requirement = tool.exec_approval_requirement(req).unwrap_or_else(|| {
    default_exec_approval_requirement(approval_policy, &turn_ctx.file_system_sandbox_policy)
});
match requirement {
    ExecApprovalRequirement::Skip { .. } => {
        otel.tool_decision(otel_tn, otel_ci, &ReviewDecision::Approved, otel_cfg);
    }
    ExecApprovalRequirement::Forbidden { reason } => {
        return Err(ToolError::Rejected(reason));
    }
    ExecApprovalRequirement::NeedsApproval { reason, .. } => {
        let approval_ctx = ApprovalCtx { ... };
        let decision = tool.start_approval_async(req, approval_ctx).await;
        // 处理各种审批决策...
    }
}
```

#### 沙箱选择逻辑

```rust
// orchestrator.rs:174-183
let initial_sandbox = match tool.sandbox_mode_for_first_attempt(req) {
    SandboxOverride::BypassSandboxFirstAttempt => crate::exec::SandboxType::None,
    SandboxOverride::NoOverride => self.sandbox.select_initial(
        &turn_ctx.file_system_sandbox_policy,
        turn_ctx.network_sandbox_policy,
        tool.sandbox_preference(),
        turn_ctx.windows_sandbox_level,
        has_managed_network_requirements,
    ),
};
```

#### 失败重试逻辑

```rust
// orchestrator.rs:221-344
Err(ToolError::Codex(CodexErr::Sandbox(SandboxErr::Denied { ... }))) => {
    // 1. 检查网络审批上下文
    // 2. 检查 escalate_on_failure
    // 3. 检查是否允许无沙箱审批
    // 4. 可能需要重新审批
    // 5. 构建升级沙箱并第二次尝试
}
```

### 数据结构详解

#### SandboxAttempt

```rust
pub(crate) struct SandboxAttempt<'a> {
    pub sandbox: crate::exec::SandboxType,                    // 沙箱类型
    pub policy: &'a crate::protocol::SandboxPolicy,          // 沙箱策略
    pub file_system_policy: &'a FileSystemSandboxPolicy,     // 文件系统策略
    pub network_policy: NetworkSandboxPolicy,                // 网络策略
    pub enforce_managed_network: bool,                       // 强制执行托管网络
    pub(crate) manager: &'a SandboxManager,                  // 沙箱管理器
    pub(crate) sandbox_cwd: &'a Path,                        // 沙箱工作目录
    pub codex_linux_sandbox_exe: Option<&'a std::path::PathBuf>, // Linux 沙箱可执行文件
    pub use_legacy_landlock: bool,                           // 使用旧版 Landlock
    pub windows_sandbox_level: WindowsSandboxLevel,          // Windows 沙箱级别
    pub windows_sandbox_private_desktop: bool,               // Windows 私有桌面
}
```

#### ApprovalCtx

```rust
pub(crate) struct ApprovalCtx<'a> {
    pub session: &'a Arc<Session>,           // 会话引用
    pub turn: &'a Arc<TurnContext>,          // 回合上下文
    pub call_id: &'a str,                    // 调用 ID
    pub retry_reason: Option<String>,        // 重试原因（用于升级场景）
    pub network_approval_context: Option<NetworkApprovalContext>, // 网络审批上下文
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::sandboxing::SandboxManager` | 沙箱类型选择和转换 |
| `crate::tools::sandboxing::*` | 工具运行时 trait 和类型 |
| `crate::tools::network_approval::*` | 网络审批流程管理 |
| `crate::guardian::*` | Guardian 自动审批路由 |
| `crate::error::{CodexErr, SandboxErr}` | 错误类型 |
| `codex_otel::ToolDecisionSource` | 遥测指标 |

### 外部协议依赖

| 协议类型 | 用途 |
|----------|------|
| `AskForApproval` | 审批策略枚举 |
| `ReviewDecision` | 用户审批决策 |
| `NetworkPolicyRuleAction` | 网络策略操作 |
| `ExecPolicyAmendment` | 执行策略修正 |

### 调用关系

```
ToolOrchestrator::run()
    ├── tool.exec_approval_requirement()          [trait 方法]
    ├── default_exec_approval_requirement()       [sandboxing.rs]
    ├── tool.start_approval_async()               [trait 方法]
    ├── tool.sandbox_mode_for_first_attempt()     [trait 方法]
    ├── SandboxManager::select_initial()          [sandboxing.rs]
    ├── run_attempt()
    │   ├── begin_network_approval()              [network_approval.rs]
    │   ├── tool.run()                            [trait 方法]
    │   └── finish_immediate/deferred_network_approval() [network_approval.rs]
    └── build_denial_reason_from_output()         [本地辅助函数]
```

## 风险、边界与改进建议

### 已知风险

1. **审批缓存绕过风险**
   - `already_approved` 标志仅在单次工具调用内有效
   - 不同工具实例间不共享审批状态
   - 建议：考虑会话级别的审批缓存

2. **沙箱升级循环**
   - 当前仅支持一次升级（沙箱 → 无沙箱）
   - 如果无沙箱也失败，不会再次尝试
   - 这是设计决策，但需确保用户知晓

3. **网络审批竞态条件**
   - 延迟网络审批模式下，工具执行和网络审批并行
   - 如果工具在审批完成前尝试网络访问，可能被阻塞

### 边界情况

1. **Guardian 模式**
   - 当 `routes_approval_to_guardian()` 返回 true 时，审批路由到 Guardian
   - 拒绝消息使用 `GUARDIAN_REJECTION_MESSAGE` 而非普通拒绝消息

2. **Granular 策略**
   - `AskForApproval::Granular` 配置可禁用沙箱审批提示
   - 此时 `ExecApprovalRequirement::Forbidden` 被返回

3. **Windows 沙箱特殊处理**
   - Windows 沙箱级别影响沙箱选择
   - 私有桌面选项需要特殊配置

### 改进建议

1. **可观测性增强**
   - 添加更多详细的 span 属性到 tracing
   - 记录沙箱选择决策的原因
   - 跟踪重试次数和成功率指标

2. **配置验证**
   - 在构建时验证沙箱配置组合的有效性
   - 提前检测不兼容的策略组合

3. **错误信息优化**
   - `build_denial_reason_from_output()` 当前返回固定字符串
   - 建议：分析输出内容，提供更具体的失败原因

4. **测试覆盖**
   - 添加更多边界情况测试（如网络审批超时）
   - 测试不同平台特定的沙箱行为

### 相关文件引用

| 文件 | 关系 |
|------|------|
| `codex-rs/core/src/tools/sandboxing.rs` | trait 定义和默认实现 |
| `codex-rs/core/src/tools/network_approval.rs` | 网络审批服务 |
| `codex-rs/core/src/sandboxing/mod.rs` | SandboxManager 实现 |
| `codex-rs/core/src/guardian/review.rs` | Guardian 审批路由 |
| `codex-rs/core/src/exec.rs` | SandboxType 定义和 exec 执行 |
