# sandbox_summary.rs 研究文档

## 场景与职责

`sandbox_summary.rs` 是 `codex-utils-sandbox-summary` crate 的核心实现文件，负责将 `SandboxPolicy` 枚举值转换为人类可读的字符串摘要。这个摘要在 TUI 状态栏、exec 命令行输出等位置显示，让用户快速了解当前 Codex 会话的安全沙箱配置。

## 功能点目的

1. **策略可视化**：将复杂的沙箱策略结构（包含网络访问、可写路径等多维度配置）简化为易读的字符串
2. **安全感知**：帮助用户直观识别当前会话的安全级别（如 "danger-full-access" 警示用户无沙箱保护）
3. **配置验证**：通过摘要展示，让用户确认配置是否按预期生效

## 具体技术实现

### 核心函数
```rust
pub fn summarize_sandbox_policy(sandbox_policy: &SandboxPolicy) -> String
```

该函数对四种沙箱策略进行模式匹配，生成对应的摘要字符串：

#### 1. DangerFullAccess（危险完全访问）
```rust
SandboxPolicy::DangerFullAccess => "danger-full-access".to_string()
```
- 无沙箱限制，直接返回警示性标识

#### 2. ReadOnly（只读模式）
```rust
SandboxPolicy::ReadOnly { network_access, .. } => {
    let mut summary = "read-only".to_string();
    if *network_access {
        summary.push_str(" (network access enabled)");
    }
    summary
}
```
- 基础标识为 "read-only"
- 网络访问启用时追加 "(network access enabled)"

#### 3. ExternalSandbox（外部沙箱）
```rust
SandboxPolicy::ExternalSandbox { network_access } => {
    let mut summary = "external-sandbox".to_string();
    if matches!(network_access, NetworkAccess::Enabled) {
        summary.push_str(" (network access enabled)");
    }
    summary
}
```
- 使用 `matches!` 宏检查 `NetworkAccess` 枚举值
- 注意：与 `ReadOnly` 不同，这里使用 `NetworkAccess` 枚举而非布尔值

#### 4. WorkspaceWrite（工作区写入）
最复杂的策略，需要展示可写路径列表：
```rust
SandboxPolicy::WorkspaceWrite {
    writable_roots,
    network_access,
    exclude_tmpdir_env_var,
    exclude_slash_tmp,
    read_only_access: _,
} => {
    let mut summary = "workspace-write".to_string();
    
    // 构建可写路径列表
    let mut writable_entries = Vec::<String>::new();
    writable_entries.push("workdir".to_string());  // 总是包含工作目录
    
    if !*exclude_slash_tmp {
        writable_entries.push("/tmp".to_string());
    }
    if !*exclude_tmpdir_env_var {
        writable_entries.push("$TMPDIR".to_string());
    }
    
    // 添加自定义可写根目录
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
```

### 数据结构依赖

#### SandboxPolicy（来自 codex-protocol）
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

#### NetworkAccess（来自 codex-protocol）
```rust
pub enum NetworkAccess {
    Restricted,
    Enabled,
}
```

## 关键代码路径与文件引用

- **当前文件**：`codex-rs/utils/sandbox-summary/src/sandbox_summary.rs`
- **协议定义**：`codex-rs/protocol/src/protocol.rs`（包含 `SandboxPolicy` 和 `NetworkAccess` 定义）
- **调用位置**：
  - `codex-rs/tui/src/status/card.rs:177`
  - `codex-rs/tui_app_server/src/status/card.rs:176`
  - `codex-rs/utils/sandbox-summary/src/config_summary.rs:18`

## 依赖与外部交互

### 导入依赖
```rust
use codex_protocol::protocol::NetworkAccess;
use codex_protocol::protocol::SandboxPolicy;
```

### 测试依赖
```rust
use codex_utils_absolute_path::AbsolutePathBuf;
use pretty_assertions::assert_eq;
```

### 测试覆盖
包含 4 个单元测试：

1. **`summarizes_external_sandbox_without_network_access_suffix`**
   - 验证 `ExternalSandbox` + `Restricted` 输出 "external-sandbox"

2. **`summarizes_external_sandbox_with_enabled_network`**
   - 验证 `ExternalSandbox` + `Enabled` 输出 "external-sandbox (network access enabled)"

3. **`summarizes_read_only_with_enabled_network`**
   - 验证 `ReadOnly` + `network_access: true` 输出 "read-only (network access enabled)"

4. **`workspace_write_summary_still_includes_network_access`**
   - 验证 `WorkspaceWrite` 正确格式化可写路径列表
   - 跨平台路径处理（Windows 使用 `C:\repo`，Unix 使用 `/repo`）

## 风险、边界与改进建议

### 风险点

1. **路径分隔符兼容性**
   - 代码使用 `to_string_lossy()` 转换路径，在 Windows 和 Unix 上表现不同
   - 测试代码通过 `cfg!(windows)` 处理平台差异

2. **枚举变更敏感性**
   - `SandboxPolicy` 结构变更需要同步更新此文件
   - `NetworkAccess` 和布尔值混用（`ReadOnly` 用 `bool`，`ExternalSandbox` 用 `NetworkAccess`）可能导致混淆

3. **字符串硬编码**
   - 所有摘要标识符（如 "workspace-write"、"network access enabled"）都是硬编码字符串
   - 修改需要同步更新测试和调用方

### 边界情况

1. **空可写路径列表**
   - `WorkspaceWrite` 至少包含 "workdir"，不会为空
   - `/tmp` 和 `$TMPDIR` 可通过配置排除

2. **特殊字符路径**
   - 使用 `to_string_lossy()` 处理非 UTF-8 路径，可能丢失信息

3. **路径显示顺序**
   - 固定顺序：workdir → /tmp → $TMPDIR → 自定义路径

### 改进建议

1. **类型一致性**
   - 建议统一 `network_access` 的类型，目前 `ReadOnly` 用 `bool` 而 `ExternalSandbox` 用 `NetworkAccess` 枚举

2. **可配置摘要格式**
   - 考虑支持不同详细级别的摘要（简洁版 vs 详细版）

3. **国际化支持**
   - 当前字符串均为英文硬编码，可引入本地化框架

4. **路径格式化优化**
   - 对于长路径列表，考虑截断或折叠显示
   - 统一路径分隔符显示（如始终使用 `/`）

5. **扩展测试覆盖**
   - 添加 `DangerFullAccess` 的测试
   - 添加 `WorkspaceWrite` 排除 `/tmp` 和 `$TMPDIR` 的边界测试
   - 添加包含多个自定义 `writable_roots` 的测试
