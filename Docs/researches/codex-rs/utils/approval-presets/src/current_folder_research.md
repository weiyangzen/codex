# codex-rs/utils/approval-presets 深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`codex-utils-approval-presets` 是一个轻量级的 Rust 工具库（utility crate），位于 `codex-rs/utils/approval-presets/` 目录下。其核心职责是：**为 Codex TUI 和 MCP 服务器提供一套内置的、预定义的审批策略组合（Approval Presets）**。

### 1.2 设计目标

根据代码注释，该库的设计遵循以下原则：

1. **UI 无关性（UI-agnostic）**：预设定义不依赖任何特定 UI 框架，可被 TUI（Terminal User Interface）和 MCP 服务器同时复用
2. **策略组合**：每个预设将"审批策略"（AskForApproval）与"沙箱策略"（SandboxPolicy）配对，形成完整的安全执行配置
3. **静态定义**：所有预设使用 `&'static str` 类型的静态字符串，避免运行时分配，提高性能

### 1.3 使用场景

| 场景 | 说明 |
|------|------|
| TUI 权限选择弹窗 | 用户在终端界面通过 `open_permissions_popup()` 选择不同的执行模式 |
| 全访问确认流程 | 当用户选择 "full-access" 模式时，触发二次确认弹窗 |
| Windows 沙箱引导 | Windows 平台下引导用户启用沙箱功能的流程 |
| 会话初始化 | 新会话创建时应用默认的审批/沙箱策略组合 |

---

## 2. 功能点目的

### 2.1 核心数据结构

```rust
/// A simple preset pairing an approval policy with a sandbox policy.
#[derive(Debug, Clone)]
pub struct ApprovalPreset {
    /// Stable identifier for the preset.
    pub id: &'static str,
    /// Display label shown in UIs.
    pub label: &'static str,
    /// Short human description shown next to the label in UIs.
    pub description: &'static str,
    /// Approval policy to apply.
    pub approval: AskForApproval,
    /// Sandbox policy to apply.
    pub sandbox: SandboxPolicy,
}
```

**字段说明：**

| 字段 | 类型 | 用途 |
|------|------|------|
| `id` | `&'static str` | 机器可读的唯一标识符，用于代码中匹配特定预设 |
| `label` | `&'static str` | 人类可读的短标签，显示在 UI 选择列表中 |
| `description` | `&'static str` | 详细描述，解释该预设的安全级别和能力范围 |
| `approval` | `AskForApproval` | 审批策略：决定何时向用户请求执行批准 |
| `sandbox` | `SandboxPolicy` | 沙箱策略：决定文件系统和网络访问权限 |

### 2.2 内置预设列表

`builtin_approval_presets()` 函数返回三个预设：

#### 2.2.1 Read Only（只读模式）

```rust
ApprovalPreset {
    id: "read-only",
    label: "Read Only",
    description: "Codex can read files in the current workspace. Approval is required to edit files or access the internet.",
    approval: AskForApproval::OnRequest,
    sandbox: SandboxPolicy::new_read_only_policy(),
}
```

- **ID**: `read-only`
- **审批策略**: `OnRequest` - 按需请求用户批准
- **沙箱策略**: `ReadOnly` - 仅允许读取文件，禁止写入和网络访问
- **适用场景**: 安全审查、代码阅读、无需修改的查询任务
- **平台注意**: Windows 平台默认隐藏此选项（`include_read_only = cfg!(target_os = "windows")`）

#### 2.2.2 Default / Auto（默认模式）

```rust
ApprovalPreset {
    id: "auto",
    label: "Default",
    description: "Codex can read and edit files in the current workspace, and run commands. Approval is required to access the internet or edit other files. (Identical to Agent mode)",
    approval: AskForApproval::OnRequest,
    sandbox: SandboxPolicy::new_workspace_write_policy(),
}
```

- **ID**: `auto`
- **审批策略**: `OnRequest` - 按需请求用户批准
- **沙箱策略**: `WorkspaceWrite` - 允许读取整个磁盘，但只允许写入当前工作目录和临时目录
- **适用场景**: 日常开发任务、代码编辑、项目维护
- **特殊处理**: 
  - Windows 下如果沙箱降级为 `RestrictedToken`，标签显示为 "Default (non-admin sandbox)"
  - 如果 Windows 沙箱未启用，会触发启用引导流程

#### 2.2.3 Full Access（完全访问模式）

```rust
ApprovalPreset {
    id: "full-access",
    label: "Full Access",
    description: "Codex can edit files outside this workspace and access the internet without asking for approval. Exercise caution when using.",
    approval: AskForApproval::Never,
    sandbox: SandboxPolicy::DangerFullAccess,
}
```

- **ID**: `full-access`
- **审批策略**: `Never` - 永不询问用户，自动批准所有请求
- **沙箱策略**: `DangerFullAccess` - 无限制访问，可读写任何文件并访问网络
- **适用场景**: 自动化脚本、CI/CD 环境、受信任的全自动任务
- **安全警告**: 选择此模式会触发二次确认弹窗，警告用户数据丢失和泄露风险

---

## 3. 具体技术实现

### 3.1 依赖类型详解

#### 3.1.1 AskForApproval（审批策略枚举）

定义于 `codex_protocol::protocol::AskForApproval`：

```rust
pub enum AskForApproval {
    /// 仅自动批准"已知安全"的只读命令
    UnlessTrusted,
    
    /// 【已弃用】所有命令自动批准，但在失败时升级
    OnFailure,
    
    /// 【默认】模型决定何时询问用户
    #[default]
    OnRequest,
    
    /// 细粒度控制各个审批流程
    Granular(GranularApprovalConfig),
    
    /// 永不询问，立即返回失败给模型
    Never,
}
```

**GranularApprovalConfig 结构：**

```rust
pub struct GranularApprovalConfig {
    pub sandbox_approval: bool,      // 沙箱命令审批
    pub rules: bool,                 // execpolicy 规则触发的提示
    pub skill_approval: bool,        // Skill 脚本执行审批
    pub request_permissions: bool,   // request_permissions 工具
    pub mcp_elicitations: bool,      // MCP 引导提示
}
```

#### 3.1.2 SandboxPolicy（沙箱策略枚举）

定义于 `codex_protocol::protocol::SandboxPolicy`：

```rust
pub enum SandboxPolicy {
    /// 无限制访问（危险）
    DangerFullAccess,
    
    /// 只读访问
    ReadOnly {
        access: ReadOnlyAccess,
        network_access: bool,
    },
    
    /// 进程已在外部沙箱中运行
    ExternalSandbox {
        network_access: NetworkAccess,
    },
    
    /// 工作区写入（最常用）
    WorkspaceWrite {
        writable_roots: Vec<AbsolutePathBuf>,
        read_only_access: ReadOnlyAccess,
        network_access: bool,
        exclude_tmpdir_env_var: bool,
        exclude_slash_tmp: bool,
    },
}
```

**构造函数：**

```rust
impl SandboxPolicy {
    /// 只读策略：完整磁盘读取，无网络访问
    pub fn new_read_only_policy() -> Self {
        SandboxPolicy::ReadOnly {
            access: ReadOnlyAccess::FullAccess,
            network_access: false,
        }
    }

    /// 工作区写入：完整磁盘读取，仅允许写入 cwd 和 tmp
    pub fn new_workspace_write_policy() -> Self {
        SandboxPolicy::WorkspaceWrite {
            writable_roots: vec![],
            read_only_access: ReadOnlyAccess::FullAccess,
            network_access: false,
            exclude_tmpdir_env_var: false,
            exclude_slash_tmp: false,
        }
    }
}
```

### 3.2 预设匹配逻辑

在 `chatwidget.rs` 中，`preset_matches_current()` 函数用于判断当前配置是否匹配某个预设：

```rust
fn preset_matches_current(
    current_approval: AskForApproval,
    current_sandbox: &SandboxPolicy,
    preset: &ApprovalPreset,
) -> bool {
    // 审批策略必须完全匹配
    if current_approval != preset.approval {
        return false;
    }

    // 沙箱策略根据变体匹配
    match (current_sandbox, &preset.sandbox) {
        (DangerFullAccess, DangerFullAccess) => true,
        (ReadOnly { network_access: n1, .. }, ReadOnly { network_access: n2, .. }) => n1 == n2,
        (WorkspaceWrite { network_access: n1, .. }, WorkspaceWrite { network_access: n2, .. }) => n1 == n2,
        _ => false,
    }
}
```

**注意**：匹配逻辑 intentionally 宽松 - WorkspaceWrite 即使配置了额外的 `writable_roots` 也能匹配 "auto" 预设。

---

## 4. 关键代码路径与文件引用

### 4.1 本库文件

| 文件路径 | 行数 | 说明 |
|----------|------|------|
| `codex-rs/utils/approval-presets/src/lib.rs` | 46 | 唯一源文件，定义 `ApprovalPreset` 和 `builtin_approval_presets()` |
| `codex-rs/utils/approval-presets/Cargo.toml` | 11 | 包配置，依赖 `codex-protocol` |
| `codex-rs/utils/approval-presets/BUILD.bazel` | 6 | Bazel 构建配置 |

### 4.2 调用方文件

#### TUI 模块 (`codex-rs/tui/`)

| 文件 | 引用行 | 用途 |
|------|--------|------|
| `src/app_event.rs` | 19, 245-304 | `ApprovalPreset` 用于多个事件变体（FullAccessConfirmation, WindowsSandboxEnablePrompt 等） |
| `src/chatwidget.rs` | 306-307, 7058, 7310-7374 | `builtin_approval_presets()` 和 `ApprovalPreset` 用于权限弹窗和预设匹配 |
| `src/chatwidget/tests.rs` | 125, 7927-7978 | 测试中使用 `builtin_approval_presets()` 获取预设 |

#### TUI App Server 模块 (`codex-rs/tui_app_server/`)

| 文件 | 引用行 | 用途 |
|------|--------|------|
| `src/app_event.rs` | 21, 256-315 | 与 TUI 类似的事件定义 |
| `src/chatwidget.rs` | 347-348, 4676, 8134, 8389-8656 | 权限弹窗、Windows 沙箱引导流程 |
| `src/chatwidget/tests.rs` | 148, 8525-8566 | 测试中使用 |

### 4.3 被调用方（依赖库）

| 库 | 类型定义位置 | 说明 |
|----|--------------|------|
| `codex-protocol` | `protocol/src/protocol.rs:558` | `AskForApproval` 枚举定义 |
| `codex-protocol` | `protocol/src/protocol.rs:722` | `SandboxPolicy` 枚举定义 |
| `codex-protocol` | `protocol/src/protocol.rs:841` | `SandboxPolicy` 构造函数实现 |

### 4.4 关键调用链

```
用户打开权限弹窗
    ↓
ChatWidget::open_permissions_popup()
    ↓
builtin_approval_presets() → Vec<ApprovalPreset>
    ↓
遍历预设，创建 SelectionItem
    ↓
根据预设 ID 决定行为：
    - "full-access" → OpenFullAccessConfirmation
    - "auto" (Windows) → OpenWindowsSandboxEnablePrompt
    - 其他 → 直接应用预设
```

---

## 5. 依赖与外部交互

### 5.1 依赖图

```
codex-utils-approval-presets
    │
    └── codex-protocol (workspace)
            ├── codex-utils-absolute-path
            ├── serde
            ├── strum
            ├── schemars
            └── ts-rs
```

### 5.2 Cargo.toml 配置

```toml
[package]
name = "codex-utils-approval-presets"
version.workspace = true
edition.workspace = true
license.workspace = true

[lints]
workspace = true

[dependencies]
codex-protocol = { workspace = true }
```

### 5.3 工作空间配置

在 `codex-rs/Cargo.toml` 中定义：

```toml
[workspace.dependencies]
codex-utils-approval-presets = { path = "utils/approval-presets" }
```

被以下 crate 使用：
- `codex-tui`
- `codex-tui-app-server`

---

## 6. 风险、边界与改进建议

### 6.1 当前限制与风险

#### 6.1.1 静态字符串限制

```rust
pub id: &'static str,
pub label: &'static str,
pub description: &'static str,
```

**风险**：无法支持动态本地化（i18n），所有字符串在编译期固定。

**影响**：非英语用户无法看到本地化的预设描述。

#### 6.1.2 预设硬编码

三个预设完全硬编码在 `builtin_approval_presets()` 函数中，无法通过配置文件扩展。

**影响**：用户或企业无法添加自定义预设（如 "Team Review Mode"、"CI Mode" 等）。

#### 6.1.3 平台差异处理分散

Windows 平台对 "auto" 预设的特殊处理（标签修改、沙箱引导）分散在调用方代码中，而非集中在预设定义内。

**代码位置**：
- `chatwidget.rs:7086-7088` - 修改标签为 "Default (non-admin sandbox)"
- `chatwidget.rs:7120-7143` - Windows 沙箱启用引导

#### 6.1.4 描述字符串硬编码

```rust
description: "Codex can read files in the current workspace..."
```

描述中硬编码产品名称 "Codex"，如果产品更名需要修改源码。

### 6.2 边界情况

#### 6.2.1 预设匹配宽松性

`preset_matches_current()` 对 `WorkspaceWrite` 的匹配只比较 `network_access`，忽略：
- `writable_roots` 内容
- `read_only_access` 配置
- `exclude_tmpdir_env_var` / `exclude_slash_tmp` 标志

**后果**：用户自定义了 `writable_roots` 后，UI 仍可能显示 "Default" 预设被选中，造成困惑。

#### 6.2.2 网络访问状态

预设默认 `network_access: false`，但某些企业环境可能需要默认启用网络。

### 6.3 改进建议

#### 6.3.1 支持配置化预设（高优先级）

```rust
// 建议：从配置文件加载额外预设
pub fn load_presets_from_config(config: &ConfigToml) -> Vec<ApprovalPreset> {
    let mut presets = builtin_approval_presets();
    presets.extend(config.custom_approval_presets.clone());
    presets
}
```

#### 6.3.2 本地化支持（中优先级）

将 `label` 和 `description` 改为消息键：

```rust
pub struct ApprovalPreset {
    pub id: &'static str,
    pub label_key: &'static str,       // e.g., "preset.read_only.label"
    pub description_key: &'static str, // e.g., "preset.read_only.desc"
    pub approval: AskForApproval,
    pub sandbox: SandboxPolicy,
}
```

#### 6.3.3 平台特定预设（中优先级）

```rust
#[cfg(target_os = "windows")]
pub fn builtin_approval_presets() -> Vec<ApprovalPreset> {
    // Windows 特定预设，包含 Windows Sandbox 相关配置
}

#[cfg(not(target_os = "windows"))]
pub fn builtin_approval_presets() -> Vec<ApprovalPreset> {
    // 通用预设
}
```

#### 6.3.4 预设元数据扩展（低优先级）

添加更多元数据支持更丰富的 UI：

```rust
pub struct ApprovalPreset {
    // ... 现有字段
    pub icon: Option<&'static str>,           // 图标标识
    pub color: Option<&'static str>,          // UI 主题色
    pub experimental: bool,                    // 是否为实验性功能
    pub requires_confirmation: bool,          // 是否需要二次确认
    pub platform_requirements: PlatformReq,   // 平台要求
}
```

#### 6.3.5 更精确的预设匹配（中优先级）

改进 `preset_matches_current()` 以考虑更多字段：

```rust
fn preset_matches_current(...) -> bool {
    // 现有逻辑...
    
    match (current_sandbox, &preset.sandbox) {
        (WorkspaceWrite { writable_roots, .. }, WorkspaceWrite { .. }) => {
            // 如果 writable_roots 非空，不匹配基础预设
            writable_roots.is_empty()
        }
        // ...
    }
}
```

### 6.4 测试覆盖

当前测试主要集中在：
- `chatwidget/tests.rs` - 预设匹配逻辑测试
- `chatwidget/tests.rs` - 全访问确认弹窗快照测试

**建议增加的测试**：
1. 预设序列化/反序列化测试（确保与 protocol 版本兼容）
2. 所有预设的字段完整性测试
3. 平台特定预设行为测试

---

## 7. 总结

`codex-utils-approval-presets` 是一个设计简洁、职责单一的 utility crate。它成功地将"审批策略"与"沙箱策略"的组合抽象为可复用的"预设"概念，使得 TUI 和 MCP 服务器能够以一致的方式呈现权限选择界面。

**核心优势**：
- 静态定义，零运行时分配
- UI 无关设计，跨组件复用
- 与 `codex-protocol` 类型系统紧密集成

**主要改进空间**：
- 支持配置化扩展预设
- 支持本地化（i18n）
- 更精确的预设匹配逻辑
- 平台特定预设的更好抽象

该库虽然代码量小（仅 46 行），但在 Codex 的安全模型中扮演着关键角色——它是用户与复杂权限系统之间的桥梁，通过简洁的 "Read Only / Default / Full Access" 三层抽象，降低了用户理解和配置安全策略的认知负担。
