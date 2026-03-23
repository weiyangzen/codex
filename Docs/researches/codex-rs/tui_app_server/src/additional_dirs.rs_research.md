# Research: codex-rs/tui_app_server/src/additional_dirs.rs

## 1. 场景与职责

### 1.1 模块定位
`additional_dirs.rs` 是 `codex-tui-app-server` crate 中的一个小型工具模块，专门负责处理用户通过 CLI 参数 `--add-dir` 指定的额外可写目录（additional writable directories）与沙盒策略（SandboxPolicy）之间的兼容性检查。

### 1.2 业务场景
在 Codex CLI 的使用场景中：
1. 用户可以通过 `--add-dir <DIR>` 参数指定除当前工作目录外，还允许 AI 代理写入的其他目录
2. 沙盒策略（SandboxPolicy）决定了 AI 代理的文件系统访问权限，包括：
   - `ReadOnly`：只读访问
   - `WorkspaceWrite`：允许写入工作目录和指定的额外目录
   - `DangerFullAccess`：完全访问（无限制）
   - `ExternalSandbox`：依赖外部沙盒

3. 当用户指定了 `--add-dir` 但沙盒策略为 `ReadOnly` 时，这些额外目录参数实际上会被忽略，因为只读模式下不允许任何写入操作

### 1.3 核心职责
该模块的核心职责是：
- **检测冲突**：识别用户输入的 `--add-dir` 参数与当前沙盒策略之间的冲突
- **生成警告**：当检测到冲突时，生成用户友好的警告信息
- **提前退出**：在 TUI 启动前拦截配置错误，避免用户在不知情的情况下运行受限会话

---

## 2. 功能点目的

### 2.1 主要功能

| 功能 | 描述 |
|------|------|
| `add_dir_warning_message()` | 公共 API，检查额外目录与沙盒策略的兼容性，返回可选的警告消息 |
| `format_warning()` | 内部函数，将路径列表格式化为用户可读的警告字符串 |

### 2.2 设计意图

1. **防御性编程**：防止用户在只读沙盒模式下误以为额外目录会被写入
2. **早期失败（Fail Fast）**：在应用启动阶段就检测配置问题，而不是在运行时才发现
3. **用户教育**：通过清晰的错误消息告知用户如何修正配置（切换到 `workspace-write` 或 `danger-full-access` 模式）

### 2.3 与 TUI 的集成

在 `lib.rs` 的 `run_main()` 函数中，该检查被调用：

```rust
if let Some(warning) =
    add_dir_warning_message(&cli.add_dir, config.permissions.sandbox_policy.get())
{
    eprintln!("Error adding directories: {warning}");
    std::process::exit(1);
}
```

这意味着如果用户运行：
```bash
codex --add-dir /tmp/writable --sandbox read-only
```
程序会立即退出并显示错误消息，而不是以只读模式静默运行。

---

## 3. 具体技术实现

### 3.1 数据结构

```rust
// 输入参数
additional_dirs: &[PathBuf]  // 用户指定的额外目录列表
sandbox_policy: &SandboxPolicy // 解析后的沙盒策略
```

### 3.2 核心算法

```rust
pub fn add_dir_warning_message(
    additional_dirs: &[PathBuf],
    sandbox_policy: &SandboxPolicy,
) -> Option<String> {
    // 快速路径：如果没有指定额外目录，无需检查
    if additional_dirs.is_empty() {
        return None;
    }

    match sandbox_policy {
        // 以下策略支持额外写入目录，返回 None（无警告）
        SandboxPolicy::WorkspaceWrite { .. }
        | SandboxPolicy::DangerFullAccess
        | SandboxPolicy::ExternalSandbox { .. } => None,
        
        // 只读策略不支持额外写入，生成警告
        SandboxPolicy::ReadOnly { .. } => Some(format_warning(additional_dirs)),
    }
}
```

### 3.3 警告消息格式

```rust
fn format_warning(additional_dirs: &[PathBuf]) -> String {
    let joined_paths = additional_dirs
        .iter()
        .map(|path| path.to_string_lossy())  // 处理非 UTF-8 路径
        .collect::<Vec<_>>()
        .join(", ");
    
    format!(
        "Ignoring --add-dir ({joined_paths}) because the effective sandbox mode is read-only. \
         Switch to workspace-write or danger-full-access to allow additional writable roots."
    )
}
```

### 3.4 协议依赖

该模块依赖 `codex_protocol::protocol::SandboxPolicy` 枚举：

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

---

## 4. 关键代码路径与文件引用

### 4.1 调用链

```
CLI 解析 (cli.rs)
    ↓
lib.rs:run_main()
    ↓
Config 构建 (加载 sandbox_policy)
    ↓
add_dir_warning_message(&cli.add_dir, sandbox_policy) [additional_dirs.rs]
    ↓
如果返回 Some(warning) → 打印错误并退出
如果返回 None → 继续启动 TUI
```

### 4.2 相关文件

| 文件路径 | 关系 | 说明 |
|---------|------|------|
| `codex-rs/tui_app_server/src/additional_dirs.rs` | **本文件** | 警告逻辑实现 |
| `codex-rs/tui_app_server/src/lib.rs` | 调用方 | 在 `run_main()` 中调用检查 |
| `codex-rs/tui_app_server/src/cli.rs` | 配置源 | 定义 `--add-dir` 参数 |
| `codex-rs/protocol/src/protocol.rs` | 依赖 | 定义 `SandboxPolicy` 枚举 |
| `codex-rs/core/src/config/mod.rs` | 配置处理 | 处理 `additional_writable_roots` 的解析和应用 |
| `codex-rs/tui/src/additional_dirs.rs` | 平行实现 | TUI crate 中的相同逻辑（代码复用） |

### 4.3 配置流向

```
CLI --add-dir
    ↓
cli.add_dir: Vec<PathBuf>
    ↓
ConfigOverrides.additional_writable_roots
    ↓
Config 构建
    ↓
FileSystemSandboxPolicy (写入权限配置)
    ↓
SandboxPolicy::WorkspaceWrite.writable_roots
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖

```rust
use codex_protocol::protocol::SandboxPolicy;  // 沙盒策略定义
use std::path::PathBuf;                        // 路径处理
```

### 5.2 测试依赖

```rust
use codex_protocol::protocol::NetworkAccess;   // 测试 ExternalSandbox 变体
use pretty_assertions::assert_eq;              // 测试断言
```

### 5.3 与 Core Config 的交互

在 `core/src/config/mod.rs` 中，`additional_writable_roots` 被实际应用到沙盒策略：

```rust
if let SandboxPolicy::WorkspaceWrite { writable_roots, .. } = &mut sandbox_policy {
    for path in &additional_writable_roots {
        if !writable_roots.iter().any(|existing| existing == path) {
            writable_roots.push(path.clone());
        }
    }
}
```

这说明 `additional_dirs.rs` 只是**前置检查**，真正的权限配置在 Core 层完成。

### 5.4 与 TUI 的平行关系

`codex-rs/tui/src/additional_dirs.rs` 包含完全相同的代码，说明：
- 两个 crate（`tui` 和 `tui_app_server`）都独立使用此逻辑
- 这是有意的设计，保持两个 TUI 变体的行为一致性
- 根据 `AGENTS.md` 的约定："When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change..."

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

| 风险点 | 描述 | 严重程度 |
|--------|------|---------|
| 硬编码错误消息 | 警告消息中的 `--add-dir` 和模式名称是硬编码的，如果 CLI 参数更名会不一致 | 低 |
| 进程退出 | 检测到冲突时直接 `exit(1)`，可能不利于程序化使用 | 低 |
| 重复代码 | 与 `tui/src/additional_dirs.rs` 代码重复 | 中 |

### 6.2 边界情况

1. **空目录列表**：`additional_dirs.is_empty()` 时快速返回 `None`，不生成警告
2. **非 UTF-8 路径**：使用 `to_string_lossy()` 处理，可能丢失部分信息但保证不 panic
3. **相对路径**：路径格式保持原样，不做规范化处理
4. **并发安全**：纯函数，无状态，线程安全

### 6.3 改进建议

#### 6.3.1 代码重构
```rust
// 建议：使用常量定义参数名，避免硬编码
const ADD_DIR_ARG_NAME: &str = "--add-dir";
const WORKSPACE_WRITE_MODE: &str = "workspace-write";
const DANGER_MODE: &str = "danger-full-access";
```

#### 6.3.2 错误处理改进
考虑将错误处理从直接 `exit(1)` 改为返回 `Result`，让调用方决定如何处理：

```rust
pub enum AddDirCheckResult {
    Ok,
    Ignored { paths: Vec<PathBuf>, reason: String },
}
```

#### 6.3.3 代码复用
考虑将公共逻辑提取到 `codex-utils-cli` 或类似 crate，避免两个 TUI 实现之间的重复。

#### 6.3.4 增强诊断
可以添加更多上下文信息到警告中：
- 当前有效的沙盒策略名称
- 建议的确切命令行参数
- 相关文档链接

### 6.4 测试覆盖

当前测试覆盖良好，包括：
- `returns_none_for_workspace_write`：确认 WorkspaceWrite 模式无警告
- `returns_none_for_danger_full_access`：确认 DangerFullAccess 模式无警告
- `returns_none_for_external_sandbox`：确认 ExternalSandbox 模式无警告
- `warns_for_read_only`：确认 ReadOnly 模式生成正确警告
- `returns_none_when_no_additional_dirs`：确认空列表无警告

### 6.5 维护建议

1. **同步更新**：修改此文件时，务必同步检查 `tui/src/additional_dirs.rs`
2. **文档同步**：如果修改错误消息，更新用户文档中的相关说明
3. **向后兼容**：`SandboxPolicy` 枚举的变体变化会影响此模块，需要同步更新

---

## 7. 总结

`additional_dirs.rs` 是一个小而精的防御性模块，虽然代码量仅约 80 行，但在用户体验和配置正确性方面扮演重要角色。它通过早期检测和清晰的错误消息，防止用户在只读沙盒模式下误以为额外目录可写，从而避免潜在的困惑和数据丢失风险。

该模块的设计体现了以下原则：
- **Fail Fast**：尽早发现问题
- **清晰沟通**：提供可操作的错误消息
- **最小侵入**：纯函数设计，无副作用（除测试外）
- **一致性**：两个 TUI crate 保持相同行为
