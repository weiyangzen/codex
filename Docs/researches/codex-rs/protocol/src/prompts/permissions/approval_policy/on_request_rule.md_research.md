# Research: on_request_rule.md

## 场景与职责

`on_request_rule.md` 是 Codex `OnRequest` 审批策略的核心提示词文档，定义了模型如何请求命令执行权限升级。这是 Codex 的**默认审批策略**，设计用于交互式使用场景。

主要场景包括：
- **交互式开发**：用户与 Codex 实时对话，Codex 在需要时请求权限
- **权限升级**：命令需要超出当前沙盒限制的权限时（如网络访问、写入受保护目录）
- **规则持久化**：允许用户批准特定命令前缀，避免重复请求

## 功能点目的

1. **命令分段评估**：将复杂命令按 shell 控制操作符分割为独立段，分别评估权限
2. **权限升级请求**：指导模型如何正确请求 `require_escalated` 权限
3. **前缀规则建议**：允许模型建议 `prefix_rule`，用户可持久化批准类似命令
4. **安全边界**：明确禁止对危险命令（如 `rm`）建议前缀规则

## 具体技术实现

### 关键数据结构

```rust
// codex-rs/protocol/src/protocol.rs:575-576
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize, Display, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum AskForApproval {
    // ...
    /// The model decides when to ask the user for approval.
    #[default]
    OnRequest,
    // ...
}

// codex-rs/protocol/src/models.rs:33-65
#[derive(Debug, Clone, Copy, Default, Eq, Hash, PartialEq, Serialize, Deserialize, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum SandboxPermissions {
    /// Run with the turn's configured sandbox policy unchanged.
    #[default]
    UseDefault,
    /// Request to run outside the sandbox.
    RequireEscalated,
    /// Request to stay in the sandbox while widening permissions for this
    /// command only.
    WithAdditionalPermissions,
}
```

### 关键流程

1. **提示词加载**（编译时）：
```rust
// codex-rs/protocol/src/models.rs:480-481
const APPROVAL_POLICY_ON_REQUEST_RULE: &str =
    include_str!("prompts/permissions/approval_policy/on_request_rule.md");
```

2. **开发者指令生成**：
```rust
// codex-rs/protocol/src/models.rs:512-528
let on_request_instructions = || {
    let on_request_rule = if exec_permission_approvals_enabled {
        APPROVAL_POLICY_ON_REQUEST_RULE_REQUEST_PERMISSION.to_string()
    } else {
        APPROVAL_POLICY_ON_REQUEST_RULE.to_string()
    };
    let mut sections = vec![on_request_rule];
    if request_permissions_tool_enabled {
        sections.push(request_permissions_tool_prompt_section().to_string());
    }
    if let Some(prefixes) = approved_command_prefixes_text(exec_policy) {
        sections.push(format!(
            "## Approved command prefixes\nThe following prefix rules have already been approved: {prefixes}"
        ));
    }
    sections.join("\n\n")
};
```

3. **条件选择**：当 `exec_permission_approvals_enabled` 为 true 时，使用 `on_request_rule_request_permission.md` 替代

### 命令分段逻辑

```markdown
# 提示词内容摘要

命令在以下操作符处分割为独立段：
- 管道: `|`
- 逻辑操作符: `&&`, `||`
- 命令分隔符: `;`
- 子 shell 边界: `(...)`, `$()`

示例：
`git pull | tee output.txt` 被分割为：
- ["git", "pull"]
- ["tee", "output.txt"]
```

### 权限升级请求流程

1. **检测需要升级的场景**：
   - 需要写入受保护目录（如 `/var`）
   - 需要运行 GUI 应用（如 `open`, `xdg-open`, `osascript`）
   - 命令因沙盒限制失败（DNS 解析、注册表访问、依赖下载失败）
   - 潜在的破坏性操作（`rm`, `git reset`）

2. **构造升级请求**：
   - 设置 `sandbox_permissions: "require_escalated"`
   - 在 `justification` 中提供简短的问题说明
   - 可选：建议 `prefix_rule` 以便未来自动批准

3. **前缀规则限制**：
   - 禁止：`["python3"]`, `["python", "-"]` 等过于宽泛的前缀
   - 禁止：为 `rm` 等破坏性命令提供前缀规则
   - 禁止：使用 heredoc 或 herestring 的命令提供前缀规则

## 关键代码路径与文件引用

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/protocol/src/prompts/permissions/approval_policy/on_request_rule.md` | 提示词内容（本文件） |
| `codex-rs/protocol/src/models.rs:480-481` | 编译时加载提示词 |
| `codex-rs/protocol/src/models.rs:512-528` | `OnRequest` 策略的指令生成逻辑 |
| `codex-rs/protocol/src/models.rs:33-65` | `SandboxPermissions` 枚举定义 |
| `codex-rs/protocol/src/protocol.rs:575-576` | `AskForApproval::OnRequest` 定义 |
| `codex-rs/core/src/exec_policy.rs:50-97` | 禁止的前缀建议列表 |
| `codex-rs/core/src/tools/handlers/shell.rs` | 命令执行和权限处理 |

### 禁止的前缀规则列表

```rust
// codex-rs/core/src/exec_policy.rs:50-97
static BANNED_PREFIX_SUGGESTIONS: &[&[&str]] = &[
    &["python3"],
    &["python3", "-"],
    &["python3", "-c"],
    &["python"],
    &["bash"],
    &["bash", "-lc"],
    &["sh"],
    &["zsh"],
    &["git"],
    &["sudo"],
    &["node"],
    &["node", "-e"],
    // ... 更多
];
```

## 依赖与外部交互

### 上游依赖

1. **ExecPolicy 系统**：`codex_execpolicy` crate 提供命令前缀匹配和规则评估
2. **配置系统**：`exec_permission_approvals_enabled` 特性开关控制是否启用权限审批
3. **特性系统**：`Feature::ExecPermissionApprovals` 控制功能可用性

### 下游影响

1. **Shell 工具处理**：`ShellHandler` 解析 `sandbox_permissions` 和 `justification` 参数
2. **模型行为**：提示词直接指导模型何时以及如何请求权限升级
3. **用户体验**：用户收到审批提示，可选择批准一次、批准前缀或拒绝

### 与 `request_permissions` 工具的关系

当 `request_permissions_tool_enabled` 为 true 时，提示词会追加工具使用说明：
```rust
// codex-rs/protocol/src/models.rs:707-709
fn request_permissions_tool_prompt_section() -> &'static str {
    "# request_permissions Tool\n\nThe built-in `request_permissions` tool is available..."
}
```

## 风险、边界与改进建议

### 风险

1. **模型误判**：模型可能错误判断何时需要权限升级，导致不必要的用户提示或命令失败
2. **前缀规则滥用**：尽管有禁止列表，模型仍可能建议过于宽泛的前缀规则
3. **提示词注入**：`justification` 参数可能被恶意利用，需要适当的清理

### 边界情况

1. **复杂命令分割**：包含多个操作符的复杂命令需要正确分割和评估
2. **嵌套子 shell**：`$(...)` 和 `(...)` 内的命令需要递归评估
3. **环境变量扩展**：命令中的环境变量在分割时可能尚未解析

### 改进建议

1. **增强前缀验证**：
   - 在运行时验证模型建议的前缀规则
   - 对过于宽泛的前缀给出警告

2. **改进命令分割**：
   - 考虑使用更完善的 shell 解析器
   - 处理更复杂的 shell 语法（如进程替换 `<(...)`）

3. **智能升级建议**：
   - 基于历史数据预测何时需要升级
   - 自动建议合适的前缀规则

4. **安全增强**：
   - 对 `justification` 参数进行内容过滤
   - 添加对危险命令的额外检查层

5. **用户体验**：
   - 提供更详细的升级原因说明
   - 允许用户配置自动批准的命令模式

### 相关测试

```rust
// 测试位置参考
codex-rs/core/tests/suite/request_permissions.rs
codex-rs/core/tests/suite/exec_policy.rs
codex-rs/core/tests/suite/approvals.rs
codex-rs/core/src/exec_policy_tests.rs
```

### 配置示例

```toml
# config.toml
[permissions]
approval_policy = "on-request"  # 默认策略

# 启用 exec_permission_approvals 特性
[features]
exec_permission_approvals = true
```
