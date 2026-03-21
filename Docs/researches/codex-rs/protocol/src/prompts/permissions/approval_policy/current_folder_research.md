# DIR Research: codex-rs/protocol/src/prompts/permissions/approval_policy

## 概述

本目录包含 Codex 项目中用于指导 AI 模型理解命令执行审批策略（Approval Policy）的提示词模板文件。这些 Markdown 文件被编译时嵌入到 Rust 代码中，作为系统提示词（System Prompts）的一部分，告知模型在不同审批策略下如何请求用户批准执行命令。

---

## 场景与职责

### 业务场景

Codex 是一个 AI 编程助手，需要执行用户请求的各种 shell 命令。由于这些命令可能具有破坏性（如 `rm -rf`）或需要超出沙箱限制的权限，系统需要一套机制来控制命令执行前的审批流程。

### 核心职责

1. **模型行为指导**: 告知 AI 模型当前审批策略的具体规则
2. **用户授权流程**: 指导模型何时、如何向用户请求执行许可
3. **权限升级机制**: 说明如何从受限沙箱执行升级到无沙箱执行
4. **规则持久化**: 指导用户如何设置持久化的命令前缀批准规则

### 审批策略类型

| 策略 | 说明 | 使用场景 |
|------|------|----------|
| `never` | 从不请求用户批准，命令失败直接返回给模型 | 自动化/CI 场景 |
| `unless-trusted` | 仅对"已知安全"的只读命令自动批准，其他需审批 | 高安全要求场景 |
| `on-failure` | 所有命令在沙箱内运行，失败后才请求批准重试 | 已废弃，不推荐使用 |
| `on-request` | 由模型决定何时请求批准（默认策略） | 交互式使用场景 |
| `granular` | 细粒度控制，可分别启用/禁用各类审批 | 高级定制场景 |

---

## 功能点目的

### 1. never.md

**目的**: 告知模型在 `approval_policy=never` 模式下不应请求任何权限升级。

**内容**:
```
Approval policy is currently never. Do not provide the `sandbox_permissions` for any reason, commands will be rejected.
```

**技术实现**:
- 在 `DeveloperInstructions::from()` 中当 `AskForApproval::Never` 时加载
- 模型被告知不提供 `sandbox_permissions` 参数
- 任何权限请求都会被系统拒绝

### 2. unless_trusted.md

**目的**: 告知模型 `unless-trusted` 策略下，只有有限的"安全读取"命令可自动执行，其他需用户批准。

**内容**:
```
Approvals are your mechanism to get user consent to run shell commands without the sandbox. `approval_policy` is `unless-trusted`: The harness will escalate most commands for user approval, apart from a limited allowlist of safe "read" commands.
```

**技术实现**:
- 与 `request_permissions` 工具说明组合使用
- 依赖 `is_known_safe_command()` 函数判断命令安全性
- 非安全命令触发 `ExecApprovalRequirement::NeedsApproval`

### 3. on_failure.md

**目的**: 说明 `on-failure` 策略下，命令先在沙箱内运行，失败后才请求用户批准无沙箱重试。

**内容**:
```
Approvals are your mechanism to get user consent to run shell commands without the sandbox. `approval_policy` is `on-failure`: The harness will allow all commands to run in the sandbox (if enabled), and failures will be escalated to the user for approval to run again without the sandbox.
```

**技术实现**:
- 已标记为 DEPRECATED
- 通过 `render_decision_for_unmatched_command()` 实现
- 沙箱失败后触发 `ExecApprovalRequirement::NeedsApproval`

### 4. on_request_rule.md

**目的**: 详细说明 `on-request` 策略下的权限升级请求机制，包括命令分段、请求方式、prefix_rule 指导等。

**核心内容**:
- **命令分段**: 在 `|`, `&&`, `||`, `;`, `$(...)` 等操作符处分割命令
- **升级请求方式**: 使用 `sandbox_permissions: "require_escalated"` + `justification`
- **prefix_rule**: 建议可持久化的命令前缀规则
- **禁止的前缀**: 如 `python3`, `bash`, `git` 等过于宽泛的前缀

**技术实现**:
```rust
// 命令分段解析
fn commands_for_exec_policy(command: &[String]) -> (Vec<Vec<String>>, bool) {
    if let Some(commands) = parse_shell_lc_plain_commands(command) {
        return (commands, false);
    }
    // 回退处理...
}

// prefix_rule 验证
static BANNED_PREFIX_SUGGESTIONS: &[&[&str]] = &[
    &["python3"],
    &["bash"],
    &["git"],
    // ...
];
```

### 5. on_request_rule_request_permission.md

**目的**: 当启用 `request_permissions` 工具时，指导模型优先使用细粒度权限请求而非完全升级。

**核心内容**:
- **首选模式**: `sandbox_permissions: "with_additional_permissions"`
- **额外权限类型**: `network.enabled`, `file_system.read`, `file_system.write`
- **完整升级**: 仅在细粒度权限不足时使用 `require_escalated`

**技术实现**:
- 通过 `Feature::RequestPermissionsTool` 特性开关控制
- 在 `apply_granted_turn_permissions()` 中处理权限应用
- 与 `GranularApprovalConfig.request_permissions` 配置联动

---

## 具体技术实现

### 关键数据结构

#### AskForApproval (协议层)

```rust
// codex-rs/protocol/src/protocol.rs
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum AskForApproval {
    #[serde(rename = "untrusted")]
    #[strum(serialize = "untrusted")]
    UnlessTrusted,
    
    OnFailure,  // DEPRECATED
    
    #[default]
    OnRequest,
    
    #[strum(serialize = "granular")]
    Granular(GranularApprovalConfig),
    
    Never,
}
```

#### GranularApprovalConfig

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct GranularApprovalConfig {
    pub sandbox_approval: bool,      // shell 命令审批
    pub rules: bool,                 // execpolicy 规则触发的审批
    pub skill_approval: bool,        // skill 脚本执行审批
    pub request_permissions: bool,   // request_permissions 工具审批
    pub mcp_elicitations: bool,      // MCP elicitation 审批
}
```

#### SandboxPermissions (模型层)

```rust
// codex-rs/protocol/src/models.rs
#[derive(Debug, Clone, Copy, Default, Eq, Hash, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SandboxPermissions {
    #[default]
    UseDefault,                    // 使用回合配置的沙箱策略
    RequireEscalated,              // 请求无沙箱执行
    WithAdditionalPermissions,     // 在沙箱内扩展权限
}
```

### 关键流程

#### 1. 提示词加载流程

```rust
// codex-rs/protocol/src/models.rs
const APPROVAL_POLICY_NEVER: &str = include_str!("prompts/permissions/approval_policy/never.md");
const APPROVAL_POLICY_UNLESS_TRUSTED: &str = include_str!("prompts/permissions/approval_policy/unless_trusted.md");
const APPROVAL_POLICY_ON_FAILURE: &str = include_str!("prompts/permissions/approval_policy/on_failure.md");
const APPROVAL_POLICY_ON_REQUEST_RULE: &str = include_str!("prompts/permissions/approval_policy/on_request_rule.md");
const APPROVAL_POLICY_ON_REQUEST_RULE_REQUEST_PERMISSION: &str = include_str!("prompts/permissions/approval_policy/on_request_rule_request_permission.md");

impl DeveloperInstructions {
    pub fn from(
        approval_policy: AskForApproval,
        exec_policy: &Policy,
        exec_permission_approvals_enabled: bool,
        request_permissions_tool_enabled: bool,
    ) -> DeveloperInstructions {
        let text = match approval_policy {
            AskForApproval::Never => APPROVAL_POLICY_NEVER.to_string(),
            AskForApproval::UnlessTrusted => with_request_permissions_tool(APPROVAL_POLICY_UNLESS_TRUSTED),
            AskForApproval::OnFailure => with_request_permissions_tool(APPROVAL_POLICY_ON_FAILURE),
            AskForApproval::OnRequest => on_request_instructions(),
            AskForApproval::Granular(granular_config) => granular_instructions(...),
        };
        DeveloperInstructions::new(text)
    }
}
```

#### 2. 审批决策流程

```rust
// codex-rs/core/src/exec_policy.rs
pub(crate) async fn create_exec_approval_requirement_for_command(
    &self,
    req: ExecApprovalRequest<'_>,
) -> ExecApprovalRequirement {
    let exec_policy = self.current();
    let (commands, used_complex_parsing) = commands_for_exec_policy(command);
    
    // 执行策略检查
    let evaluation = exec_policy.check_multiple_with_options(
        commands.iter(),
        &exec_policy_fallback,
        &match_options,
    );
    
    match evaluation.decision {
        Decision::Forbidden => ExecApprovalRequirement::Forbidden { reason },
        Decision::Prompt => {
            // 检查 Granular 配置是否允许
            match prompt_is_rejected_by_policy(approval_policy, prompt_is_rule) {
                Some(reason) => ExecApprovalRequirement::Forbidden { reason },
                None => ExecApprovalRequirement::NeedsApproval { reason, proposed_execpolicy_amendment },
            }
        }
        Decision::Allow => ExecApprovalRequirement::Skip { bypass_sandbox, proposed_execpolicy_amendment },
    }
}
```

#### 3. 命令分段解析

```rust
// codex-rs/core/src/exec_policy.rs
fn commands_for_exec_policy(command: &[String]) -> (Vec<Vec<String>>, bool) {
    // 尝试解析 bash -lc 内部的普通命令
    if let Some(commands) = parse_shell_lc_plain_commands(command) {
        return (commands, false);
    }
    
    // 尝试提取单条命令前缀
    if let Some(single_command) = parse_shell_lc_single_command_prefix(command) {
        return (vec![single_command], true);
    }
    
    // 回退：返回原始命令
    (vec![command.to_vec()], false)
}
```

#### 4. Granular 策略处理

```rust
fn granular_instructions(
    granular_config: GranularApprovalConfig,
    exec_policy: &Policy,
    exec_permission_approvals_enabled: bool,
    request_permissions_tool_enabled: bool,
) -> String {
    let categories = [
        (granular_config.allows_sandbox_approval(), "`sandbox_approval`"),
        (granular_config.allows_rules_approval(), "`rules`"),
        (granular_config.allows_skill_approval(), "`skill_approval`"),
        (granular_config.allows_request_permissions(), "`request_permissions`"),
        (granular_config.allows_mcp_elicitations(), "`mcp_elicitations`"),
    ];
    
    // 生成提示词，区分允许和禁止的类别
    let prompted_categories = categories.iter().filter(|(allowed, _)| *allowed).collect();
    let rejected_categories = categories.iter().filter(|(allowed, _)| !*allowed).collect();
    
    // 组合最终提示词...
}
```

---

## 关键代码路径与文件引用

### 提示词定义文件

| 文件 | 用途 | 加载位置 |
|------|------|----------|
| `never.md` | Never 策略提示词 | `models.rs:475` |
| `unless_trusted.md` | UnlessTrusted 策略提示词 | `models.rs:476-477` |
| `on_failure.md` | OnFailure 策略提示词 | `models.rs:478-479` |
| `on_request_rule.md` | OnRequest 策略基础提示词 | `models.rs:480-481` |
| `on_request_rule_request_permission.md` | OnRequest + RequestPermissions 工具提示词 | `models.rs:482-483` |

### 核心代码文件

| 文件 | 职责 |
|------|------|
| `codex-rs/protocol/src/models.rs` | 提示词加载、DeveloperInstructions 生成 |
| `codex-rs/protocol/src/protocol.rs` | `AskForApproval` 枚举定义 |
| `codex-rs/core/src/exec_policy.rs` | 执行策略管理、审批决策逻辑 |
| `codex-rs/core/src/tools/sandboxing.rs` | 工具运行时审批抽象 |
| `codex-rs/core/src/tools/handlers/shell.rs` | shell 命令处理、审批请求发起 |
| `codex-rs/execpolicy/src/decision.rs` | 底层决策枚举 (`Allow`/`Prompt`/`Forbidden`) |

### 测试文件

| 文件 | 测试范围 |
|------|----------|
| `codex-rs/core/src/exec_policy_tests.rs` | 执行策略单元测试 |
| `codex-rs/core/tests/suite/approvals.rs` | 端到端审批流程测试 |
| `codex-rs/protocol/src/models.rs` (mod tests) | DeveloperInstructions 生成测试 |

---

## 依赖与外部交互

### 上游依赖

1. **codex_execpolicy crate**: 提供底层的 `Policy`, `Decision`, `RuleMatch` 等类型
2. **config 层**: `ConfigLayerStack` 提供用户配置的审批策略
3. **feature 系统**: `Feature::ExecPermissionApprovals`, `Feature::RequestPermissionsTool` 控制功能开关

### 下游消费

1. **AI 模型**: 通过 `DeveloperInstructions` 注入到系统提示词中
2. **工具运行时**: `ToolOrchestrator` 根据审批要求决定是否执行
3. **UI 层**: `ExecApprovalRequestEvent` 发送到客户端请求用户确认

### 配置关联

```toml
# config.toml 示例
[permissions]
approval_policy = "on-request"  # 或 "never", "unless-trusted", "granular"

[permissions.granular]
sandbox_approval = true
rules = true
skill_approval = true
request_permissions = true
mcp_elicitations = true
```

---

## 风险、边界与改进建议

### 已知风险

1. **提示词注入风险**: 如果用户可控内容被嵌入到提示词中，可能导致提示词注入攻击
   - 缓解: 所有提示词内容均为硬编码，不包含用户输入

2. **策略不一致风险**: 代码逻辑与提示词描述可能不一致
   - 缓解: `approvals.rs` 包含端到端测试覆盖所有策略组合

3. **模型误解风险**: 模型可能误解审批策略，导致未授权执行
   - 缓解: 系统层面有 `ExecPolicyManager` 进行二次检查

### 边界情况

1. **空命令处理**: `commands_for_exec_policy` 对空/空白命令有专门回退处理
2. **Heredoc 命令**: 复杂 shell 结构使用 heredoc 时，`auto_amendment_allowed` 设为 false
3. **Windows 特殊处理**: `ReadOnly` 沙箱在 Windows 上不提供真正保护，需特殊处理
4. **Granular 配置冲突**: `sandbox_approval=false` 但 `rules=true` 时的优先级处理

### 改进建议

1. **文档化策略矩阵**: 当前策略逻辑分散在多个文件中，建议创建一个统一的策略决策矩阵文档

2. **提示词版本控制**: 考虑为提示词添加版本号，便于追踪模型行为变化

3. **A/B 测试支持**: 当前提示词为编译时嵌入，可考虑运行时加载以支持提示词 A/B 测试

4. **多语言支持**: 当前提示词仅英文，国际化场景需要考虑多语言提示词

5. **策略可视化**: 建议在 CLI/UI 中展示当前生效的审批策略，帮助用户理解系统行为

6. **prefix_rule 智能建议**: 当前禁止列表为硬编码，可考虑基于命令历史智能建议安全的 prefix_rule

---

## 附录：审批决策流程图

```
用户提交命令
    │
    ▼
┌─────────────────┐
│ 解析命令分段    │◄─── 在 | && || ; 等处分割
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 检查 ExecPolicy │◄─── 匹配 prefix_rule, host_executable 等
│ (codex_execpolicy)│
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼         ▼
  Allow     Prompt    Forbidden
    │         │           │
    ▼         ▼           ▼
┌────────┐ ┌──────────┐ ┌──────────┐
│检查是否 │ │检查      │ │返回      │
│需要绕过 │ │Granular  │ │Forbidden │
│沙箱     │ │配置      │ │          │
└────┬───┘ └────┬─────┘ └──────────┘
     │          │
     ▼          ▼
┌────────┐  ┌──────────┐
│Skip    │  │Needs     │
│bypass= │  │Approval  │
│true/false│ │          │
└────────┘  └──────────┘
                 │
                 ▼
            ┌──────────┐
            │发送      │
            │ExecApproval│
            │RequestEvent│
            │到UI      │
            └──────────┘
                 │
                 ▼
            等待用户决策
```

---

*文档生成时间: 2026-03-21*
*研究范围: codex-rs/protocol/src/prompts/permissions/approval_policy/*
