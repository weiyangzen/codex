# 研究文档：codex-rs/utils/approval-presets/src/lib.rs

## 1. 场景与职责

### 1.1 定位与目标

`codex-utils-approval-presets` 是一个轻量级的 Rust 工具库，位于 Codex 项目的 `utils` 目录下。其核心职责是**集中定义和管理内置的权限预设（Approval Presets）**，为 TUI（终端用户界面）和潜在的 MCP 服务器提供统一的权限配置选项。

该库的设计遵循**UI 无关性（UI-agnostic）**原则，即不依赖于具体的用户界面实现，只提供纯粹的数据结构定义和预设配置集合。

### 1.2 使用场景

| 场景 | 描述 |
|------|------|
| **TUI 权限选择器** | 用户在终端中通过 `/permissions` 命令或快捷键打开权限选择界面时，展示预设选项（Read Only / Default / Full Access）|
| **Windows 沙盒启用提示** | 当检测到 Windows 沙盒未启用时，基于 "auto" 预设引导用户启用沙盒 |
| **全访问模式确认** | 用户选择 "Full Access" 预设时，需要二次确认以避免意外授予过高权限 |
| **权限匹配与校验** | 在 TUI 中判断当前配置是否与某个预设匹配，以高亮显示当前选项 |

### 1.3 设计哲学

- **单一职责**：仅定义预设数据结构，不涉及 UI 渲染或业务逻辑
- **静态配置**：所有预设都是编译期确定的静态数据（`&'static str`）
- **可扩展性**：通过 `Vec<ApprovalPreset>` 返回类型，为未来动态添加预设留有余地
- **跨平台复用**：同样的预设可被 `codex-tui` 和 `codex-tui-app-server` 共享

---

## 2. 功能点目的

### 2.1 核心功能

#### 2.1.1 ApprovalPreset 结构体

```rust
pub struct ApprovalPreset {
    pub id: &'static str,           // 稳定标识符
    pub label: &'static str,        // UI 显示标签
    pub description: &'static str,  // 简短描述
    pub approval: AskForApproval,   // 审批策略
    pub sandbox: SandboxPolicy,     // 沙盒策略
}
```

**功能目的**：封装一个完整的权限配置单元，将人类可读的元数据（id/label/description）与机器可执行的策略（approval/sandbox）绑定。

#### 2.1.2 builtin_approval_presets 函数

返回三个内置预设：

| 预设 ID | 标签 | 审批策略 | 沙盒策略 | 适用场景 |
|---------|------|----------|----------|----------|
| `read-only` | Read Only | `OnRequest` | `ReadOnly` | 安全审查、只读浏览 |
| `auto` | Default | `OnRequest` | `WorkspaceWrite` | 日常开发、代码编辑 |
| `full-access` | Full Access | `Never` | `DangerFullAccess` | 系统管理、网络访问 |

**功能目的**：提供开箱即用的权限配置组合，降低用户决策成本。

### 2.2 各预设详细说明

#### read-only（只读模式）

```rust
ApprovalPreset {
    id: "read-only",
    label: "Read Only",
    description: "Codex can read files in the current workspace. Approval is required to edit files or access the internet.",
    approval: AskForApproval::OnRequest,
    sandbox: SandboxPolicy::new_read_only_policy(),
}
```

- **沙盒策略**：`SandboxPolicy::ReadOnly { access: FullAccess, network_access: false }`
- **安全特性**：禁止写入、禁止网络访问
- **审批行为**：所有命令执行前都需要用户确认

#### auto（默认/Agent 模式）

```rust
ApprovalPreset {
    id: "auto",
    label: "Default",
    description: "Codex can read and edit files in the current workspace, and run commands. Approval is required to access the internet or edit other files. (Identical to Agent mode)",
    approval: AskForApproval::OnRequest,
    sandbox: SandboxPolicy::new_workspace_write_policy(),
}
```

- **沙盒策略**：`SandboxPolicy::WorkspaceWrite`，允许写入当前工作目录和临时目录
- **安全特性**：文件系统访问限制在工作区，网络仍受限
- **审批行为**：网络访问和修改工作区外文件时需要确认

#### full-access（完全访问）

```rust
ApprovalPreset {
    id: "full-access",
    label: "Full Access",
    description: "Codex can edit files outside this workspace and access the internet without asking for approval. Exercise caution when using.",
    approval: AskForApproval::Never,
    sandbox: SandboxPolicy::DangerFullAccess,
}
```

- **沙盒策略**：`SandboxPolicy::DangerFullAccess`，无任何限制
- **安全特性**：无沙盒保护，可访问整个文件系统和网络
- **审批行为**：**永不询问**，所有操作自动批准（危险）

---

## 3. 具体技术实现

### 3.1 数据结构详解

#### ApprovalPreset

```rust
#[derive(Debug, Clone)]
pub struct ApprovalPreset {
    pub id: &'static str,
    pub label: &'static str,
    pub description: &'static str,
    pub approval: AskForApproval,
    pub sandbox: SandboxPolicy,
}
```

**设计决策**：
- 使用 `&'static str` 而非 `String`：预设是编译期确定的，避免运行时堆分配
- 实现 `Debug` + `Clone`：便于日志记录和事件传递
- 不包含序列化派生：该库专注于运行时内存表示，序列化由调用方处理

### 3.2 依赖类型详解

#### AskForApproval（来自 codex-protocol）

```rust
pub enum AskForApproval {
    UnlessTrusted,           // 仅自动批准"已知安全"的只读命令
    OnFailure,               // 已弃用：失败时才请求批准
    OnRequest,               // 默认：模型决定何时询问
    Granular(GranularApprovalConfig),  // 细粒度控制
    Never,                   // 永不询问（危险）
}
```

#### SandboxPolicy（来自 codex-protocol）

```rust
pub enum SandboxPolicy {
    DangerFullAccess,        // 无限制
    ReadOnly { access, network_access },
    ExternalSandbox { network_access },
    WorkspaceWrite { writable_roots, read_only_access, network_access, ... },
}
```

### 3.3 关键流程

#### 流程 1：TUI 权限选择器初始化

```
tui/src/chatwidget.rs::configure_approval_sandbox()
    ↓
builtin_approval_presets() → Vec<ApprovalPreset>
    ↓
遍历 presets，为每个 preset 创建 SelectionItem
    ↓
调用 preset_matches_current() 判断是否为当前配置
    ↓
渲染 ListSelectionView
```

#### 流程 2：Windows 沙盒启用检查

```
tui/src/chatwidget.rs::maybe_show_windows_sandbox_prompt()
    ↓
检查 WindowsSandboxLevel::Disabled
    ↓
查找 "auto" preset
    ↓
open_windows_sandbox_enable_prompt(preset)
    ↓
引导用户启用 Windows 沙盒
```

#### 流程 3：全访问模式确认

```
用户选择 "full-access" preset
    ↓
open_full_access_confirmation(preset, return_to_permissions)
    ↓
显示二次确认对话框（警告风险）
    ↓
用户确认后才应用 preset.sandbox 和 preset.approval
```

### 3.4 预设匹配算法

在 TUI 中，通过以下逻辑判断当前配置是否匹配某个预设：

```rust
fn preset_matches_current(
    &self,
    current_approval: AskForApproval,
    current_sandbox: &SandboxPolicy,
    preset: &ApprovalPreset,
) -> bool {
    // 1. 审批策略必须完全匹配
    if current_approval != preset.approval {
        return false;
    }
    
    // 2. 沙盒策略必须匹配（考虑额外可写根目录）
    match (current_sandbox, &preset.sandbox) {
        (
            SandboxPolicy::WorkspaceWrite { writable_roots, .. },
            SandboxPolicy::WorkspaceWrite { .. },
        ) => {
            // 允许有额外的 writable_roots，但基础策略必须一致
            // 具体匹配逻辑在 TUI 中实现
        }
        _ => current_sandbox == &preset.sandbox,
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 本库文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `utils/approval-presets/src/lib.rs` | 46 | 定义 `ApprovalPreset` 结构和 `builtin_approval_presets()` 函数 |
| `utils/approval-presets/Cargo.toml` | 11 | 声明依赖 `codex-protocol` |
| `utils/approval-presets/BUILD.bazel` | 6 | Bazel 构建配置 |

### 4.2 调用方文件

#### TUI 主库（codex-tui）

| 文件 | 引用方式 | 使用场景 |
|------|----------|----------|
| `tui/src/chatwidget.rs:306-307` | `use codex_utils_approval_presets::{ApprovalPreset, builtin_approval_presets};` | 权限选择器、Windows 沙盒提示 |
| `tui/src/chatwidget.rs:7058` | `let presets = builtin_approval_presets();` | 配置权限选择列表 |
| `tui/src/chatwidget.rs:7310` | `preset_matches_current()` 参数 | 预设匹配校验 |
| `tui/src/chatwidget.rs:7374` | `open_full_access_confirmation(preset, ...)` | 全访问确认对话框 |
| `tui/src/chatwidget.rs:7577` | `open_windows_sandbox_enable_prompt(preset)` | Windows 沙盒启用提示 |
| `tui/src/app_event.rs:19` | `use codex_utils_approval_presets::ApprovalPreset;` | 事件类型定义 |

#### TUI App Server（codex-tui-app-server）

| 文件 | 引用方式 | 使用场景 |
|------|----------|----------|
| `tui_app_server/src/chatwidget.rs:347-348` | `use codex_utils_approval_presets::{ApprovalPreset, builtin_approval_presets};` | 同上 |
| `tui_app_server/src/chatwidget.rs:8134` | `let presets = builtin_approval_presets();` | 配置权限选择列表 |
| `tui_app_server/src/chatwidget.rs:8389` | `preset_matches_current()` 参数 | 预设匹配校验 |
| `tui_app_server/src/chatwidget.rs:8453` | `open_full_access_confirmation(preset, ...)` | 全访问确认对话框 |
| `tui_app_server/src/app_event.rs:21` | `use codex_utils_approval_presets::ApprovalPreset;` | 事件类型定义 |

### 4.3 依赖库

| 文件 | 提供的类型 | 说明 |
|------|------------|------|
| `protocol/src/protocol.rs:542-589` | `AskForApproval` | 审批策略枚举 |
| `protocol/src/protocol.rs:719-784` | `SandboxPolicy` | 沙盒策略枚举 |
| `protocol/src/protocol.rs:843-848` | `new_read_only_policy()` | 只读策略工厂方法 |
| `protocol/src/protocol.rs:853-861` | `new_workspace_write_policy()` | 工作区写入策略工厂方法 |

---

## 5. 依赖与外部交互

### 5.1 依赖关系图

```
┌─────────────────────────────────────────────────────────────┐
│                    codex-utils-approval-presets              │
│                          (本库)                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  ApprovalPreset struct                              │   │
│  │  builtin_approval_presets() -> Vec<ApprovalPreset>  │   │
│  └─────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────┘
                           │ 依赖
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    codex-protocol                            │
│  ┌─────────────────┐  ┌─────────────────────────────────┐   │
│  │ AskForApproval  │  │ SandboxPolicy                   │   │
│  │  - UnlessTrusted│  │  - DangerFullAccess             │   │
│  │  - OnRequest    │  │  - ReadOnly                     │   │
│  │  - Never        │  │  - WorkspaceWrite               │   │
│  │  - Granular     │  │  - ExternalSandbox              │   │
│  └─────────────────┘  └─────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────┘
                           │ 被使用
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  codex-tui   │  │codex-tui-app-│  │  (未来)      │
│              │  │   server     │  │  MCP server  │
└──────────────┘  └──────────────┘  └──────────────┘
```

### 5.2 Cargo.toml 依赖

```toml
[dependencies]
codex-protocol = { workspace = true }
```

### 5.3 工作空间配置

在根 `Cargo.toml` 中定义：

```toml
[workspace.dependencies]
codex-utils-approval-presets = { path = "utils/approval-presets" }
```

被以下 crate 引用：
- `codex-tui`（第 47 行）
- `codex-tui-app-server`（第 51 行）

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 风险 1：静态 ID 硬编码

**问题**：预设 ID（"read-only", "auto", "full-access"）在代码中多处硬编码，存在拼写错误风险。

**示例**：
```rust
// tui/src/chatwidget.rs:4443
let Some(preset) = builtin_approval_presets()
    .into_iter()
    .find(|preset| preset.id == "auto")  // 硬编码
```

**建议**：定义常量：
```rust
pub const PRESET_ID_READ_ONLY: &str = "read-only";
pub const PRESET_ID_AUTO: &str = "auto";
pub const PRESET_ID_FULL_ACCESS: &str = "full-access";
```

#### 风险 2：无序列化支持

**问题**：`ApprovalPreset` 未实现 `Serialize`/`Deserialize`，无法直接用于配置文件或网络传输。

**影响**：调用方需要自行封装或转换。

**建议**：添加可选的序列化支持（通过 feature flag）：
```rust
#[cfg(feature = "serde")]
use serde::{Serialize, Deserialize};

#[derive(Debug, Clone)]
#[cfg_attr(feature = "serde", derive(Serialize, Deserialize))]
pub struct ApprovalPreset { ... }
```

#### 风险 3："auto" 预设的歧义

**问题**：ID 为 "auto" 但 label 为 "Default"，命名不一致可能导致混淆。

**建议**：考虑统一命名，或在文档中明确说明。

### 6.2 边界情况

#### 边界 1：预设不匹配时的回退

当用户配置与任何预设都不匹配时，TUI 不会高亮任何选项。这是预期行为，但可能让用户困惑（"我当前是什么模式？"）。

#### 边界 2：Windows 特定功能

`open_windows_sandbox_enable_prompt` 等函数在非 Windows 平台是空实现（`#[cfg(not(target_os = "windows"))]`），这通过条件编译正确处理。

#### 边界 3：细粒度审批配置

`AskForApproval::Granular` 允许细粒度控制，但当前预设系统未涵盖这种复杂配置，用户只能选择三种预设之一。

### 6.3 改进建议

#### 建议 1：添加预设查找辅助函数

```rust
impl ApprovalPreset {
    pub fn by_id(id: &str) -> Option<&'static Self> {
        builtin_approval_presets()
            .into_iter()
            .find(|p| p.id == id)
    }
    
    pub fn auto() -> &'static Self {
        Self::by_id(PRESET_ID_AUTO).expect("auto preset exists")
    }
}
```

#### 建议 2：支持自定义预设

未来可考虑从配置文件加载额外预设：

```rust
pub fn load_presets_from_config(config: &Config) -> Vec<ApprovalPreset> {
    let mut presets = builtin_approval_presets();
    if let Some(custom) = config.custom_presets {
        presets.extend(custom);
    }
    presets
}
```

#### 建议 3：添加安全等级评级

```rust
pub enum SafetyLevel {
    Safe,      // read-only
    Normal,    // auto
    Dangerous, // full-access
}

impl ApprovalPreset {
    pub fn safety_level(&self) -> SafetyLevel {
        match self.id {
            "read-only" => SafetyLevel::Safe,
            "auto" => SafetyLevel::Normal,
            "full-access" => SafetyLevel::Dangerous,
            _ => SafetyLevel::Normal,
        }
    }
}
```

#### 建议 4：国际化支持

当前 label 和 description 是硬编码的英文。未来可考虑：
- 使用 `fluent` 或类似框架支持多语言
- 或至少将显示文本提取到常量，便于调用方覆盖

### 6.4 测试覆盖

当前测试主要分布在调用方（`tui/src/chatwidget/tests.rs`），建议在本库添加单元测试：

```rust
#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_all_presets_have_unique_ids() {
        let presets = builtin_approval_presets();
        let ids: Vec<_> = presets.iter().map(|p| p.id).collect();
        let unique_ids: std::collections::HashSet<_> = ids.iter().cloned().collect();
        assert_eq!(ids.len(), unique_ids.len());
    }
    
    #[test]
    fn test_full_access_is_dangerous() {
        let preset = builtin_approval_presets()
            .into_iter()
            .find(|p| p.id == "full-access")
            .unwrap();
        assert!(matches!(preset.sandbox, SandboxPolicy::DangerFullAccess));
        assert!(matches!(preset.approval, AskForApproval::Never));
    }
}
```

---

## 7. 总结

`codex-utils-approval-presets` 是一个小而精的工具库，成功地将权限预设的定义与使用分离。其设计简洁、职责清晰，通过静态数据避免了运行时开销。主要改进空间在于：

1. **消除魔法字符串**：将硬编码 ID 提取为常量
2. **增强类型安全**：考虑使用枚举替代字符串 ID
3. **扩展功能**：支持自定义预设、安全等级提示
4. **完善测试**：添加本库级别的单元测试

该库在 Codex 项目的安全模型中扮演重要角色，是连接底层权限系统（`codex-protocol`）和用户界面（`codex-tui`）的关键桥梁。
