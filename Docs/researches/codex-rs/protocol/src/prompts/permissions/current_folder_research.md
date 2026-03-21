# Research: codex-rs/protocol/src/prompts/permissions

## 场景与职责

`codex-rs/protocol/src/prompts/permissions` 目录是 Codex CLI/Agent 系统中负责**权限策略提示词模板**的核心组件。该目录包含的 Markdown 文件被编译时嵌入到 Rust 二进制中，用于动态生成向 AI 模型传达当前权限策略的开发者指令（Developer Instructions）。

### 核心职责

1. **权限策略传达**：向 AI 模型说明当前会话的文件系统沙箱模式（sandbox_mode）和命令审批策略（approval_policy）
2. **安全边界定义**：明确告知 AI 哪些操作需要用户审批、哪些操作被允许/禁止
3. **权限升级引导**：指导 AI 如何在需要时请求额外的权限（escalation）
4. **命令分段规则**：解释复杂 shell 命令如何被分割评估以确定权限需求

### 使用场景

- **会话初始化**：根据配置生成初始开发者指令
- **策略变更**：当用户修改权限配置时更新指令
- **权限请求**：AI 需要请求额外权限时参考的模板

---

## 功能点目的

### 1. 审批策略提示词（approval_policy/）

| 文件 | 用途 | 对应策略 |
|------|------|----------|
| `never.md` | 禁止所有命令执行，不请求权限 | `AskForApproval::Never` |
| `unless_trusted.md` | 仅允许已知安全命令，其他需审批 | `AskForApproval::UnlessTrusted` |
| `on_failure.md` | 命令在沙箱中运行，失败时请求审批 | `AskForApproval::OnFailure` |
| `on_request_rule.md` | 模型主动请求审批，支持 prefix_rule | `AskForApproval::OnRequest` |
| `on_request_rule_request_permission.md` | 扩展版本，包含 request_permissions 工具说明 | `AskForApproval::OnRequest` + 工具启用 |

### 2. 沙箱模式提示词（sandbox_mode/）

| 文件 | 用途 | 对应模式 |
|------|------|----------|
| `danger_full_access.md` | 无文件系统限制，警告性描述 | `SandboxPolicy::DangerFullAccess` |
| `read_only.md` | 仅允许读取文件 | `SandboxPolicy::ReadOnly` |
| `workspace_write.md` | 允许读取和写入当前工作目录 | `SandboxPolicy::WorkspaceWrite` |

### 3. 关键功能特性

#### 3.1 命令分段评估
`on_request_rule.md` 详细说明了命令如何被分割：
- 管道符 `|`、逻辑运算符 `&& ||`、分号 `;` 作为分隔符
- 子shell边界 `(...)` 和 `$(...)` 独立评估
- 每个分段独立评估沙箱限制和审批需求

#### 3.2 权限升级机制
支持两种权限请求模式：

**沙箱内权限扩展**（`with_additional_permissions`）：
- 保持沙箱环境
- 临时增加网络或文件系统权限
- 通过 `additional_permissions` 参数指定

**完全升级**（`require_escalated`）：
- 请求在沙箱外运行
- 需要用户明确批准
- 可附带 `prefix_rule` 建议持久化规则

#### 3.3 Prefix Rule 指导
- 禁止过于宽泛的前缀（如 `["python3"]`）
- 禁止为破坏性命令（如 `rm`）提供前缀规则
- 禁止使用 heredoc/herestring 时提供前缀规则
- 推荐按功能分类的前缀（如 `["npm", "run", "dev"]`）

---

## 具体技术实现

### 1. 文件嵌入机制

在 `models.rs` 中使用 `include_str!` 编译时嵌入：

```rust
// models.rs L475-489
const APPROVAL_POLICY_NEVER: &str = include_str!("prompts/permissions/approval_policy/never.md");
const APPROVAL_POLICY_UNLESS_TRUSTED: &str =
    include_str!("prompts/permissions/approval_policy/unless_trusted.md");
const APPROVAL_POLICY_ON_FAILURE: &str =
    include_str!("prompts/permissions/approval_policy/on_failure.md");
const APPROVAL_POLICY_ON_REQUEST_RULE: &str =
    include_str!("prompts/permissions/approval_policy/on_request_rule.md");
const APPROVAL_POLICY_ON_REQUEST_RULE_REQUEST_PERMISSION: &str =
    include_str!("prompts/permissions/approval_policy/on_request_rule_request_permission.md");

const SANDBOX_MODE_DANGER_FULL_ACCESS: &str =
    include_str!("prompts/permissions/sandbox_mode/danger_full_access.md");
const SANDBOX_MODE_WORKSPACE_WRITE: &str =
    include_str!("prompts/permissions/sandbox_mode/workspace_write.md");
const SANDBOX_MODE_READ_ONLY: &str = include_str!("prompts/permissions/sandbox_mode/read_only.md");
```

### 2. 开发者指令生成流程

#### 2.1 入口函数
`DeveloperInstructions::from_policy()`（models.rs L590-623）是主要入口：

```rust
pub fn from_policy(
    sandbox_policy: &SandboxPolicy,
    approval_policy: AskForApproval,
    exec_policy: &Policy,
    cwd: &Path,
    exec_permission_approvals_enabled: bool,
    request_permissions_tool_enabled: bool,
) -> Self {
    // 1. 确定网络访问状态
    let network_access = if sandbox_policy.has_full_network_access() { ... }
    
    // 2. 确定沙箱模式和可写根目录
    let (sandbox_mode, writable_roots) = match sandbox_policy { ... }
    
    // 3. 生成完整指令
    DeveloperInstructions::from_permissions_with_network(...)
}
```

#### 2.2 指令组装流程
`from_permissions_with_network()`（L639-663）：

```rust
fn from_permissions_with_network(...) -> Self {
    let start_tag = DeveloperInstructions::new("<permissions instructions>");
    let end_tag = DeveloperInstructions::new("</permissions instructions>");
    start_tag
        .concat(DeveloperInstructions::sandbox_text(sandbox_mode, network_access))
        .concat(DeveloperInstructions::from(approval_policy, exec_policy, ...))
        .concat(DeveloperInstructions::from_writable_roots(writable_roots))
        .concat(end_tag)
}
```

#### 2.3 沙箱文本生成
`sandbox_text()`（L686-695）根据模式选择模板：

```rust
fn sandbox_text(mode: SandboxMode, network_access: NetworkAccess) -> DeveloperInstructions {
    let template = match mode {
        SandboxMode::DangerFullAccess => SANDBOX_MODE_DANGER_FULL_ACCESS.trim_end(),
        SandboxMode::WorkspaceWrite => SANDBOX_MODE_WORKSPACE_WRITE.trim_end(),
        SandboxMode::ReadOnly => SANDBOX_MODE_READ_ONLY.trim_end(),
    };
    let text = template.replace("{network_access}", &network_access.to_string());
    DeveloperInstructions::new(text)
}
```

#### 2.4 审批策略文本生成
`from()`（L499-545）根据策略选择模板：

```rust
fn from(approval_policy: AskForApproval, exec_policy: &Policy, ...) -> DeveloperInstructions {
    let text = match approval_policy {
        AskForApproval::Never => APPROVAL_POLICY_NEVER.to_string(),
        AskForApproval::UnlessTrusted => with_request_permissions_tool(APPROVAL_POLICY_UNLESS_TRUSTED),
        AskForApproval::OnFailure => with_request_permissions_tool(APPROVAL_POLICY_ON_FAILURE),
        AskForApproval::OnRequest => on_request_instructions(),
        AskForApproval::Granular(granular_config) => granular_instructions(...),
    };
    DeveloperInstructions::new(text)
}
```

### 3. 数据结构关联

#### 3.1 核心类型定义

**SandboxPolicy**（protocol.rs L718-784）：
```rust
pub enum SandboxPolicy {
    DangerFullAccess,
    ReadOnly { access: ReadOnlyAccess, network_access: bool },
    ExternalSandbox { network_access: NetworkAccess },
    WorkspaceWrite { 
        writable_roots: Vec<AbsolutePathBuf>,
        read_only_access: ReadOnlyAccess,
        network_access: bool,
        exclude_tmpdir_env_var: bool,
        exclude_slash_tmp: bool,
    },
}
```

**AskForApproval**（protocol.rs L540-589）：
```rust
pub enum AskForApproval {
    UnlessTrusted,      // 仅信任命令自动批准
    OnFailure,          // 失败时请求审批
    OnRequest,          // 模型主动请求
    Granular(GranularApprovalConfig),  // 细粒度控制
    Never,              // 永不请求
}
```

**GranularApprovalConfig**（protocol.rs L591-606）：
```rust
pub struct GranularApprovalConfig {
    pub sandbox_approval: bool,      // 是否允许沙箱审批
    pub rules: bool,                 // 是否允许规则审批
    pub skill_approval: bool,        // 是否允许技能审批
    pub request_permissions: bool,   // 是否允许权限请求工具
    pub mcp_elicitations: bool,      // 是否允许 MCP 请求
}
```

#### 3.2 权限请求参数

**ShellToolCallParams**（models.rs L1148-1168）：
```rust
pub struct ShellToolCallParams {
    pub command: Vec<String>,
    pub workdir: Option<String>,
    pub timeout_ms: Option<u64>,
    pub sandbox_permissions: Option<SandboxPermissions>,  // 权限覆盖
    pub prefix_rule: Option<Vec<String>>,                 // 建议前缀规则
    pub additional_permissions: Option<PermissionProfile>, // 额外权限
    pub justification: Option<String>,                    // 请求理由
}
```

**SandboxPermissions**（models.rs L33-65）：
```rust
pub enum SandboxPermissions {
    UseDefault,                    // 使用默认策略
    RequireEscalated,             // 请求沙箱外执行
    WithAdditionalPermissions,    // 沙箱内增加权限
}
```

### 4. 权限评估流程

#### 4.1 文件系统权限评估
`FileSystemSandboxPolicy::resolve_access_with_cwd()`（permissions.rs L322-340）：

```rust
pub fn resolve_access_with_cwd(&self, path: &Path, cwd: &Path) -> FileSystemAccessMode {
    match self.kind {
        FileSystemSandboxKind::Unrestricted | FileSystemSandboxKind::ExternalSandbox => {
            return FileSystemAccessMode::Write;
        }
        FileSystemSandboxKind::Restricted => {}
    }
    
    // 解析路径
    let Some(path) = resolve_candidate_path(path, cwd) else {
        return FileSystemAccessMode::None;
    };
    
    // 查找最匹配的条目
    self.resolved_entries_with_cwd(cwd)
        .into_iter()
        .filter(|entry| path.as_path().starts_with(entry.path.as_path()))
        .max_by_key(resolved_entry_precedence)
        .map(|entry| entry.access)
        .unwrap_or(FileSystemAccessMode::None)
}
```

#### 4.2 特殊路径解析
`resolve_file_system_special_path()`（permissions.rs L949-987）：

```rust
fn resolve_file_system_special_path(...) -> Option<AbsolutePathBuf> {
    match value {
        FileSystemSpecialPath::Root | FileSystemSpecialPath::Minimal | ... => None,
        FileSystemSpecialPath::CurrentWorkingDirectory => cwd.cloned(),
        FileSystemSpecialPath::ProjectRoots { subpath } => { ... }
        FileSystemSpecialPath::Tmpdir => { /* 读取 TMPDIR 环境变量 */ }
        FileSystemSpecialPath::SlashTmp => { /* 返回 /tmp */ }
    }
}
```

---

## 关键代码路径与文件引用

### 4.1 提示词模板文件

| 路径 | 类型 | 内容概要 |
|------|------|----------|
| `approval_policy/never.md` | 模板 | 禁止所有命令执行 |
| `approval_policy/unless_trusted.md` | 模板 | 仅信任命令自动通过 |
| `approval_policy/on_failure.md` | 模板 | 失败时升级策略 |
| `approval_policy/on_request_rule.md` | 模板 | 主动请求审批+分段规则 |
| `approval_policy/on_request_rule_request_permission.md` | 模板 | 扩展版+权限工具说明 |
| `sandbox_mode/danger_full_access.md` | 模板 | 无限制模式说明 |
| `sandbox_mode/read_only.md` | 模板 | 只读模式说明 |
| `sandbox_mode/workspace_write.md` | 模板 | 工作区写入模式说明 |

### 4.2 核心代码文件

| 文件 | 相关功能 |
|------|----------|
| `models.rs` L475-489 | 模板嵌入、DeveloperInstructions 生成 |
| `models.rs` L499-545 | 审批策略指令生成 |
| `models.rs` L590-623 | 从策略生成完整指令 |
| `models.rs` L639-663 | 带网络的权限指令组装 |
| `models.rs` L686-695 | 沙箱模式文本生成 |
| `protocol.rs` L540-589 | AskForApproval 枚举定义 |
| `protocol.rs` L718-784 | SandboxPolicy 枚举定义 |
| `permissions.rs` L20-35 | NetworkSandboxPolicy 定义 |
| `permissions.rs` L42-72 | FileSystemAccessMode 定义 |
| `permissions.rs` L117-140 | FileSystemSandboxPolicy 定义 |
| `permissions.rs` L322-349 | 路径权限解析 |
| `approvals.rs` L19-25 | Permissions 结构体 |
| `approvals.rs` L146-196 | ExecApprovalRequestEvent 定义 |
| `request_permissions.rs` L9-74 | 权限请求参数定义 |

### 4.3 测试覆盖

| 测试文件 | 测试内容 |
|----------|----------|
| `models.rs` L1523-1556 | SandboxPermissions 辅助方法测试 |
| `models.rs` L1903-1942 | 沙箱模式转开发者指令测试 |
| `models.rs` L1944-2007 | 权限工具指令包含测试 |
| `models.rs` L2112-2259 | Granular 策略测试 |
| `permissions.rs` L1128-1790 | 文件系统权限策略全面测试 |

---

## 依赖与外部交互

### 5.1 内部依赖

```
prompts/permissions/
├── models.rs (通过 include_str! 嵌入)
│   └── DeveloperInstructions::from_policy()
├── protocol.rs
│   ├── SandboxPolicy
│   ├── AskForApproval
│   └── GranularApprovalConfig
├── permissions.rs
│   ├── FileSystemSandboxPolicy
│   └── NetworkSandboxPolicy
├── approvals.rs
│   └── ExecApprovalRequestEvent
└── request_permissions.rs
    └── RequestPermissionsArgs/Response
```

### 5.2 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| AI 模型 | 文本指令 | 通过 DeveloperInstructions 传递权限上下文 |
| 用户 | 审批提示 | 当 AI 请求权限时展示审批界面 |
| 执行策略 | 配置读取 | 读取 exec_policy 获取已批准前缀 |
| 沙箱系统 | 策略执行 | 根据生成的策略执行命令限制 |

### 5.3 配置关联

- **config.toml** 中的 `sandbox_mode` 和 `approval_policy` 配置
- **execpolicy** 中的前缀规则配置
- **环境变量** `TMPDIR` 影响临时目录权限

---

## 风险、边界与改进建议

### 6.1 潜在风险

#### 6.1.1 安全风险
- **风险**：`danger_full_access.md` 描述的无限制模式可能导致意外文件操作
- **缓解**：该模式需要用户明确配置，且提示词中包含警告性描述

#### 6.1.2 提示词注入风险
- **风险**：用户输入可能通过某些路径影响权限提示词
- **缓解**：模板使用静态字符串，动态内容（如 writable_roots）经过格式化转义

#### 6.1.3 权限升级绕过
- **风险**：AI 可能通过命令分段绕过权限检查
- **缓解**：明确的分段规则说明和独立评估机制

### 6.2 边界情况

#### 6.2.1 路径解析边界
- 符号链接处理：permissions.rs 中有专门的符号链接测试（L1174-1230）
- 跨平台路径：Windows 和 Unix 路径格式差异
- TMPDIR 未设置时的回退行为

#### 6.2.2 策略组合边界
- `Granular` 策略与 `OnRequest` 的复杂交互
- `ExternalSandbox` 模式下文件系统权限的特殊处理
- 网络权限与文件系统权限的独立控制

#### 6.2.3 模板渲染边界
- 模板中的 `{network_access}` 占位符替换
- 前缀规则列表截断（MAX_RENDERED_PREFIXES = 100）
- 文本长度限制（MAX_ALLOW_PREFIX_TEXT_BYTES = 5000）

### 6.3 改进建议

#### 6.3.1 文档改进
1. **增加策略决策流程图**：用 Mermaid 图展示从配置到指令生成的完整流程
2. **补充示例**：为每种策略组合提供实际的提示词输出示例
3. **国际化准备**：当前模板为英文，未来可考虑多语言支持

#### 6.3.2 代码改进
1. **模板版本控制**：考虑在模板中嵌入版本号，便于追踪变更
2. **动态模板加载**：开发模式下支持从文件系统热加载模板
3. **模板验证**：编译时检查模板占位符是否正确替换

#### 6.3.3 功能增强
1. **更细粒度的权限控制**：
   - 按文件类型的权限控制
   - 按命令类型的权限控制
   - 时间窗口限制的临时权限

2. **权限使用审计**：
   - 记录 AI 请求权限的频率和类型
   - 分析权限使用模式优化策略

3. **智能权限建议**：
   - 基于任务类型自动建议合适的权限配置
   - 学习用户审批习惯优化前缀规则推荐

#### 6.3.4 测试增强
1. **集成测试**：增加端到端的权限策略测试
2. **模糊测试**：对路径解析进行模糊测试
3. **性能测试**：大规模前缀规则下的性能基准

### 6.4 技术债务

| 位置 | 问题 | 建议 |
|------|------|------|
| `models.rs` L707 | 硬编码的工具说明字符串 | 提取到独立模板文件 |
| `protocol.rs` L1000+ | 重复的只读子路径计算逻辑 | 与 permissions.rs 中的逻辑统一 |
| `permissions.rs` L1000+ | 复杂的嵌套条件判断 | 考虑使用策略模式重构 |

---

## 总结

`codex-rs/protocol/src/prompts/permissions` 是 Codex 权限系统的核心提示词模板目录，通过编译时嵌入的方式将静态模板与动态策略结合，生成向 AI 模型传达权限上下文的开发者指令。该设计实现了：

1. **安全性**：明确的权限边界和升级机制
2. **灵活性**：多种策略组合满足不同场景需求
3. **可维护性**：模板与代码分离，便于独立更新
4. **可测试性**：全面的单元测试覆盖核心逻辑

理解该目录的内容和关联机制，对于维护和扩展 Codex 的权限系统至关重要。
