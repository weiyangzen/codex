# SandboxMode.ts 研究文档

## 场景与职责

`SandboxMode.ts` 定义了沙箱执行模式的数据结构，用于指定 Codex 执行命令时的安全隔离级别。这是 Codex 安全模型的核心组件，控制代理执行外部命令时的文件系统和网络访问权限。

## 功能点目的

该类型用于：
1. **安全分级**：提供三个预定义的安全级别供用户选择
2. **权限控制**：控制文件系统读写和网络访问权限
3. **风险平衡**：在安全性和功能性之间提供可配置的平衡
4. **用户体验**：简化复杂的沙箱配置，提供直观的选项

## 具体技术实现

### 数据结构定义

```typescript
export type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
```

### 变体详解

| 值 | 说明 | 文件系统 | 网络 |
|----|------|---------|------|
| "read-only" | 只读模式 | 只读访问 | 禁用 |
| "workspace-write" | 工作区写入模式 | 读写当前工作目录 | 可选 |
| "danger-full-access" | 完全访问模式 | 无限制 | 无限制 |

### Rust 协议定义

在 `codex-rs/protocol/src/models.rs` 中：

```rust
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Display, Default, JsonSchema, TS,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum SandboxMode {
    /// 只读访问，最安全
    ReadOnly,
    
    /// 允许写入工作区
    #[default]
    WorkspaceWrite,
    
    /// 无限制访问，最危险
    DangerFullAccess,
}
```

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中的 V2 封装：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[ts(rename_all = "kebab-case", export_to = "v2/")]
pub enum SandboxMode {
    ReadOnly,
    WorkspaceWrite,
    DangerFullAccess,
}

impl SandboxMode {
    pub fn to_core(self) -> CoreSandboxMode {
        match self {
            SandboxMode::ReadOnly => CoreSandboxMode::ReadOnly,
            SandboxMode::WorkspaceWrite => CoreSandboxMode::WorkspaceWrite,
            SandboxMode::DangerFullAccess => CoreSandboxMode::DangerFullAccess,
        }
    }
}
```

### 配置集成

在 `config.toml` 中：

```toml
sandbox_mode = "read-only"  # 或 "workspace-write", "danger-full-access"
```

### CLI 参数

在 `codex-rs/cli/src/main.rs` 和 `codex-rs/tui/src/cli.rs` 中：

```rust
#[arg(long, value_enum)]
sandbox_mode: Option<SandboxMode>,
```

### 到 SandboxPolicy 的映射

SandboxMode 会被转换为更详细的 SandboxPolicy：

```rust
impl From<SandboxMode> for SandboxPolicy {
    fn from(mode: SandboxMode) -> Self {
        match mode {
            SandboxMode::ReadOnly => SandboxPolicy::ReadOnly {
                access: ReadOnlyAccess::Restricted {
                    include_platform_defaults: true,
                    readable_roots: vec![],
                },
                network_access: false,
            },
            SandboxMode::WorkspaceWrite => SandboxPolicy::WorkspaceWrite {
                writable_roots: vec![],
                read_only_access: ReadOnlyAccess::Restricted {
                    include_platform_defaults: true,
                    readable_roots: vec![],
                },
                network_access: false,
                exclude_tmpdir_env_var: false,
                exclude_slash_tmp: false,
            },
            SandboxMode::DangerFullAccess => SandboxPolicy::DangerFullAccess,
        }
    }
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SandboxMode.ts`

### Rust 协议定义
- 核心类型：`codex-rs/protocol/src/models.rs`
- V2 API 封装：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- V1 协议：`codex-rs/app-server-protocol/src/protocol/v1.rs`

### 配置系统
- 配置类型：`codex-rs/core/src/config/types.rs`
- 配置模块：`codex-rs/core/src/config/mod.rs`
- 配置模式：`codex-rs/core/config.schema.json`

### CLI 集成
- CLI 主程序：`codex-rs/cli/src/main.rs`
- 调试沙箱：`codex-rs/cli/src/debug_sandbox.rs`
- TUI CLI：`codex-rs/tui/src/cli.rs`
- Exec CLI：`codex-rs/exec/src/cli.rs`

### 沙箱实现
- Linux 沙箱：`codex-rs/linux-sandbox/src/linux_run_main.rs`
- Landlock：`codex-rs/core/src/landlock.rs`
- Windows 沙箱：`codex-rs/core/src/windows_sandbox.rs`
- Seatbelt：`codex-rs/core/src/seatbelt.rs`

### 工具函数
- CLI 参数工具：`codex-rs/utils/cli/src/sandbox_mode_cli_arg.rs`

### 测试覆盖
- 配置测试：`codex-rs/app-server/tests/suite/v2/config_rpc.rs`

## 依赖与外部交互

### 上游依赖
- 用户配置：从 config.toml 或命令行参数读取
- 平台检测：不同平台实现不同的沙箱机制

### 下游消费
- SandboxPolicy：SandboxMode 转换为更详细的策略
- 执行引擎：根据模式配置相应的沙箱技术

### 安全级别对比

| 特性 | read-only | workspace-write | danger-full-access |
|------|-----------|-----------------|-------------------|
| 文件读取 | 受限 | 受限 | 无限制 |
| 文件写入 | 禁止 | 工作区允许 | 无限制 |
| 网络访问 | 禁止 | 可选 | 无限制 |
| 安全风险 | 低 | 中 | 高 |
| 适用场景 | 安全审计 | 日常开发 | 特殊需求 |

## 风险、边界与改进建议

### 边界情况
1. **默认模式**：默认值为 WorkspaceWrite，平衡安全和功能
2. **模式降级**：某些平台可能不支持某些模式
3. **嵌套执行**：子进程继承父进程的沙箱设置

### 潜在风险
1. **DangerFullAccess**：完全禁用沙箱保护，仅在受信任环境使用
2. **平台差异**：不同平台的沙箱实现可能有细微差异
3. **绕过可能**：有经验的用户可能找到绕过沙箱的方法

### 改进建议
1. **默认安全**：考虑将默认从 WorkspaceWrite 改为 ReadOnly
2. **警告提示**：在启用 DangerFullAccess 时显示明确警告
3. **审计日志**：记录沙箱模式的使用情况
4. **细粒度控制**：在 WorkspaceWrite 中添加更多可配置选项
5. **模式推荐**：根据操作类型智能推荐合适的模式
6. **临时提升**：支持临时提升权限而不改变配置
