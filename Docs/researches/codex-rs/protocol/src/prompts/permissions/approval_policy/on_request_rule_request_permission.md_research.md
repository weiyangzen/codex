# Research: on_request_rule_request_permission.md

## 场景与职责

`on_request_rule_request_permission.md` 是 `OnRequest` 审批策略的增强版本提示词，当 `exec_permission_approvals_enabled` 特性启用时使用。它在基础 `on_request_rule.md` 功能之上，增加了对 `request_permissions` 工具的支持，提供更精细的权限控制。

主要场景包括：
- **精细权限控制**：用户需要请求特定的沙盒权限（网络、文件系统读写），而非完全绕过沙盒
- **最小权限原则**：仅授予完成任务所需的最小权限集
- **权限预设**：允许模型提前请求权限，避免在命令执行时中断

## 功能点目的

1. **沙盒内权限扩展**：优先在沙盒内通过 `request_permissions` 工具请求额外权限，而非完全退出沙盒
2. **分级权限请求**：
   - **首选**：`with_additional_permissions` - 在沙盒内添加临时权限
   - **备选**：`require_escalated` - 完全退出沙盒执行
3. **权限类别**：支持网络访问、文件系统读写、macOS 特定权限等
4. **与 exec-policy 集成**：如果命令匹配已批准的 exec-policy 规则，可自动批准

## 具体技术实现

### 关键数据结构

```rust
// codex-rs/protocol/src/models.rs:67-88
#[derive(Debug, Clone, Default, Eq, Hash, PartialEq, Serialize, Deserialize, JsonSchema, TS)]
pub struct FileSystemPermissions {
    pub read: Option<Vec<AbsolutePathBuf>>,
    pub write: Option<Vec<AbsolutePathBuf>>,
}

#[derive(Debug, Clone, Default, Eq, Hash, PartialEq, Serialize, Deserialize, JsonSchema, TS)]
pub struct NetworkPermissions {
    pub enabled: Option<bool>,
}

#[derive(Debug, Clone, Default, Eq, Hash, PartialEq, Serialize, Deserialize, JsonSchema, TS)]
pub struct PermissionProfile {
    pub network: Option<NetworkPermissions>,
    pub file_system: Option<FileSystemPermissions>,
    pub macos: Option<MacOsSeatbeltProfileExtensions>,
}
```

### 关键流程

1. **提示词加载**（编译时）：
```rust
// codex-rs/protocol/src/models.rs:482-483
const APPROVAL_POLICY_ON_REQUEST_RULE_REQUEST_PERMISSION: &str =
    include_str!("prompts/permissions/approval_policy/on_request_rule_request_permission.md");
```

2. **条件选择**：
```rust
// codex-rs/protocol/src/models.rs:512-517
let on_request_instructions = || {
    let on_request_rule = if exec_permission_approvals_enabled {
        APPROVAL_POLICY_ON_REQUEST_RULE_REQUEST_PERMISSION.to_string()
    } else {
        APPROVAL_POLICY_ON_REQUEST_RULE.to_string()
    };
    // ...
};
```

3. **权限请求处理**：
```rust
// codex-rs/protocol/src/request_permissions.rs
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "snake_case")]
#[ts(tag = "type")]
pub enum RequestPermissionsEvent {
    Request {
        call_id: String,
        turn_id: String,
        requested_permissions: RequestPermissionsArgs,
    },
}
```

### 权限请求模式

#### 首选模式：`with_additional_permissions`

```markdown
## Preferred request mode

When you need extra sandboxed permissions for one command, use:
- `sandbox_permissions: "with_additional_permissions"`
- `additional_permissions` with one or more of:
  - `network.enabled`: set to `true` to enable network access
  - `file_system.read`: list of paths that need read access
  - `file_system.write`: list of paths that need write access
```

#### 备选模式：`require_escalated`

```markdown
## Escalation Requests

Use full escalation only when sandboxed additional permissions cannot satisfy the task.
- `sandbox_permissions: "require_escalated"`
- Include `justification` as a short question asking for approval.
- Optionally include `prefix_rule` to suggest a reusable allow rule.
```

### 与 exec-policy 的集成

```markdown
If the command already matches an exec-policy allow rule, the command can be 
auto-approved without an extra prompt. In that case, exec-policy allow behavior 
(including any sandbox bypass) takes precedence.
```

这意味着：
1. 模型首先检查命令是否匹配已批准的 exec-policy 规则
2. 如果匹配，命令自动批准，无需提示用户
3. 如果不匹配，进入正常的权限请求流程

## 关键代码路径与文件引用

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/protocol/src/prompts/permissions/approval_policy/on_request_rule_request_permission.md` | 提示词内容（本文件） |
| `codex-rs/protocol/src/models.rs:482-483` | 编译时加载提示词 |
| `codex-rs/protocol/src/models.rs:512-528` | 条件选择逻辑 |
| `codex-rs/protocol/src/request_permissions.rs` | `request_permissions` 工具定义 |
| `codex-rs/protocol/src/models.rs:67-223` | 权限相关数据结构 |
| `codex-rs/core/src/tools/handlers/shell.rs:347-395` | 权限申请处理逻辑 |
| `codex-rs/core/src/exec_policy.rs` | exec-policy 评估 |

### 权限申请处理代码

```rust
// codex-rs/core/src/tools/handlers/shell.rs:347-395
let exec_permission_approvals_enabled =
    session.features().enabled(Feature::ExecPermissionApprovals);
let requested_additional_permissions = additional_permissions.clone();
let effective_additional_permissions = apply_granted_turn_permissions(
    session.as_ref(),
    exec_params.sandbox_permissions,
    additional_permissions,
)
.await;
let additional_permissions_allowed = exec_permission_approvals_enabled
    || (session.features().enabled(Feature::RequestPermissionsTool)
        && effective_additional_permissions.permissions_preapproved);

// Approval policy guard for explicit escalation in non-OnRequest modes.
if effective_additional_permissions
    .sandbox_permissions
    .requests_sandbox_override()
    && !effective_additional_permissions.permissions_preapproved
    && !matches!(
        turn.approval_policy.value(),
        codex_protocol::protocol::AskForApproval::OnRequest
    )
{
    // 拒绝非 OnRequest 模式下的权限升级请求
}
```

## 依赖与外部交互

### 上游依赖

1. **特性系统**：
   - `Feature::ExecPermissionApprovals`：控制 exec 权限审批功能
   - `Feature::RequestPermissionsTool`：控制 `request_permissions` 工具

2. **配置系统**：
```rust
// codex-rs/core/src/config/mod.rs
pub struct Permissions {
    pub approval_policy: Constrained<AskForApproval>,
    pub sandbox_policy: Constrained<SandboxPolicy>,
    // ...
}
```

3. **ExecPolicy 系统**：评估命令是否匹配已批准的前缀规则

### 下游影响

1. **权限验证**：`normalize_and_validate_additional_permissions` 函数验证请求的权限
2. **沙盒配置**：根据批准的权限动态调整沙盒配置
3. **用户体验**：用户看到细粒度的权限请求，而非简单的"允许/拒绝"

### 与 `on_request_rule.md` 的关系

| 特性 | `on_request_rule.md` | `on_request_rule_request_permission.md` |
|-----|---------------------|----------------------------------------|
| 使用条件 | `!exec_permission_approvals_enabled` | `exec_permission_approvals_enabled` |
| 权限请求方式 | 仅 `require_escalated` | `with_additional_permissions` + `require_escalated` |
| 沙盒行为 | 完全退出沙盒 | 优先在沙盒内扩展权限 |
| 精细度 | 粗粒度（全部/无） | 细粒度（网络、读、写等） |

## 风险、边界与改进建议

### 风险

1. **权限累积**：多次 `with_additional_permissions` 请求可能导致权限累积，需要定期清理
2. **路径验证**：`file_system.read/write` 中的路径需要严格验证，防止目录遍历攻击
3. **模型混淆**：模型可能混淆 `with_additional_permissions` 和 `require_escalated` 的使用场景

### 边界情况

1. **权限冲突**：
   - 如果 `additional_permissions` 请求的权限与 `sandbox_policy` 冲突，以哪个为准？
   - 当前实现：`additional_permissions` 在命令级别扩展沙盒策略

2. **跨命令权限**：
   - `with_additional_permissions` 是单命令有效还是持续有效？
   - 当前实现：单命令有效，但可通过 `prefix_rule` 持久化

3. **与 exec-policy 的优先级**：
   - exec-policy 的 `allow` 规则优先级高于 `additional_permissions`
   - exec-policy 的 `prompt` 规则可能触发额外的审批提示

### 改进建议

1. **权限缓存**：
   - 实现权限请求的会话级缓存，避免重复请求相同权限
   - 提供权限撤销机制

2. **智能路径建议**：
   - 基于命令内容自动建议需要访问的路径
   - 检测常见的权限需求模式（如 `npm install` 需要网络和 `node_modules` 写入）

3. **权限可视化**：
   - 在用户界面中清晰展示当前有效的权限集
   - 提供权限使用历史记录

4. **安全增强**：
   - 对 `additional_permissions` 中的路径进行规范化验证
   - 限制单次请求的最大权限范围
   - 添加权限请求的频率限制

5. **模型指导**：
   - 在提示词中增加更多使用示例
   - 提供常见场景的权限请求模板

### 相关测试

```rust
// 测试位置参考
codex-rs/core/tests/suite/request_permissions.rs
codex-rs/core/tests/suite/request_permissions_tool.rs
codex-rs/core/src/tools/sandboxing_tests.rs
codex-rs/app-server/tests/suite/v2/request_permissions.rs
```

### 配置示例

```toml
# config.toml
[permissions]
approval_policy = "on-request"

[features]
exec_permission_approvals = true
request_permissions_tool = true
```

### 使用示例

```json
// 模型请求的权限示例
{
  "sandbox_permissions": "with_additional_permissions",
  "additional_permissions": {
    "network": {"enabled": true},
    "file_system": {
      "read": ["/etc/config"],
      "write": ["/tmp/output"]
    }
  },
  "justification": "Need network access to download dependencies and write to /tmp"
}
```
