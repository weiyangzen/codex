# Research: on_failure.md

## 场景与职责

`on_failure.md` 定义了 `on-failure` 审批策略的提示词。这是 Codex 的一种**已弃用（DEPRECATED）**策略，其设计初衷是：

- 允许所有命令在沙盒中运行（如果启用了沙盒）
- 当命令因沙盒限制失败时，将失败升级为向用户请求在无沙盒环境下重新运行的权限

此策略主要用于早期 Codex 版本，现在推荐使用 `OnRequest` 进行交互式运行，或 `Never` 进行非交互式运行。

## 功能点目的

1. **自动沙盒执行**：默认情况下所有命令都在沙盒中自动执行，无需用户审批
2. **失败时升级**：仅当命令因沙盒限制失败时，才向用户请求权限升级
3. **简化正常流程**：对于不会触发沙盒限制的命令，提供无摩擦的执行体验

## 具体技术实现

### 关键数据结构

```rust
// codex-rs/protocol/src/protocol.rs:566-572
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize, Display, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum AskForApproval {
    // ...
    /// DEPRECATED: *All* commands are auto‑approved, but they are expected to
    /// run inside a sandbox where network access is disabled and writes are
    /// confined to a specific set of paths. If the command fails, it will be
    /// escalated to the user to approve execution without a sandbox.
    /// Prefer `OnRequest` for interactive runs or `Never` for non-interactive
    /// runs.
    OnFailure,
    // ...
}
```

### 关键流程

1. **提示词加载**（编译时）：
```rust
// codex-rs/protocol/src/models.rs:478-479
const APPROVAL_POLICY_ON_FAILURE: &str =
    include_str!("prompts/permissions/approval_policy/on_failure.md");
```

2. **开发者指令生成**：
```rust
// codex-rs/protocol/src/models.rs:534
AskForApproval::OnFailure => with_request_permissions_tool(APPROVAL_POLICY_ON_FAILURE),
```

注意：`with_request_permissions_tool` 包装器会在启用 `request_permissions` 工具时追加相关说明。

3. **与 request_permissions 工具的集成**：
```rust
// codex-rs/protocol/src/models.rs:505-511
let with_request_permissions_tool = |text: &str| {
    if request_permissions_tool_enabled {
        format!("{text}\n\n{}", request_permissions_tool_prompt_section())
    } else {
        text.to_string()
    }
};
```

### 命令执行流程

1. 命令默认在沙盒中执行
2. 如果命令失败且失败原因可能是沙盒限制（如网络访问、文件系统权限）
3. 系统向用户发起审批请求，询问是否允许在无沙盒环境下重新运行
4. 用户批准后，命令重新执行

## 关键代码路径与文件引用

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/protocol/src/prompts/permissions/approval_policy/on_failure.md` | 提示词内容（本文件） |
| `codex-rs/protocol/src/models.rs:478-479` | 编译时加载提示词 |
| `codex-rs/protocol/src/models.rs:534` | 根据 `AskForApproval::OnFailure` 选择提示词 |
| `codex-rs/protocol/src/protocol.rs:566-572` | `AskForApproval::OnFailure` 定义及弃用说明 |
| `codex-rs/core/src/exec_policy.rs:136` | `OnFailure` 策略不拒绝提示 |

## 依赖与外部交互

### 上游依赖

1. **配置系统**：通过 `Config` 中的 `approval_policy` 字段设置
2. **沙盒系统**：依赖沙盒机制来限制命令执行

### 下游影响

1. **命令执行流程**：改变命令执行的默认行为和失败处理逻辑
2. **用户体验**：正常命令无摩擦执行，失败时才需要用户介入

### 与 `request_permissions` 工具的关系

当 `request_permissions_tool_enabled` 为 true 时，提示词会追加：
```markdown
# request_permissions Tool

The built-in `request_permissions` tool is available in this session...
```

## 风险、边界与改进建议

### 风险

1. **已弃用状态**：此策略已被标记为 DEPRECATED，未来版本可能移除
2. **安全风险**：自动允许所有命令在沙盒中运行，如果沙盒机制有漏洞，可能导致安全问题
3. **失败检测准确性**：系统需要准确判断失败是否由沙盒限制引起，误判会导致不必要的用户提示或命令失败

### 边界情况

1. **与 `OnRequest` 的区别**：`OnRequest` 要求模型主动判断何时需要升级，而 `OnFailure` 是失败后自动升级
2. **与 `UnlessTrusted` 的区别**：`UnlessTrusted` 对非安全命令立即提示，而 `OnFailure` 是先执行后提示

### 改进建议

1. **迁移到 `OnRequest`**：按照弃用说明，新代码应使用 `OnRequest` 策略
2. **移除支持**：考虑在后续版本中完全移除此策略的支持
3. **文档更新**：在弃用说明中提供更详细的迁移指南

### 迁移路径

```rust
// 旧代码
approval_policy = AskForApproval::OnFailure

// 新代码推荐
approval_policy = AskForApproval::OnRequest  // 交互式
// 或
approval_policy = AskForApproval::Never      // 非交互式
```

### 相关测试

```rust
// 测试位置参考
codex-rs/core/tests/suite/exec_policy.rs
codex-rs/core/tests/suite/approvals.rs
```
