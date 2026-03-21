# 研究文档：codex-rs/protocol/src/prompts/permissions

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 目录定位

`codex-rs/protocol/src/prompts/permissions/` 目录是 Codex 协议层中负责**权限提示模板**管理的核心目录。它包含了一系列 Markdown 格式的提示模板文件，用于向 AI 模型传达当前会话的权限策略和沙箱配置。

### 核心职责

1. **权限策略提示生成**：为不同的 `approval_policy`（审批策略）提供对应的自然语言提示模板
2. **沙箱模式提示生成**：为不同的 `sandbox_mode`（沙箱模式）提供对应的自然语言提示模板
3. **模型行为指导**：通过系统提示（system prompts）指导 AI 模型如何根据当前权限配置执行命令

### 使用场景

| 场景 | 描述 |
|------|------|
| 会话初始化 | 当新的 Codex 会话启动时，根据配置的权限策略加载对应的提示模板 |
| 策略变更 | 当用户通过配置或命令更改权限策略时，更新提示内容 |
| 命令执行 | AI 模型根据提示中的权限指导决定是否需要请求用户审批 |

---

## 功能点目的

### 2.1 Approval Policy（审批策略）提示

审批策略决定了 AI 执行 shell 命令时如何获取用户许可。目录中包含以下策略模板：

#### `never.md` - 永不审批策略
```markdown
Approval policy is currently never. Do not provide the `sandbox_permissions` for any reason, commands will be rejected.
```
**目的**：完全禁止 AI 请求权限提升，所有需要特殊权限的命令都会被拒绝。

#### `unless_trusted.md` - 除非受信策略
```markdown
Approvals are your mechanism to get user consent to run shell commands without the sandbox. `approval_policy` is `unless-trusted`: The harness will escalate most commands for user approval, apart from a limited allowlist of safe "read" commands.
```
**目的**：仅允许已知安全的"只读"命令自动执行，其他命令都需要用户审批。

#### `on_failure.md` - 失败时审批策略
```markdown
Approvals are your mechanism to get user consent to run shell commands without the sandbox. `approval_policy` is `on-failure`: The harness will allow all commands to run in the sandbox (if enabled), and failures will be escalated to the user for approval to run again without the sandbox.
```
**目的**：允许命令在沙箱中先尝试执行，失败时才请求用户审批。

#### `on_request_rule.md` - 按需请求策略（基础版）
**目的**：指导 AI 何时以及如何请求权限提升，包括：
- 命令分段逻辑（管道、逻辑运算符等）
- 升级请求机制（`sandbox_permissions: "require_escalated"`）
- `prefix_rule` 的使用指导

#### `on_request_rule_request_permission.md` - 按需请求策略（增强版）
**目的**：在基础版之上增加了对 `request_permissions` 工具的支持，允许 AI 请求额外的沙箱内权限而非完全升级。

### 2.2 Sandbox Mode（沙箱模式）提示

沙箱模式定义了文件系统访问权限。目录中包含以下模式模板：

#### `danger_full_access.md` - 完全访问模式
```markdown
Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `danger-full-access`: No filesystem sandboxing - all commands are permitted. Network access is {network_access}.
```
**目的**：告知 AI 当前无任何文件系统限制，可读写任意位置。

#### `read_only.md` - 只读模式
```markdown
Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `read-only`: The sandbox only permits reading files. Network access is {network_access}.
```
**目的**：告知 AI 当前只能读取文件，不能写入。

#### `workspace_write.md` - 工作区写入模式
```markdown
Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `workspace-write`: The sandbox permits reading files, and editing files in `cwd` and `writable_roots`. Editing files in other directories requires approval. Network access is {network_access}.
```
**目的**：告知 AI 可以在当前工作目录和配置的写入根目录中编辑文件，其他位置需要审批。

---

## 具体技术实现

### 3.1 模板加载机制

所有提示模板通过 Rust 的 `include_str!` 宏在编译时嵌入到二进制中：

```rust
// codex-rs/protocol/src/models.rs 第 475-489 行
const APPROVAL_POLICY_NEVER: &str = include_str!("prompts/permissions/approval_policy/never.md");
const APPROVAL_POLICY_UNLESS_TRUSTED: &str = include_str!("prompts/permissions/approval_policy/unless_trusted.md");
const APPROVAL_POLICY_ON_FAILURE: &str = include_str!("prompts/permissions/approval_policy/on_failure.md");
const APPROVAL_POLICY_ON_REQUEST_RULE: &str = include_str!("prompts/permissions/approval_policy/on_request_rule.md");
const APPROVAL_POLICY_ON_REQUEST_RULE_REQUEST_PERMISSION: &str = include_str!("prompts/permissions/approval_policy/on_request_rule_request_permission.md");

const SANDBOX_MODE_DANGER_FULL_ACCESS: &str = include_str!("prompts/permissions/sandbox_mode/danger_full_access.md");
const SANDBOX_MODE_WORKSPACE_WRITE: &str = include_str!("prompts/permissions/sandbox_mode/workspace_write.md");
const SANDBOX_MODE_READ_ONLY: &str = include_str!("prompts/permissions/sandbox_mode/read_only.md");
```

### 3.2 提示组装流程

`DeveloperInstructions` 结构体负责组装权限提示：

```rust
// models.rs 第 499-545 行
impl DeveloperInstructions {
    pub fn from(
        approval_policy: AskForApproval,
        exec_policy: &Policy,
        exec_permission_approvals_enabled: bool,
        request_permissions_tool_enabled: bool,
    ) -> DeveloperInstructions {
        // 根据 approval_policy 选择对应的模板
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

### 3.3 沙箱提示生成

```rust
// models.rs 第 686-695 行
fn sandbox_text(mode: SandboxMode, network_access: NetworkAccess) -> DeveloperInstructions {
    let template = match mode {
        SandboxMode::DangerFullAccess => SANDBOX_MODE_DANGER_FULL_ACCESS.trim_end(),
        SandboxMode::WorkspaceWrite => SANDBOX_MODE_WORKSPACE_WRITE.trim_end(),
        SandboxMode::ReadOnly => SANDBOX_MODE_READ_ONLY.trim_end(),
    };
    // 替换模板中的 {network_access} 占位符
    let text = template.replace("{network_access}", &network_access.to_string());
    DeveloperInstructions::new(text)
}
```

### 3.4 完整权限提示组装

```rust
// models.rs 第 639-663 行
fn from_permissions_with_network(
    sandbox_mode: SandboxMode,
    network_access: NetworkAccess,
    approval_policy: AskForApproval,
    exec_policy: &Policy,
    writable_roots: Option<Vec<WritableRoot>>,
    exec_permission_approvals_enabled: bool,
    request_permissions_tool_enabled: bool,
) -> Self {
    let start_tag = DeveloperInstructions::new("<permissions instructions>");
    let end_tag = DeveloperInstructions::new("</permissions instructions>");
    start_tag
        .concat(DeveloperInstructions::sandbox_text(sandbox_mode, network_access))
        .concat(DeveloperInstructions::from(approval_policy, exec_policy, ...))
        .concat(DeveloperInstructions::from_writable_roots(writable_roots))
        .concat(end_tag)
}
```

---

## 关键代码路径与文件引用

### 4.1 目录结构

```
codex-rs/protocol/src/prompts/permissions/
├── approval_policy/
│   ├── never.md                              # 永不审批策略提示
│   ├── on_failure.md                         # 失败时审批策略提示
│   ├── on_request_rule.md                    # 按需请求策略提示（基础）
│   ├── on_request_rule_request_permission.md # 按需请求策略提示（增强）
│   └── unless_trusted.md                     # 除非受信策略提示
└── sandbox_mode/
    ├── danger_full_access.md                 # 完全访问模式提示
    ├── read_only.md                          # 只读模式提示
    └── workspace_write.md                    # 工作区写入模式提示
```

### 4.2 核心代码文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/models.rs` | 定义 `DeveloperInstructions`，实现提示模板加载和组装逻辑 |
| `codex-rs/protocol/src/protocol.rs` | 定义 `AskForApproval` 枚举（审批策略）、`SandboxPolicy` 枚举（沙箱策略） |
| `codex-rs/protocol/src/config_types.rs` | 定义 `SandboxMode` 枚举（沙箱模式） |
| `codex-rs/protocol/src/permissions.rs` | 实现文件系统沙箱策略的详细逻辑 |
| `codex-rs/protocol/src/approvals.rs` | 定义审批相关的事件和结构体 |
| `codex-rs/protocol/src/request_permissions.rs` | 实现权限请求相关的数据类型 |

### 4.3 关键数据类型

```rust
// protocol.rs - 审批策略枚举
pub enum AskForApproval {
    UnlessTrusted,           // 除非受信
    OnFailure,              // 失败时
    OnRequest,              // 按需请求（默认）
    Granular(GranularApprovalConfig),  // 细粒度控制
    Never,                  // 永不
}

// config_types.rs - 沙箱模式枚举
pub enum SandboxMode {
    ReadOnly,               // 只读
    WorkspaceWrite,         // 工作区写入
    DangerFullAccess,       // 完全访问
}

// permissions.rs - 文件系统沙箱策略
pub struct FileSystemSandboxPolicy {
    pub kind: FileSystemSandboxKind,
    pub entries: Vec<FileSystemSandboxEntry>,
}

// approvals.rs - 权限集合
pub struct Permissions {
    pub sandbox_policy: SandboxPolicy,
    pub file_system_sandbox_policy: FileSystemSandboxPolicy,
    pub network_sandbox_policy: NetworkSandboxPolicy,
    pub macos_seatbelt_profile_extensions: Option<MacOsSeatbeltProfileExtensions>,
}
```

---

## 依赖与外部交互

### 5.1 编译时依赖

| 依赖 | 用途 |
|-----|------|
| `include_str!` 宏 | 将 Markdown 模板文件嵌入到编译后的二进制中 |

### 5.2 运行时依赖

| 模块 | 交互方式 |
|-----|---------|
| `codex_execpolicy::Policy` | 读取已批准的命令前缀规则 |
| `SandboxPolicy` | 获取当前沙箱配置 |
| `AskForApproval` | 确定当前审批策略 |

### 5.3 调用方

| 调用方 | 用途 |
|-------|------|
| `DeveloperInstructions::from_policy()` | 根据策略生成完整提示 |
| `DeveloperInstructions::from()` | 根据审批策略生成提示片段 |
| `DeveloperInstructions::sandbox_text()` | 根据沙箱模式生成提示片段 |

### 5.4 被调用方

提示内容最终被注入到 AI 模型的系统消息中，影响模型的行为决策。

---

## 风险、边界与改进建议

### 6.1 潜在风险

#### 风险 1：提示注入攻击
- **描述**：如果用户输入包含特殊字符或标记，可能干扰权限提示的解析
- **缓解**：模板中的变量通过 `replace()` 方法进行简单的字符串替换，不涉及复杂解析

#### 风险 2：模板与代码不同步
- **描述**：修改模板文件后，如果不重新编译，运行时仍使用旧版本
- **缓解**：使用 `include_str!` 宏确保模板在编译时嵌入，运行时无外部依赖

#### 风险 3：权限提示被截断或忽略
- **描述**：AI 模型可能忽略或误解权限提示，导致未授权操作
- **缓解**：提示使用明确的指令性语言（如 "Do not provide...", "ALWAYS proceed..."）

### 6.2 边界情况

| 边界情况 | 处理逻辑 |
|---------|---------|
| Granular 策略 | 动态生成提示，根据启用的类别列出允许/拒绝的审批类型 |
| 网络访问状态 | 通过 `{network_access}` 占位符动态替换为 `enabled` 或 `restricted` |
| 可写根目录列表 | 通过 `from_writable_roots()` 方法动态追加到提示中 |
| 空可写根目录 | 返回空字符串，不添加额外提示 |

### 6.3 改进建议

#### 建议 1：模板版本控制
- 当前：模板内容与代码版本无显式关联
- 建议：在模板中添加版本注释，便于追踪变更

#### 建议 2：国际化支持
- 当前：所有模板为英文
- 建议：考虑支持多语言提示（如果 Codex 支持非英语交互）

#### 建议 3：模板热重载（开发模式）
- 当前：模板修改需要重新编译
- 建议：在开发模式下支持从文件系统动态加载模板，便于调试

#### 建议 4：更细粒度的权限提示
- 当前：权限提示相对通用
- 建议：根据具体工具（如 `local_shell`、`apply_patch`）提供针对性的权限指导

#### 建议 5：提示长度优化
- 当前：`on_request_rule.md` 和 `on_request_rule_request_permission.md` 内容较长
- 建议：考虑压缩或结构化提示，减少 token 消耗

---

## 附录：相关配置示例

### 配置文件中权限相关的典型配置

```toml
# 示例：.codex/config.toml
[permissions]
approval_policy = "on-request"  # 或 "never", "unless-trusted", "on-failure"
sandbox_mode = "workspace-write"  # 或 "read-only", "danger-full-access"

[permissions.network]
enabled = true  # 或 false
```

### 程序化配置

```rust
// 创建 DeveloperInstructions
let instructions = DeveloperInstructions::from_policy(
    &sandbox_policy,
    approval_policy,
    &exec_policy,
    cwd,
    exec_permission_approvals_enabled,
    request_permissions_tool_enabled,
);
```

---

*文档生成时间：2026-03-21*
*研究对象版本：基于 codex-rs/protocol 当前 HEAD*
