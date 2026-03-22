# codex-rs/utils/sandbox-summary 深度研究文档

## 1. 场景与职责

### 1.1 组件定位

`sandbox-summary` 是 Codex CLI 项目中一个**工具类 crate**（utility crate），位于 `codex-rs/utils/sandbox-summary`。其核心职责是：

1. **配置摘要生成**：将复杂的 `Config` 对象转换为人类可读的键值对列表
2. **沙箱策略可视化**：将 `SandboxPolicy` 枚举转换为简洁的字符串描述

### 1.2 使用场景

该 crate 被以下三个主要调用方使用：

| 调用方 | 文件路径 | 使用方式 |
|--------|----------|----------|
| `codex-exec` | `exec/src/event_processor_with_human_output.rs` | `create_config_summary_entries()` 用于 CLI 启动时打印配置摘要 |
| `codex-tui` | `tui/src/status/card.rs` | `summarize_sandbox_policy()` 用于 TUI 状态卡片显示沙箱配置 |
| `codex-tui-app-server` | `tui_app_server/src/status/card.rs` | `summarize_sandbox_policy()` 用于 app-server 模式下的状态显示 |

### 1.3 设计目的

- **关注点分离**：将配置格式化逻辑从 UI/CLI 代码中抽离，保持单一职责
- **可复用性**：多个前端（CLI、TUI、App Server）共享同一套配置摘要逻辑
- **可测试性**：独立的 crate 便于单元测试，确保格式化输出的一致性

---

## 2. 功能点目的

### 2.1 模块结构

```
codex-rs/utils/sandbox-summary/src/
├── lib.rs              # 模块入口，导出两个公共函数
├── config_summary.rs   # 配置摘要生成（create_config_summary_entries）
└── sandbox_summary.rs  # 沙箱策略摘要（summarize_sandbox_policy）
```

### 2.2 核心功能

#### 2.2.1 `create_config_summary_entries`

**功能**：构建配置键值对列表，用于向用户展示当前会话的有效配置。

**输出字段**：
- `workdir`: 当前工作目录
- `model`: 使用的 AI 模型
- `provider`: 模型提供商 ID
- `approval`: 命令审批策略（如 `on-request`, `never` 等）
- `sandbox`: 沙箱策略摘要（调用 `summarize_sandbox_policy`）
- `reasoning effort`: 推理努力程度（仅 Responses API）
- `reasoning summaries`: 推理摘要设置（仅 Responses API）

#### 2.2.2 `summarize_sandbox_policy`

**功能**：将 `SandboxPolicy` 枚举转换为人类可读的字符串描述。

**支持的策略类型**：

| 策略类型 | 输出示例 |
|----------|----------|
| `DangerFullAccess` | `danger-full-access` |
| `ReadOnly` | `read-only` 或 `read-only (network access enabled)` |
| `ExternalSandbox` | `external-sandbox` 或 `external-sandbox (network access enabled)` |
| `WorkspaceWrite` | `workspace-write [workdir, /tmp, $TMPDIR, /custom/path] (network access enabled)` |

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 依赖的核心类型

```rust
// 来自 codex_protocol::protocol
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

pub enum NetworkAccess {
    Restricted,
    Enabled,
}

pub enum ReadOnlyAccess {
    FullAccess,
    Restricted { include_platform_defaults: bool, readable_roots: Vec<AbsolutePathBuf> },
}
```

#### 3.1.2 配置结构

```rust
// 来自 codex_core::config::Config
pub struct Config {
    pub cwd: PathBuf,
    pub model_provider_id: String,
    pub model_provider: ModelProviderInfo,
    pub permissions: Permissions,
    pub model_reasoning_effort: Option<ReasoningEffort>,
    pub model_reasoning_summary: Option<ReasoningSummary>,
    // ... 其他字段
}

pub struct Permissions {
    pub approval_policy: Constrained<AskForApproval>,
    pub sandbox_policy: Constrained<SandboxPolicy>,
    // ... 其他字段
}
```

### 3.2 关键流程

#### 3.2.1 配置摘要生成流程

```
Config + model_name
    ↓
create_config_summary_entries()
    ↓
构建基础 entries 向量
    ↓
添加 sandbox 摘要（调用 summarize_sandbox_policy）
    ↓
根据 WireApi 类型条件添加 reasoning 相关字段
    ↓
返回 Vec<(&'static str, String)>
```

#### 3.2.2 沙箱策略摘要流程

```
SandboxPolicy
    ↓
match 枚举变体
    ↓
DangerFullAccess → "danger-full-access"
ReadOnly → "read-only" + 可选网络后缀
ExternalSandbox → "external-sandbox" + 可选网络后缀
WorkspaceWrite → "workspace-write [可写路径列表]" + 可选网络后缀
```

### 3.3 代码实现细节

#### 3.3.1 `config_summary.rs`

```rust
pub fn create_config_summary_entries(config: &Config, model: &str) -> Vec<(&'static str, String)> {
    let mut entries = vec![
        ("workdir", config.cwd.display().to_string()),
        ("model", model.to_string()),
        ("provider", config.model_provider_id.clone()),
        ("approval", config.permissions.approval_policy.value().to_string()),
        ("sandbox", summarize_sandbox_policy(config.permissions.sandbox_policy.get())),
    ];
    
    // 条件添加 reasoning 字段
    if config.model_provider.wire_api == WireApi::Responses {
        // 添加 reasoning effort 和 reasoning summaries
    }
    
    entries
}
```

#### 3.3.2 `sandbox_summary.rs`

```rust
pub fn summarize_sandbox_policy(sandbox_policy: &SandboxPolicy) -> String {
    match sandbox_policy {
        SandboxPolicy::DangerFullAccess => "danger-full-access".to_string(),
        SandboxPolicy::ReadOnly { network_access, .. } => {
            let mut summary = "read-only".to_string();
            if *network_access { summary.push_str(" (network access enabled)"); }
            summary
        }
        SandboxPolicy::ExternalSandbox { network_access } => {
            let mut summary = "external-sandbox".to_string();
            if matches!(network_access, NetworkAccess::Enabled) {
                summary.push_str(" (network access enabled)");
            }
            summary
        }
        SandboxPolicy::WorkspaceWrite { writable_roots, network_access, exclude_tmpdir_env_var, exclude_slash_tmp, .. } => {
            let mut summary = "workspace-write".to_string();
            let mut writable_entries = Vec::new();
            
            // 构建可写路径列表
            writable_entries.push("workdir".to_string());
            if !*exclude_slash_tmp { writable_entries.push("/tmp".to_string()); }
            if !*exclude_tmpdir_env_var { writable_entries.push("$TMPDIR".to_string()); }
            writable_entries.extend(writable_roots.iter().map(|p| p.to_string_lossy().to_string()));
            
            summary.push_str(&format!(" [{}]", writable_entries.join(", ")));
            if *network_access { summary.push_str(" (network access enabled)"); }
            summary
        }
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 本 crate 内文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/lib.rs` | 5 | 模块入口，导出公共 API |
| `src/config_summary.rs` | 39 | 配置摘要生成实现 |
| `src/sandbox_summary.rs` | 103 | 沙箱策略摘要实现（含测试） |
| `Cargo.toml` | 16 | 依赖声明 |
| `BUILD.bazel` | 6 | Bazel 构建配置 |

### 4.2 调用方代码路径

#### 4.2.1 codex-exec

**文件**: `codex-rs/exec/src/event_processor_with_human_output.rs`

```rust
// 第 60 行：导入
use codex_utils_sandbox_summary::create_config_summary_entries;

// 第 194-195 行：使用
let mut entries = create_config_summary_entries(config, session_configured_event.model.as_str());
entries.push(("session id", session_configured_event.session_id.to_string()));

// 第 201-203 行：输出
for (key, value) in entries {
    eprintln!("{} {}", format!("{key}:").style(self.bold), value);
}
```

**上下文**: `print_config_summary` 方法在会话启动时打印配置摘要，镜像 TUI 欢迎屏幕的信息。

#### 4.2.2 codex-tui

**文件**: `codex-rs/tui/src/status/card.rs`

```rust
// 第 18 行：导入
use codex_utils_sandbox_summary::summarize_sandbox_policy;

// 第 176-178 行：使用
(
    "sandbox",
    summarize_sandbox_policy(config.permissions.sandbox_policy.get()),
),
```

**上下文**: `StatusHistoryCell::new` 方法构建状态卡片时，将沙箱策略作为配置项之一显示。

#### 4.2.3 codex-tui-app-server

**文件**: `codex-rs/tui_app_server/src/status/card.rs`

```rust
// 第 18 行：导入
use codex_utils_sandbox_summary::summarize_sandbox_policy;

// 第 175-177 行：使用
(
    "sandbox",
    summarize_sandbox_summary(config.permissions.sandbox_policy.get()),
),
```

**注意**: 与 `codex-tui` 的实现几乎完全一致，遵循 AGENTS.md 中"平行实现"的约定。

### 4.3 依赖类型定义路径

| 类型 | 定义位置 |
|------|----------|
| `SandboxPolicy` | `codex-rs/protocol/src/protocol.rs` (第 718-784 行) |
| `NetworkAccess` | `codex-rs/protocol/src/protocol.rs` (第 631-646 行) |
| `ReadOnlyAccess` | `codex-rs/protocol/src/protocol.rs` (第 653-716 行) |
| `Config` | `codex-rs/core/src/config/mod.rs` (第 232-591 行) |
| `Permissions` | `codex-rs/core/src/config/mod.rs` (第 195-228 行) |
| `AbsolutePathBuf` | `codex-rs/utils/absolute-path/src/lib.rs` |

---

## 5. 依赖与外部交互

### 5.1 依赖关系图

```
codex-utils-sandbox-summary
    ├── codex-core (workspace)
    │   └── 提供 Config, Permissions, WireApi 等类型
    ├── codex-protocol (workspace)
    │   └── 提供 SandboxPolicy, NetworkAccess, ReadOnlyAccess 等类型
    ├── codex-utils-absolute-path (dev-dependency)
    │   └── 测试中使用 AbsolutePathBuf
    └── pretty_assertions (dev-dependency)
        └── 测试断言增强
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

### 5.3 反向依赖

在 workspace 中被以下 crate 依赖：

```toml
# codex-rs/exec/Cargo.toml
codex-utils-sandbox-summary = { workspace = true }

# codex-rs/tui/Cargo.toml
codex-utils-sandbox-summary = { workspace = true }

# codex-rs/tui_app_server/Cargo.toml
codex-utils-sandbox-summary = { workspace = true }
```

### 5.4 与沙箱执行系统的关系

虽然 `sandbox-summary` 本身只负责**显示**沙箱配置，但它依赖的类型与实际的沙箱执行系统紧密相关：

- **Seatbelt** (macOS): `codex-rs/core/src/seatbelt.rs`
- **Landlock** (Linux): `codex-rs/core/src/landlock.rs`
- **Windows Sandbox**: `codex-rs/core/src/windows_sandbox.rs`
- **Bubblewrap**: `codex-rs/linux-sandbox/`

这些模块使用 `SandboxPolicy` 来决定如何配置实际的系统级沙箱。

---

## 6. 风险、边界与改进建议

### 6.1 当前风险与边界

#### 6.1.1 功能边界

1. **只读职责**：该 crate 仅负责格式化显示，不参与实际的沙箱决策或执行
2. **字符串硬编码**：沙箱策略名称（如 `"danger-full-access"`）是硬编码的，与 `SandboxPolicy` 的 serde 序列化名称需要手动保持一致
3. **平台差异处理**：`WorkspaceWrite` 的路径显示在 Windows 和 Unix 上可能有不同表现（测试代码中使用了条件编译 `cfg!(windows)`）

#### 6.1.2 潜在风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 命名不一致 | `SandboxPolicy` 的 Display/serde 实现与 summarize 函数返回的字符串可能不一致 | 测试覆盖，代码审查 |
| 路径泄露 | `WorkspaceWrite` 会显示完整路径，可能包含敏感信息 | 调用方负责脱敏 |
| 网络状态误判 | `ExternalSandbox` 使用 `NetworkAccess` 枚举，与其他策略使用 `bool` 不同 | 已实现正确的 match 处理 |

### 6.2 测试覆盖

当前测试位于 `sandbox_summary.rs` 的 `#[cfg(test)]` 模块：

```rust
#[test]
fn summarizes_external_sandbox_without_network_access_suffix() { ... }

#[test]
fn summarizes_external_sandbox_with_enabled_network() { ... }

#[test]
fn summarizes_read_only_with_enabled_network() { ... }

#[test]
fn workspace_write_summary_still_includes_network_access() { ... }
```

**测试缺口**：
- 没有 `DangerFullAccess` 的测试
- 没有 `ReadOnly` 不带网络访问的测试
- 没有 `WorkspaceWrite` 排除 `/tmp` 和 `$TMPDIR` 的测试
- 没有 `config_summary.rs` 的单元测试

### 6.3 改进建议

#### 6.3.1 短期改进

1. **增加测试覆盖**
   ```rust
   // 建议添加的测试
   #[test]
   fn summarizes_danger_full_access() { ... }
   
   #[test]
   fn summarizes_workspace_write_with_exclusions() { ... }
   ```

2. **统一网络访问显示逻辑**
   当前 `ReadOnly` 和 `WorkspaceWrite` 使用 `bool`，而 `ExternalSandbox` 使用 `NetworkAccess` 枚举，建议统一。

3. **添加文档注释**
   为 `create_config_summary_entries` 和 `summarize_sandbox_policy` 添加更详细的 rustdoc 注释，说明输出格式和用途。

#### 6.3.2 中期改进

1. **国际化支持**
   当前输出字符串是硬编码的英文，未来如需支持多语言，可考虑使用 `i18n` 框架。

2. **结构化输出**
   除了字符串摘要，可考虑提供结构化数据（如 JSON），便于下游工具解析。

3. **与 serde 名称同步检查**
   考虑使用编译时检查或测试确保 `summarize_sandbox_policy` 返回的名称与 `SandboxPolicy` 的 serde 序列化名称一致。

#### 6.3.3 架构思考

1. **职责扩展**
   如果未来需要更复杂的配置格式化（如颜色高亮、表格布局），可考虑：
   - 引入模板引擎（如 `askama`）
   - 或返回结构化数据让调用方自行格式化

2. **与配置验证的集成**
   当前 crate 假设输入的 `Config` 和 `SandboxPolicy` 是有效的。如果未来需要在显示时进行验证或警告，可考虑与 `codex-config` 集成。

---

## 7. 附录

### 7.1 相关文档

- `AGENTS.md`: 项目级代理开发指南
- `codex-rs/tui/styles.md`: TUI 样式规范
- `codex-rs/protocol/src/protocol.rs`: 协议定义
- `codex-rs/core/src/config/mod.rs`: 配置系统实现

### 7.2 变更历史注意事项

根据 `AGENTS.md`，修改本 crate 后需要：

1. 运行 `just fmt` 格式化代码
2. 运行 `cargo test -p codex-utils-sandbox-summary` 测试
3. 如果修改了依赖，运行 `just bazel-lock-update`
4. TUI 相关变更需要同步到 `tui_app_server`（本 crate 的调用方已遵循此约定）

### 7.3 调试技巧

要查看配置摘要的输出效果，可以：

```bash
# 运行 CLI 查看启动时的配置摘要
cargo run -p codex-cli -- --help

# 运行 TUI 查看状态卡片
cargo run -p codex-tui

# 在 /status 命令中查看沙箱配置
```
