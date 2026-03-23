# sandbox_mode_cli_arg.rs 研究文档

## 场景与职责

`sandbox_mode_cli_arg.rs` 是 `codex-utils-cli` crate 的核心组件之一，负责为 Codex CLI 工具提供标准化的 `--sandbox`（或 `-s`）命令行参数解析。该模块定义了用户如何控制 AI 代理执行 shell 命令时的沙箱安全策略，是系统安全隔离的关键配置入口。

该模块主要服务于以下场景：
- **交互式 TUI 模式**：用户在 `codex` 主命令中使用 `-s` 参数指定沙箱模式
- **非交互式 Exec 模式**：`codex exec` 命令通过该参数控制执行环境隔离级别
- **安全策略配置**：与 `--approval-mode` 配合使用，构建完整的安全执行策略

## 功能点目的

### 1. 沙箱模式枚举定义

定义 `SandboxModeCliArg` 枚举，提供三种沙箱隔离级别：

| 枚举值 | CLI 值 | 对应配置类型 | 说明 |
|--------|--------|--------------|------|
| `ReadOnly` | `read-only` | `SandboxMode::ReadOnly` | 只读沙箱，禁止任何文件写入 |
| `WorkspaceWrite` | `workspace-write` | `SandboxMode::WorkspaceWrite` | 允许写入工作区目录（默认推荐） |
| `DangerFullAccess` | `danger-full-access` | `SandboxMode::DangerFullAccess` | **危险**：完全文件系统访问 |

### 2. CLI 集成支持

- 使用 `clap::ValueEnum` derive 宏自动生成命令行解析逻辑
- 通过 `#[value(rename_all = "kebab-case")]` 确保 CLI 参数使用短横线命名规范
- 变体命名直观反映安全级别，便于用户理解

### 3. 协议类型转换

实现 `From<SandboxModeCliArg> for SandboxMode` trait，将 CLI 层类型无缝转换为内部配置类型，供沙箱实现层使用。

### 4. 高级配置说明

模块文档明确说明：
- 该枚举仅提供简化的标志选项
- 需要调整 `workspace-write` 高级选项的用户应使用 `-c` 覆盖或 `config.toml`
- 保持 CLI 简洁的同时不限制高级配置能力

## 具体技术实现

### 核心数据结构

```rust
#[derive(Clone, Copy, Debug, ValueEnum)]
#[value(rename_all = "kebab-case")]
pub enum SandboxModeCliArg {
    ReadOnly,
    WorkspaceWrite,
    DangerFullAccess,
}
```

### 类型转换实现

```rust
impl From<SandboxModeCliArg> for SandboxMode {
    fn from(value: SandboxModeCliArg) -> Self {
        match value {
            SandboxModeCliArg::ReadOnly => SandboxMode::ReadOnly,
            SandboxModeCliArg::WorkspaceWrite => SandboxMode::WorkspaceWrite,
            SandboxModeCliArg::DangerFullAccess => SandboxMode::DangerFullAccess,
        }
    }
}
```

### 测试覆盖

模块包含单元测试验证映射正确性：

```rust
#[test]
fn maps_cli_args_to_protocol_modes() {
    assert_eq!(SandboxMode::ReadOnly, SandboxModeCliArg::ReadOnly.into());
    assert_eq!(SandboxMode::WorkspaceWrite, SandboxModeCliArg::WorkspaceWrite.into());
    assert_eq!(SandboxMode::DangerFullAccess, SandboxModeCliArg::DangerFullAccess.into());
}
```

使用 `pretty_assertions` 提供清晰的测试失败输出。

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/utils/cli/src/sandbox_mode_cli_arg.rs` (47 行，含测试)

### 调用方（CLI 定义）

#### TUI CLI
- `codex-rs/tui/src/cli.rs` (第 72-73 行):
  ```rust
  #[arg(long = "sandbox", short = 's')]
  pub sandbox_mode: Option<codex_utils_cli::SandboxModeCliArg>,
  ```

#### TUI App Server CLI
- `codex-rs/tui_app_server/src/cli.rs` (第 72-73 行): 同上

#### Exec CLI
- `codex-rs/exec/src/cli.rs` (第 40-41 行):
  ```rust
  #[arg(long = "sandbox", short = 's', value_enum)]
  pub sandbox_mode: Option<codex_utils_cli::SandboxModeCliArg>,
  ```

### 被调用方（协议层）
- `codex-rs/protocol/src/config_types.rs` (第 52-67 行): `SandboxMode` 枚举定义

### 相关配置

#### 与 `--full-auto` 的集成
在 TUI 和 Exec CLI 中，`--full-auto` 是便捷别名：
```rust
/// Convenience alias for low-friction sandboxed automatic execution 
/// (-a on-request, --sandbox workspace-write).
#[arg(long = "full-auto", default_value_t = false)]
pub full_auto: bool,
```

#### 与 `--dangerously-bypass-approvals-and-sandbox` 的互斥
```rust
#[arg(
    long = "dangerously-bypass-approvals-and-sandbox",
    alias = "yolo",
    conflicts_with_all = ["approval_policy", "full_auto"]
)]
pub dangerously_bypass_approvals_and_sandbox: bool,
```

### 使用示例

```bash
# 只读沙箱（最安全）
codex -s read-only "analyze this codebase"

# 工作区写入（默认推荐）
codex -s workspace-write "refactor this code"

# 危险模式（完全访问）
codex -s danger-full-access "system maintenance"

# 与审批模式组合
codex -s workspace-write -a never "automated task"

# --full-auto 等效于 -s workspace-write -a on-request
codex --full-auto "quick task"
```

## 依赖与外部交互

### 直接依赖
- `clap::ValueEnum`: 提供 CLI 参数解析能力
- `codex_protocol::config_types::SandboxMode`: 内部配置类型

### Crate 依赖关系
```
codex-utils-cli
├── clap (workspace)
└── codex-protocol (workspace)
    └── SandboxMode (配置层沙箱模式枚举)
```

### 模块导出
在 `codex-rs/utils/cli/src/lib.rs` 中公开导出：
```rust
pub use sandbox_mode_cli_arg::SandboxModeCliArg;
```

## 风险、边界与改进建议

### 已知风险

1. **DangerFullAccess 命名风险**
   - 名称中包含 "Danger" 但仍可能被用户误用
   - 建议添加运行时警告或确认提示

2. **平台兼容性差异**
   - 不同操作系统（Linux/macOS/Windows）的沙箱实现能力不同
   - CLI 层不暴露这些差异，用户可能产生错误预期
   - 例如：Windows 可能不支持某些 Landlock 特性

3. **高级配置隐藏**
   - 文档说明高级选项需通过 `-c` 或配置文件
   - 但用户可能不知道有哪些高级选项可用
   - 缺乏 discoverability

### 边界情况

| 场景 | 行为 |
|------|------|
| 未指定 `-s` | 使用配置文件默认值（通常是 `workspace-write`） |
| 与 `--full-auto` 同时指定 | CLI 定义确保 `--full-auto` 设置独立字段，由应用逻辑处理冲突 |
| 与 `--dangerously-bypass-approvals-and-sandbox` 同时指定 | `conflicts_with_all` 阻止此组合 |
| 无效值 | clap 自动提供错误提示和有效值列表 |

### 与协议层差异

注意 CLI 层和配置层的序列化差异：

| 层 | ReadOnly | WorkspaceWrite | DangerFullAccess |
|----|----------|----------------|------------------|
| CLI (ValueEnum) | `read-only` | `workspace-write` | `danger-full-access` |
| Config (serde) | `read-only` | `workspace-write` | `danger-full-access` |

两者使用相同的 kebab-case 命名，保持一致性。

### 改进建议

1. **添加平台检测**
   ```rust
   impl SandboxModeCliArg {
       pub fn check_platform_support(&self) -> Result<(), String> {
           match (self, std::env::consts::OS) {
               (Self::ReadOnly, "windows") => {
                   warn!("Read-only sandbox on Windows has limited enforcement");
               }
               _ => {}
           }
           Ok(())
       }
   }
   ```

2. **危险模式确认**
   ```rust
   // 在应用层（非本模块）添加
   if sandbox_mode == SandboxMode::DangerFullAccess {
       eprintln!("⚠️  WARNING: Using danger-full-access sandbox mode");
       eprintln!("   This grants the AI full filesystem access.");
       if !confirm("Continue?") {
           std::process::exit(1);
       }
   }
   ```

3. **高级选项文档**
   ```rust
   /// Select the sandbox policy to use when executing model-generated shell
   /// commands.
   ///
   /// For advanced options (e.g., custom writable paths), use:
   ///   -c sandbox.workspace_write.paths=["/custom/path"]
   #[arg(long = "sandbox", short = 's')]
   pub sandbox_mode: Option<SandboxModeCliArg>,
   ```

4. **添加 DryRun 模式**
   ```rust
   // 建议新增变体
   DryRun,  // 显示将要执行的命令但不实际运行
   ```

5. **配置验证**
   ```rust
   impl SandboxModeCliArg {
       pub fn validate_with_cwd(&self, cwd: &Path) -> Result<(), String> {
           // 验证工作区路径可访问
           // 验证沙箱策略与当前目录兼容
       }
   }
   ```

6. **与 Seatbelt/Landlock 集成文档**
   - 添加注释说明各模式在 macOS (Seatbelt) 和 Linux (Landlock) 下的具体实现
   - 帮助开发者理解底层安全机制
