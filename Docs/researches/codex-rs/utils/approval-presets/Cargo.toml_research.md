# Cargo.toml 研究文档

## 文件信息

- **文件路径**: `codex-rs/utils/approval-presets/Cargo.toml`
- **文件大小**: 203 bytes
- **所属 Crate**: `codex-utils-approval-presets`
- **Crate 类型**: Library（库 crate）

## 场景与职责

### 1.1 定位与用途

此 Cargo.toml 文件定义了 `codex-utils-approval-presets` crate 的包元数据和依赖关系。该 crate 是 Codex 项目权限系统的核心组件之一，专门提供预定义的权限审批策略组合（Approval Presets），供 TUI 和 TUI App Server 共享使用。

### 1.2 设计意图

- **权限策略抽象**：将审批策略（AskForApproval）和沙盒策略（SandboxPolicy）绑定为可复用的预设单元
- **跨模块复用**：通过独立的 utility crate，确保 TUI 和 App Server 使用完全一致的权限定义
- **零运行时开销**：纯静态数据结构，无运行时分配（使用 `&'static str`）

### 1.3 使用场景

1. **权限设置弹窗**：用户在 TUI 中选择权限模式（Read Only / Default / Full Access）
2. **Windows 沙盒启用流程**：自动选择 "auto" 预设进行配置
3. **降级模式处理**：从 full-access 降级时恢复到 "auto" 预设
4. **测试验证**：快照测试中使用预设验证 UI 行为

## 功能点目的

### 2.1 包元数据配置

```toml
[package]
name = "codex-utils-approval-presets"
version.workspace = true
edition.workspace = true
license.workspace = true
```

| 字段 | 值 | 说明 |
|------|-----|------|
| `name` | `codex-utils-approval-presets` | 遵循项目命名规范：`codex-utils-*` |
| `version.workspace` | `true` | 继承工作区版本号，确保所有 crate 版本一致 |
| `edition.workspace` | `true` | 继承工作区 Rust 版本（通常是 2021 edition） |
| `license.workspace` | `true` | 继承工作区许可证配置 |

### 2.2 Lint 配置

```toml
[lints]
workspace = true
```

继承工作区级别的 lint 配置，确保代码风格和质量标准一致。

### 2.3 依赖配置

```toml
[dependencies]
codex-protocol = { workspace = true }
```

| 依赖 | 来源 | 用途 |
|------|------|------|
| `codex-protocol` | workspace | 提供 `AskForApproval` 和 `SandboxPolicy` 类型定义 |

## 具体技术实现

### 3.1 依赖解析

`codex-protocol` 是关键依赖，提供了以下核心类型：

```rust
// 来自 codex-protocol/src/protocol.rs

/// 审批策略枚举
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize, Display, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum AskForApproval {
    #[default]
    OnRequest,           // 按需询问（默认）
    UnlessTrusted,       // 除非可信
    OnFailure,           // 失败时（已废弃）
    Granular(GranularApprovalConfig),  // 细粒度控制
    Never,               // 从不询问
}

/// 沙盒策略枚举
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Display, JsonSchema, TS)]
#[strum(serialize_all = "kebab-case")]
#[serde(tag = "type", rename_all = "kebab-case")]
pub enum SandboxPolicy {
    #[serde(rename = "danger-full-access")]
    DangerFullAccess,    // 完全访问（危险）
    
    #[serde(rename = "read-only")]
    ReadOnly {           // 只读模式
        access: ReadOnlyAccess,
        network_access: bool,
    },
    
    #[serde(rename = "external-sandbox")]
    ExternalSandbox {    // 外部沙盒
        network_access: NetworkAccess,
    },
    
    #[serde(rename = "workspace-write")]
    WorkspaceWrite {     // 工作区可写
        writable_roots: Vec<AbsolutePathBuf>,
        read_only_access: ReadOnlyAccess,
        network_access: bool,
        exclude_tmpdir_env_var: bool,
        exclude_slash_tmp: bool,
    },
}
```

### 3.2 本 crate 提供的核心类型

```rust
// src/lib.rs

/// 审批预设结构体
#[derive(Debug, Clone)]
pub struct ApprovalPreset {
    /// 稳定标识符（如 "read-only", "auto", "full-access"）
    pub id: &'static str,
    /// UI 显示标签（如 "Read Only", "Default", "Full Access"）
    pub label: &'static str,
    /// 简短描述，显示在 UI 中
    pub description: &'static str,
    /// 审批策略
    pub approval: AskForApproval,
    /// 沙盒策略
    pub sandbox: SandboxPolicy,
}

/// 返回内置审批预设列表
pub fn builtin_approval_presets() -> Vec<ApprovalPreset>
```

### 3.3 三种内置预设

| 预设 ID | 标签 | 审批策略 | 沙盒策略 | 描述 |
|---------|------|----------|----------|------|
| `read-only` | Read Only | `OnRequest` | `new_read_only_policy()` | 只读文件，编辑和网络需审批 |
| `auto` | Default | `OnRequest` | `new_workspace_write_policy()` | 可读写工作区，网络和外部文件需审批 |
| `full-access` | Full Access | `Never` | `DangerFullAccess` | 完全访问，无需审批 |

## 关键代码路径与文件引用

### 4.1 当前目录文件

| 文件 | 行数 | 说明 |
|------|------|------|
| `src/lib.rs` | 46 | 实现 `ApprovalPreset` 结构体和 `builtin_approval_presets()` |
| `BUILD.bazel` | 6 | Bazel 构建配置 |

### 4.2 上游依赖（被依赖方）

| 文件 | 用途 |
|------|------|
| `codex-rs/protocol/src/protocol.rs` | 定义 `AskForApproval` 和 `SandboxPolicy` |
| `codex-rs/protocol/src/permissions.rs` | 定义 `SandboxPolicy` 的详细实现 |

### 4.3 下游消费者（调用方）

#### TUI 模块 (`codex-rs/tui/`)

| 文件 | 引用行 | 用途 |
|------|--------|------|
| `src/chatwidget.rs` | 306-307 | 导入 `ApprovalPreset` 和 `builtin_approval_presets` |
| `src/chatwidget.rs` | 7058 | 权限弹窗中遍历预设列表 |
| `src/chatwidget.rs` | 4443-4453 | 降级模式命令处理，查找 "auto" 预设 |
| `src/chatwidget.rs` | 7774-7783 | Windows 沙盒启用提示，查找 "auto" 预设 |
| `src/app_event.rs` | 19 | 导入 `ApprovalPreset` 类型 |
| `src/app_event.rs` | 245-304 | 多个事件变体使用 `ApprovalPreset`（FullAccessConfirmation, WindowsSandboxEnablePrompt 等） |
| `src/chatwidget/tests.rs` | 125 | 测试中使用 `builtin_approval_presets` |

#### TUI App Server 模块 (`codex-rs/tui_app_server/`)

| 文件 | 引用行 | 用途 |
|------|--------|------|
| `src/chatwidget.rs` | 347-348 | 导入 `ApprovalPreset` 和 `builtin_approval_presets` |
| `src/chatwidget.rs` | 8134 | 权限弹窗中遍历预设列表 |
| `src/chatwidget.rs` | 4676-4686 | 降级模式命令处理 |
| `src/chatwidget.rs` | 8853-8863 | Windows 沙盒启用提示 |
| `src/app_event.rs` | 21 | 导入 `ApprovalPreset` 类型 |
| `src/app_event.rs` | 254-317 | 多个事件变体使用 `ApprovalPreset` |
| `src/chatwidget/tests.rs` | 148 | 测试中使用 `builtin_approval_presets` |

### 4.4 调用链示例

```
用户点击权限设置
    ↓
ChatWidget::open_permissions_popup()
    ↓
builtin_approval_presets() → Vec<ApprovalPreset>
    ↓
遍历预设，创建 SelectionItem
    ↓
用户选择预设
    ↓
根据预设 ID 决定行为：
    - "full-access" → OpenFullAccessConfirmation
    - 其他 → 直接应用 approval + sandbox 策略
```

## 依赖与外部交互

### 5.1 编译时依赖图

```
codex-utils-approval-presets
├── codex-protocol
│   ├── serde (序列化)
│   ├── schemars (JSON Schema)
│   ├── ts-rs (TypeScript 生成)
│   └── strum (枚举工具)
└── (无其他直接依赖)
```

### 5.2 运行时数据流

```
┌─────────────────────────────────────────────────────────────┐
│                    builtin_approval_presets()                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  read-only  │  │    auto     │  │     full-access     │  │
│  │  preset     │  │   preset    │  │       preset        │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
└─────────┼────────────────┼────────────────────┼─────────────┘
          │                │                    │
          ▼                ▼                    ▼
   ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐
   │ AskForApproval│ │ AskForApproval│ │  AskForApproval  │
   │  OnRequest    │ │  OnRequest    │ │     Never        │
   └──────┬───────┘ └──────┬───────┘ └────────┬─────────┘
          │                │                    │
          ▼                ▼                    ▼
   ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐
   │SandboxPolicy │ │SandboxPolicy │ │  SandboxPolicy   │
   │ ReadOnly     │ │WorkspaceWrite│ │ DangerFullAccess │
   └──────────────┘ └──────────────┘ └──────────────────┘
```

### 5.3 与调用方的交互模式

1. **遍历模式**：获取所有预设用于 UI 列表展示
   ```rust
   let presets: Vec<ApprovalPreset> = builtin_approval_presets();
   for preset in presets { /* 创建 UI 选项 */ }
   ```

2. **查找模式**：根据 ID 查找特定预设
   ```rust
   let preset = builtin_approval_presets()
       .into_iter()
       .find(|preset| preset.id == "auto")
       .expect("auto preset must exist");
   ```

3. **匹配模式**：检查当前配置是否匹配某个预设
   ```rust
   fn preset_matches_current(
       current_approval: AskForApproval,
       current_sandbox: &SandboxPolicy,
       preset: &ApprovalPreset,
   ) -> bool { /* ... */ }
   ```

## 风险、边界与改进建议

### 6.1 潜在风险

1. **硬编码预设不可扩展**：三种预设完全硬编码，无法通过配置添加新预设
2. **字符串 ID 匹配风险**：调用方使用字符串字面量匹配（如 `"auto"`），拼写错误会导致运行时失败
3. **预设 ID 重复风险**：如果未来添加相同 ID 的预设，查找逻辑可能返回非预期结果

### 6.2 边界情况

1. **预设查找失败**：调用方使用 `.find(|p| p.id == "xxx")` 查找预设，如果 ID 不存在会返回 `None`，需要调用方正确处理
2. **跨平台行为差异**：虽然预设本身是平台无关的，但 `SandboxPolicy` 在 Windows 上有额外的配置选项（`WindowsSandboxLevel`）
3. **并发安全**：`builtin_approval_presets()` 返回 `Vec<ApprovalPreset>`，其中包含 `&'static str`，是线程安全的

### 6.3 改进建议

1. **添加预设查找辅助函数**：
   ```rust
   impl ApprovalPreset {
       pub const READ_ONLY: &'static str = "read-only";
       pub const AUTO: &'static str = "auto";
       pub const FULL_ACCESS: &'static str = "full-access";
       
       pub fn find(id: &str) -> Option<&'static Self> {
           builtin_approval_presets().iter().find(|p| p.id == id)
       }
       
       pub fn auto() -> Option<&'static Self> {
           Self::find(Self::AUTO)
       }
   }
   ```

2. **添加单元测试**：
   ```rust
   #[test]
   fn test_preset_lookup_by_id() {
       let presets = builtin_approval_presets();
       assert!(presets.iter().any(|p| p.id == "read-only"));
       assert!(presets.iter().any(|p| p.id == "auto"));
       assert!(presets.iter().any(|p| p.id == "full-access"));
   }
   
   #[test]
   fn auto_preset_must_exist() {
       assert!(builtin_approval_presets()
           .into_iter()
           .any(|p| p.id == "auto"));
   }
   
   #[test]
   fn preset_ids_are_unique() {
       let ids: Vec<_> = builtin_approval_presets()
           .into_iter()
           .map(|p| p.id)
           .collect();
       let unique: std::collections::HashSet<_> = ids.iter().cloned().collect();
       assert_eq!(ids.len(), unique.len());
   }
   ```

3. **支持配置扩展**：考虑从配置文件加载额外预设，允许用户或企业自定义权限模式

4. **文档增强**：在 Cargo.toml 中添加更详细的文档注释：
   ```toml
   [package]
   name = "codex-utils-approval-presets"
   description = "Built-in approval policy presets for Codex TUI and App Server"
   keywords = ["codex", "approval", "sandbox", "permissions"]
   ```

### 6.4 相关配置

- 工作区 Cargo.toml: `codex-rs/Cargo.toml` - 定义 workspace 级别的依赖和版本
- Bazel 配置: `BUILD.bazel` - 定义 Bazel 构建规则
- 协议定义: `codex-rs/protocol/src/protocol.rs` - `AskForApproval` 和 `SandboxPolicy` 定义
