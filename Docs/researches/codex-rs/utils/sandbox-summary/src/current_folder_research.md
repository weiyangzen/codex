# codex-rs/utils/sandbox-summary 研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 定位与目标

`sandbox-summary` 是 Codex CLI 工具链中的一个**工具类 crate**，位于 `codex-rs/utils/sandbox-summary`。它的核心职责是：

- **将复杂的沙箱策略（SandboxPolicy）转换为人类可读的摘要字符串**
- **构建配置摘要条目列表，用于 TUI 和 CLI 的状态展示**

该 crate 作为**表现层（Presentation Layer）**的辅助工具，将底层的权限配置转化为用户友好的文本描述。

### 1.2 使用场景

| 场景 | 调用方 | 用途 |
|------|--------|------|
| TUI 状态卡片展示 | `codex-tui/src/status/card.rs` | 在 `/status` 命令输出中显示当前沙箱策略 |
| TUI App Server 状态展示 | `codex-tui_app_server/src/status/card.rs` | 同上，TUI App Server 版本 |
| Exec 模式配置摘要 | `codex-exec/src/event_processor_with_human_output.rs` | 在会话开始时打印配置摘要 |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                    表现层 (Presentation)                     │
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │   codex-tui  │  │ codex-tui-app-server│  │ codex-exec   │  │
│  └──────┬───────┘  └────────┬─────────┘  └──────┬───────┘  │
│         │                   │                   │          │
│         └───────────────────┼───────────────────┘          │
│                             ▼                              │
│              ┌──────────────────────────────┐              │
│              │  codex-utils-sandbox-summary │              │
│              └──────────────┬───────────────┘              │
│                             │                              │
└─────────────────────────────┼──────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    领域层 (Domain)                          │
│              ┌──────────────────────────┐                  │
│              │    codex-protocol        │                  │
│              │  (SandboxPolicy, NetworkAccess)             │
│              └──────────────────────────┘                  │
│              ┌──────────────────────────┐                  │
│              │      codex-core          │                  │
│              │    (Config, Permissions) │                  │
│              └──────────────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 2.1 核心功能

该 crate 暴露两个主要公共 API：

#### 2.1.1 `summarize_sandbox_policy`

```rust
pub fn summarize_sandbox_policy(sandbox_policy: &SandboxPolicy) -> String
```

将 `SandboxPolicy` 枚举转换为可读的摘要字符串，支持以下策略类型：

| 策略类型 | 输出示例 |
|---------|---------|
| `DangerFullAccess` | `"danger-full-access"` |
| `ReadOnly { network_access: true }` | `"read-only (network access enabled)"` |
| `ExternalSandbox { network_access: Enabled }` | `"external-sandbox (network access enabled)"` |
| `WorkspaceWrite { writable_roots, network_access, ... }` | `"workspace-write [workdir, /tmp, $TMPDIR, /custom/path] (network access enabled)"` |

#### 2.1.2 `create_config_summary_entries`

```rust
pub fn create_config_summary_entries(config: &Config, model: &str) -> Vec<(&'static str, String)>
```

构建配置摘要键值对列表，包含：

- `workdir`: 当前工作目录
- `model`: 使用的模型名称
- `provider`: 模型提供者 ID
- `approval`: 审批策略
- `sandbox`: 沙箱策略摘要（调用 `summarize_sandbox_policy`）
- `reasoning effort`: 推理努力程度（仅 Responses API）
- `reasoning summaries`: 推理摘要设置（仅 Responses API）

### 2.2 设计意图

1. **单一职责**：将沙箱策略的格式化逻辑集中管理，避免在多个前端组件中重复实现
2. **可测试性**：独立的 crate 便于单元测试
3. **可复用性**：TUI 和 CLI 可以共享相同的格式化逻辑

---

## 具体技术实现

### 3.1 模块结构

```
codex-rs/utils/sandbox-summary/src/
├── lib.rs                    # 模块导出
├── sandbox_summary.rs        # 沙箱策略摘要核心逻辑
└── config_summary.rs         # 配置摘要条目构建
```

### 3.2 核心算法

#### 3.2.1 沙箱策略摘要算法 (`sandbox_summary.rs`)

```rust
pub fn summarize_sandbox_policy(sandbox_policy: &SandboxPolicy) -> String {
    match sandbox_policy {
        SandboxPolicy::DangerFullAccess => "danger-full-access".to_string(),
        
        SandboxPolicy::ReadOnly { network_access, .. } => {
            let mut summary = "read-only".to_string();
            if *network_access {
                summary.push_str(" (network access enabled)");
            }
            summary
        }
        
        SandboxPolicy::ExternalSandbox { network_access } => {
            let mut summary = "external-sandbox".to_string();
            if matches!(network_access, NetworkAccess::Enabled) {
                summary.push_str(" (network access enabled)");
            }
            summary
        }
        
        SandboxPolicy::WorkspaceWrite {
            writable_roots,
            network_access,
            exclude_tmpdir_env_var,
            exclude_slash_tmp,
            read_only_access: _,
        } => {
            let mut summary = "workspace-write".to_string();
            let mut writable_entries = Vec::<String>::new();
            
            // 默认包含 workdir
            writable_entries.push("workdir".to_string());
            
            // 条件性包含 /tmp
            if !*exclude_slash_tmp {
                writable_entries.push("/tmp".to_string());
            }
            
            // 条件性包含 $TMPDIR
            if !*exclude_tmpdir_env_var {
                writable_entries.push("$TMPDIR".to_string());
            }
            
            // 添加额外的可写根目录
            writable_entries.extend(
                writable_roots
                    .iter()
                    .map(|p| p.to_string_lossy().to_string()),
            );
            
            summary.push_str(&format!(" [{}]", writable_entries.join(", ")));
            
            if *network_access {
                summary.push_str(" (network access enabled)");
            }
            summary
        }
    }
}
```

#### 3.2.2 配置摘要构建算法 (`config_summary.rs`)

```rust
pub fn create_config_summary_entries(config: &Config, model: &str) -> Vec<(&'static str, String)> {
    let mut entries = vec![
        ("workdir", config.cwd.display().to_string()),
        ("model", model.to_string()),
        ("provider", config.model_provider_id.clone()),
        ("approval", config.permissions.approval_policy.value().to_string()),
        ("sandbox", summarize_sandbox_policy(config.permissions.sandbox_policy.get())),
    ];
    
    // 仅对 Responses API 添加推理相关配置
    if config.model_provider.wire_api == WireApi::Responses {
        let reasoning_effort = config
            .model_reasoning_effort
            .map(|effort| effort.to_string())
            .unwrap_or_else(|| "none".to_string());
        entries.push(("reasoning effort", reasoning_effort));
        
        let reasoning_summary = config
            .model_reasoning_summary
            .map(|summary| summary.to_string())
            .unwrap_or_else(|| "none".to_string());
        entries.push(("reasoning summaries", reasoning_summary));
    }
    
    entries
}
```

### 3.3 数据结构依赖

#### 3.3.1 SandboxPolicy（来自 codex-protocol）

```rust
pub enum SandboxPolicy {
    #[serde(rename = "danger-full-access")]
    DangerFullAccess,

    #[serde(rename = "read-only")]
    ReadOnly {
        access: ReadOnlyAccess,
        network_access: bool,
    },

    #[serde(rename = "external-sandbox")]
    ExternalSandbox {
        network_access: NetworkAccess,
    },

    #[serde(rename = "workspace-write")]
    WorkspaceWrite {
        writable_roots: Vec<AbsolutePathBuf>,
        read_only_access: ReadOnlyAccess,
        network_access: bool,
        exclude_tmpdir_env_var: bool,
        exclude_slash_tmp: bool,
    },
}
```

#### 3.3.2 NetworkAccess（来自 codex-protocol）

```rust
pub enum NetworkAccess {
    #[default]
    Restricted,
    Enabled,
}
```

### 3.4 测试覆盖

`sandbox_summary.rs` 包含完整的单元测试：

| 测试用例 | 验证内容 |
|---------|---------|
| `summarizes_external_sandbox_without_network_access_suffix` | 外部沙箱无网络访问时的格式 |
| `summarizes_external_sandbox_with_enabled_network` | 外部沙箱启用网络访问时的格式 |
| `summarizes_read_only_with_enabled_network` | 只读策略启用网络访问时的格式 |
| `workspace_write_summary_still_includes_network_access` | 工作区写入策略的完整格式 |

---

## 关键代码路径与文件引用

### 4.1 本 crate 文件

| 文件路径 | 行数 | 职责 |
|---------|------|------|
| `src/lib.rs` | 5 | 模块声明和公共 API 导出 |
| `src/sandbox_summary.rs` | 103 | 沙箱策略摘要核心实现和测试 |
| `src/config_summary.rs` | 39 | 配置摘要条目构建 |
| `Cargo.toml` | 16 | crate 元数据和依赖声明 |
| `BUILD.bazel` | 6 | Bazel 构建配置 |

### 4.2 调用方代码路径

| 调用方 | 文件路径 | 使用方式 |
|--------|---------|---------|
| codex-exec | `exec/src/event_processor_with_human_output.rs:60` | `use codex_utils_sandbox_summary::create_config_summary_entries;` |
| codex-exec | `exec/src/event_processor_with_human_output.rs:194-195` | 调用 `create_config_summary_entries` 打印配置摘要 |
| codex-tui | `tui/src/status/card.rs:18` | `use codex_utils_sandbox_summary::summarize_sandbox_policy;` |
| codex-tui | `tui/src/status/card.rs:177` | 调用 `summarize_sandbox_policy` 构建状态卡片 |
| codex-tui-app-server | `tui_app_server/src/status/card.rs:18` | `use codex_utils_sandbox_summary::summarize_sandbox_policy;` |
| codex-tui-app-server | `tui_app_server/src/status/card.rs:176` | 调用 `summarize_sandbox_policy` 构建状态卡片 |

### 4.3 依赖的协议/数据结构定义

| 定义位置 | 类型 | 用途 |
|---------|------|------|
| `protocol/src/protocol.rs:722-784` | `SandboxPolicy` | 沙箱策略枚举定义 |
| `protocol/src/protocol.rs:636-640` | `NetworkAccess` | 网络访问权限枚举 |
| `core/src/config/mod.rs:232-` | `Config` | 配置结构体 |
| `core/src/config/mod.rs:196-216` | `Permissions` | 权限配置结构体 |
| `core/src/config/mod.rs:264` | `Constrained<T>` | 带约束的值包装类型 |

---

## 依赖与外部交互

### 5.1 依赖关系图

```
codex-utils-sandbox-summary
├── 编译依赖
│   ├── codex-core (workspace)
│   │   ├── Config
│   │   ├── Permissions
│   │   └── WireApi
│   └── codex-protocol (workspace)
│       ├── SandboxPolicy
│       └── NetworkAccess
└── 测试依赖
    ├── codex-utils-absolute-path (workspace)
    └── pretty_assertions (workspace)
```

### 5.2 Cargo.toml 依赖声明

```toml
[dependencies]
codex-core = { workspace = true }
codex-protocol = { workspace = true }

[dev-dependencies]
codex-utils-absolute-path = { workspace = true }
pretty_assertions = { workspace = true }
```

### 5.3 调用方 Cargo.toml 声明

使用本 crate 的调用方都在其 `Cargo.toml` 中声明：

```toml
[dependencies]
codex-utils-sandbox-summary = { workspace = true }
```

涉及 crate：
- `codex-rs/exec/Cargo.toml:33`
- `codex-rs/tui/Cargo.toml:53`
- `codex-rs/tui_app_server/Cargo.toml:57`

### 5.4 外部接口契约

#### 输入契约

| 函数 | 输入参数 | 约束 |
|------|---------|------|
| `summarize_sandbox_policy` | `&SandboxPolicy` | 必须引用有效的 SandboxPolicy 实例 |
| `create_config_summary_entries` | `&Config, &str` | Config 必须包含有效的 permissions 和 cwd |

#### 输出契约

| 函数 | 输出 | 保证 |
|------|------|------|
| `summarize_sandbox_policy` | `String` | 非空字符串，包含策略类型和网络状态 |
| `create_config_summary_entries` | `Vec<(&'static str, String)>` | 至少包含 5 个条目（workdir, model, provider, approval, sandbox） |

---

## 风险、边界与改进建议

### 6.1 当前风险点

#### 6.1.1 代码重复风险

在 `codex-tui/src/status/card.rs` 和 `codex-tui-app_server/src/status/card.rs` 中存在**重复逻辑**：

```rust
// 两处都有类似的权限判断逻辑
let sandbox = match config.permissions.sandbox_policy.get() {
    SandboxPolicy::DangerFullAccess => "danger-full-access".to_string(),
    SandboxPolicy::ReadOnly { .. } => "read-only".to_string(),
    // ...
};
```

这与 `summarize_sandbox_policy` 的功能有重叠，但输出格式略有不同。

#### 6.1.2 扩展性风险

当新增 `SandboxPolicy` 变体时，需要修改：
1. `protocol/src/protocol.rs` - 定义新变体
2. `sandbox_summary.rs` - 添加新的摘要逻辑
3. 可能需要在 `card.rs` 中添加对应的显示逻辑

这种分散的修改点增加了遗漏风险。

#### 6.1.3 测试覆盖局限

当前测试仅覆盖 `sandbox_summary.rs`，`config_summary.rs` 没有独立测试。

### 6.2 边界情况

| 边界情况 | 当前行为 | 评估 |
|---------|---------|------|
| `writable_roots` 包含大量路径 | 全部列出，可能产生超长字符串 | 可接受，实际场景路径数量有限 |
| 路径包含非 UTF-8 字符 | 使用 `to_string_lossy()` 转换 | 可能丢失信息，但显示场景可接受 |
| `WorkspaceWrite` 排除所有默认路径 | 仅显示 `[workdir]` | 符合预期 |
| 空 `writable_roots` | 仅显示默认路径 | 符合预期 |

### 6.3 改进建议

#### 6.3.1 短期改进（低风险）

1. **为 `config_summary.rs` 添加单元测试**
   ```rust
   #[cfg(test)]
   mod tests {
       use super::*;
       use codex_core::config::ConfigBuilder;
       
       #[test]
       fn creates_basic_config_entries() {
           // 验证基本条目创建
       }
       
       #[test]
       fn includes_reasoning_for_responses_api() {
           // 验证 Responses API 的特殊处理
       }
   }
   ```

2. **统一 TUI 和 App Server 的权限显示逻辑**
   - 将 `card.rs` 中的权限判断逻辑迁移到 `sandbox-summary` crate
   - 提供新的 API：`summarize_permissions(approval_policy, sandbox_policy) -> String`

#### 6.3.2 中期改进（中等风险）

1. **支持可配置的摘要格式**
   ```rust
   pub struct SummaryOptions {
       pub include_network_status: bool,
       pub max_writable_roots: Option<usize>,
       pub path_truncation: Option<usize>,
   }
   
   pub fn summarize_sandbox_policy_with_options(
       sandbox_policy: &SandboxPolicy,
       options: &SummaryOptions,
   ) -> String
   ```

2. **国际化（i18n）支持**
   - 将硬编码的英文标签改为可配置
   - 支持 `"danger-full-access"` 等术语的本地化

#### 6.3.3 长期改进（需架构调整）

1. **与 protocol 层的更紧密集成**
   - 考虑在 `SandboxPolicy` 上实现 `Display` trait
   - 或者使用 `strum` 的 `Display` 派生宏

2. **结构化输出支持**
   - 除了字符串摘要，提供结构化数据输出
   ```rust
   pub struct SandboxSummary {
       pub policy_type: &'static str,
       pub network_access: bool,
       pub writable_paths: Vec<String>,
   }
   ```

### 6.4 维护建议

1. **文档同步**：当 `SandboxPolicy` 新增变体时，同步更新本文档的"数据结构依赖"章节
2. **变更审查**：修改摘要格式时，检查所有调用方的快照测试（insta tests）
3. **性能注意**：当前实现使用字符串拼接，对于高频调用场景（如实时状态更新），考虑使用 `fmt::Write` 减少分配

---

## 附录：完整文件清单

### A.1 本 crate 文件

```
codex-rs/utils/sandbox-summary/
├── src/
│   ├── lib.rs
│   ├── sandbox_summary.rs
│   └── config_summary.rs
├── Cargo.toml
└── BUILD.bazel
```

### A.2 相关依赖文件

```
codex-rs/protocol/src/protocol.rs          # SandboxPolicy, NetworkAccess 定义
codex-rs/core/src/config/mod.rs            # Config, Permissions 定义
codex-rs/core/src/config/profile.rs        # 配置 profile 定义
```

### A.3 调用方文件

```
codex-rs/exec/src/event_processor_with_human_output.rs
codex-rs/tui/src/status/card.rs
codex-rs/tui_app_server/src/status/card.rs
```

---

*文档生成时间：2026-03-22*
*基于 commit：当前工作目录状态*
