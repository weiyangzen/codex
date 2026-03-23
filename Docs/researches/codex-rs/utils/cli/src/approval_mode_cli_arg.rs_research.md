# approval_mode_cli_arg.rs 研究文档

## 场景与职责

`approval_mode_cli_arg.rs` 是 `codex-utils-cli` crate 的核心组件之一，负责为 Codex CLI 工具提供标准化的 `--approval-mode`（或 `-a`）命令行参数解析。该模块定义了用户如何控制 AI 代理执行 shell 命令时的审批策略，是安全执行模型的关键配置入口。

该模块主要服务于以下场景：
- **交互式 TUI 模式**：用户在 `codex` 主命令中使用 `-a` 参数指定审批模式
- **非交互式 Exec 模式**：`codex exec` 命令通过该参数控制自动执行行为
- **配置一致性**：确保所有 CLI 工具使用统一的审批策略枚举定义

## 功能点目的

### 1. 审批模式枚举定义

定义 `ApprovalModeCliArg` 枚举，提供四种审批策略：

| 枚举值 | CLI 值 | 对应协议类型 | 说明 |
|--------|--------|--------------|------|
| `Untrusted` | `untrusted` | `AskForApproval::UnlessTrusted` | 仅自动批准"可信"命令（如 ls、cat、sed），其他需用户批准 |
| `OnFailure` | `on-failure` | `AskForApproval::OnFailure` | **已弃用**：所有命令自动批准，失败时才升级请求 |
| `OnRequest` | `on-request` | `AskForApproval::OnRequest` | 模型决定何时请求用户批准（默认推荐） |
| `Never` | `never` | `AskForApproval::Never` | 从不请求批准，失败立即返回给模型 |

### 2. CLI 集成支持

- 使用 `clap::ValueEnum` derive 宏自动生成命令行解析逻辑
- 通过 `#[value(rename_all = "kebab-case")]` 确保 CLI 参数使用短横线命名规范
- 每个变体附带详细文档注释，在 `--help` 中展示给用户

### 3. 协议类型转换

实现 `From<ApprovalModeCliArg> for AskForApproval` trait，将 CLI 层类型无缝转换为内部协议类型，供核心逻辑使用。

## 具体技术实现

### 关键数据结构

```rust
#[derive(Clone, Copy, Debug, ValueEnum)]
#[value(rename_all = "kebab-case")]
pub enum ApprovalModeCliArg {
    Untrusted,
    OnFailure,
    OnRequest,
    Never,
}
```

### 类型转换实现

```rust
impl From<ApprovalModeCliArg> for AskForApproval {
    fn from(value: ApprovalModeCliArg) -> Self {
        match value {
            ApprovalModeCliArg::Untrusted => AskForApproval::UnlessTrusted,
            ApprovalModeCliArg::OnFailure => AskForApproval::OnFailure,
            ApprovalModeCliArg::OnRequest => AskForApproval::OnRequest,
            ApprovalModeCliArg::Never => AskForApproval::Never,
        }
    }
}
```

### 命名映射说明

注意 CLI 层使用 `Untrusted` 名称，而协议层使用 `UnlessTrusted`，这是有意为之的设计：
- CLI 层强调"不可信命令需要审批"的用户视角
- 协议层强调"除非可信否则需要审批"的实现逻辑

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/utils/cli/src/approval_mode_cli_arg.rs` (38 行)

### 调用方（CLI 定义）
- `codex-rs/tui/src/cli.rs` (第 77 行): `approval_policy: Option<ApprovalModeCliArg>`
- `codex-rs/tui_app_server/src/cli.rs` (第 77 行): 同上
- `codex-rs/exec/src/cli.rs`: 通过 `full_auto` 和 `dangerously_bypass_approvals_and_sandbox` 间接使用

### 被调用方（协议层）
- `codex-rs/protocol/src/protocol.rs` (第 558-589 行): `AskForApproval` 枚举定义
- `codex-rs/protocol/src/protocol.rs` (第 591-606 行): `GranularApprovalConfig` 细粒度配置

### 使用示例

在 TUI CLI 中的使用方式：
```rust
/// Configure when the model requires human approval before executing a command.
#[arg(long = "ask-for-approval", short = 'a')]
pub approval_policy: Option<ApprovalModeCliArg>,
```

用户命令示例：
```bash
codex -a never "deploy to production"
codex -a on-request "review this code"
codex -a untrusted "analyze logs"
```

## 依赖与外部交互

### 直接依赖
- `clap::ValueEnum`: 提供 CLI 参数解析能力
- `codex_protocol::protocol::AskForApproval`: 内部协议类型

### Crate 依赖关系
```
codex-utils-cli
├── clap (workspace)
└── codex-protocol (workspace)
    └── AskForApproval (协议层审批策略枚举)
```

### 模块导出
在 `codex-rs/utils/cli/src/lib.rs` 中公开导出：
```rust
pub use approval_mode_cli_arg::ApprovalModeCliArg;
```

## 风险、边界与改进建议

### 已知风险

1. **OnFailure 模式已弃用**
   - 代码注释明确标记 `OnFailure` 为 DEPRECATED
   - 建议使用 `on-request`（交互式）或 `never`（非交互式）替代
   - 风险：用户可能仍在使用此模式，未来版本可能移除

2. **命名不一致性**
   - CLI 的 `Untrusted` 映射到协议的 `UnlessTrusted`
   - 可能导致代码阅读时的困惑

3. **Granular 模式未暴露**
   - 协议层支持 `Granular(GranularApprovalConfig)` 细粒度控制
   - CLI 层未提供对应选项，用户无法通过命令行配置细粒度策略

### 边界情况

- CLI 参数为可选值 `Option<ApprovalModeCliArg>`，未指定时使用配置文件的默认值
- 与 `--full-auto` 和 `--dangerously-bypass-approvals-and-sandbox` 存在互斥关系（由调用方 CLI 定义控制）

### 改进建议

1. **添加细粒度 CLI 支持**
   ```rust
   // 建议新增
   Granular {
       sandbox_approval: bool,
       rules: bool,
       skill_approval: bool,
       request_permissions: bool,
       mcp_elicitations: bool,
   }
   ```

2. **统一命名**
   - 考虑将 CLI 层的 `Untrusted` 重命名为 `UnlessTrusted` 以与协议层保持一致

3. **移除已弃用选项**
   - 在主要版本更新时移除 `OnFailure` 变体
   - 添加运行时警告通知用户迁移

4. **增强文档**
   - 在 `--help` 输出中添加各模式的使用场景建议
   - 提供与 `--sandbox` 参数的组合使用指南
