# Research: never.md

## 场景与职责

`never.md` 是 Codex 协议层中定义的最严格的命令审批策略提示词。当 `approval_policy` 被设置为 `AskForApproval::Never` 时，系统将此提示词注入到模型的开发者指令中，明确告知模型：**任何情况下都不要提供 `sandbox_permissions` 参数**，所有命令都将被拒绝执行。

此策略主要用于以下场景：
- **非交互式/自动化环境**：在 CI/CD 或自动化脚本中运行 Codex，确保不会因等待用户审批而阻塞
- **高安全要求环境**：完全禁止命令执行，仅允许纯代码分析和建议
- **沙盒测试环境**：确保模型不会尝试执行任何系统命令

## 功能点目的

1. **完全禁止命令执行**：通过明确告知模型不提供 `sandbox_permissions`，从根本上阻止命令执行流程
2. **防止意外审批请求**：确保模型不会在任何情况下向用户请求权限升级或沙盒绕过
3. **简化安全边界**：对于不需要命令执行的场景，消除所有与命令审批相关的复杂性

## 具体技术实现

### 关键数据结构

```rust
// codex-rs/protocol/src/protocol.rs
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize, Display, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum AskForApproval {
    // ...
    /// Never ask the user to approve commands. Failures are immediately returned
    /// to the model, and never escalated to the user for approval.
    Never,
    // ...
}
```

### 关键流程

1. **提示词加载**（编译时）：
```rust
// codex-rs/protocol/src/models.rs:475
const APPROVAL_POLICY_NEVER: &str = include_str!("prompts/permissions/approval_policy/never.md");
```

2. **开发者指令生成**：
```rust
// codex-rs/protocol/src/models.rs:499-545
impl DeveloperInstructions {
    pub fn from(
        approval_policy: AskForApproval,
        exec_policy: &Policy,
        exec_permission_approvals_enabled: bool,
        request_permissions_tool_enabled: bool,
    ) -> DeveloperInstructions {
        let text = match approval_policy {
            AskForApproval::Never => APPROVAL_POLICY_NEVER.to_string(),
            // ... 其他策略
        };
        DeveloperInstructions::new(text)
    }
}
```

3. **策略冲突检测**：
```rust
// codex-rs/core/src/exec_policy.rs:130-153
pub(crate) fn prompt_is_rejected_by_policy(
    approval_policy: AskForApproval,
    prompt_is_rule: bool,
) -> Option<&'static str> {
    match approval_policy {
        AskForApproval::Never => Some(PROMPT_CONFLICT_REASON),
        // ...
    }
}
```

### 命令执行流程中的拦截点

当 `approval_policy` 为 `Never` 时，以下流程会被触发：

1. **ExecPolicyManager** 会在命令评估阶段检测到策略冲突
2. **prompt_is_rejected_by_policy** 返回 `"approval required by policy, but AskForApproval is set to Never"`
3. 命令执行被立即拒绝，不会进入用户审批流程

## 关键代码路径与文件引用

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/protocol/src/prompts/permissions/approval_policy/never.md` | 提示词内容（本文件） |
| `codex-rs/protocol/src/models.rs:475` | 编译时加载提示词 |
| `codex-rs/protocol/src/models.rs:530` | 根据 `AskForApproval::Never` 选择提示词 |
| `codex-rs/protocol/src/protocol.rs:542-588` | `AskForApproval` 枚举定义 |
| `codex-rs/core/src/exec_policy.rs:130-153` | 策略冲突检测逻辑 |
| `codex-rs/core/src/tools/handlers/shell.rs:379-395` | 命令执行前的策略检查 |

## 依赖与外部交互

### 上游依赖

1. **配置系统**：通过 `Config` 中的 `approval_policy` 字段设置
```rust
// codex-rs/core/src/config/mod.rs:198
pub struct Permissions {
    pub approval_policy: Constrained<AskForApproval>,
    // ...
}
```

2. **ExecPolicy 系统**：`codex_execpolicy` crate 提供的命令评估能力

### 下游影响

1. **Shell 工具处理**：`ShellHandler` 和 `ShellCommandHandler` 在 `run_exec_like` 中会检查 `approval_policy`
2. **模型行为**：提示词直接影响模型的命令调用决策
3. **用户体验**：用户不会收到任何审批提示，命令直接失败

## 风险、边界与改进建议

### 风险

1. **模型不遵循指令**：尽管提示词明确，但模型仍可能尝试提供 `sandbox_permissions`，导致命令被拒绝
2. **误用风险**：用户可能误以为 `Never` 策略会自动允许命令执行，而实际上它会阻止所有命令
3. **功能受限**：在此策略下，Codex 只能提供代码分析和建议，无法执行任何系统命令

### 边界情况

1. **Granular 策略的替代**：`AskForApproval::Granular` 可以更精细地控制哪些类别的审批被允许/拒绝
2. **与 sandbox_policy 的关系**：`Never` 策略独立于沙盒策略，即使 `sandbox_policy` 是 `DangerFullAccess`，命令仍会被拒绝

### 改进建议

1. **增强错误提示**：当命令因 `Never` 策略被拒绝时，向模型提供更详细的解释，帮助其理解为什么不能执行命令
2. **文档完善**：在用户配置文档中明确说明 `Never` 策略的行为，避免误解
3. **考虑添加 `AutoApprove` 策略**：如果需求是自动允许而非自动拒绝，需要一个新的策略变体
4. **模型微调**：考虑在模型训练数据中增加对此类严格策略提示词的理解

### 相关测试

```rust
// 测试位置参考
codex-rs/core/tests/suite/exec_policy.rs
codex-rs/core/tests/suite/approvals.rs
```
