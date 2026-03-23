# cli.rs 研究文档

## 场景与职责

`cli.rs` 是 Codex TUI 应用服务器的命令行接口定义模块，负责定义和解析用户通过命令行传入的所有参数和选项。它是应用程序的入口点配置层，将用户的命令行意图转换为结构化的 Rust 数据结构，供后续的应用逻辑使用。

该模块在整个应用架构中处于最前端，直接面对终端用户，是用户与 Codex TUI 交互的第一道接口。

## 功能点目的

### 1. 核心命令行参数定义
- **Prompt 参数**：可选的初始用户提示语，用于启动会话时直接传入问题或指令
- **Image 附件**：支持通过 `-i` 或 `--image` 参数附加一个或多个图片文件到初始提示

### 2. 会话恢复控制（内部使用）
- `resume_picker` / `resume_last` / `resume_session_id` / `resume_show_all`：由顶层 `codex resume` 子命令设置，用于恢复之前保存的会话
- `fork_picker` / `fork_last` / `fork_session_id` / `fork_show_all`：由顶层 `codex fork` 子命令设置，用于分叉现有会话
- 这些字段标记为 `#[clap(skip)]`，不对用户直接暴露

### 3. 模型与提供商配置
- `--model` / `-m`：指定使用的 AI 模型
- `--oss`：快捷方式，选择本地开源模型提供商（等效于 `-c model_provider=oss`）
- `--local-provider`：指定具体的本地提供商（lmstudio 或 ollama）
- `--profile` / `-p`：从 config.toml 加载指定的配置 profile

### 4. 安全与沙箱控制
- `--sandbox` / `-s`：选择沙箱策略（sandbox policy）
- `--ask-for-approval` / `-a`：配置命令执行前的人工审批策略
- `--full-auto`：低摩擦沙箱自动执行的快捷方式（`-a on-request --sandbox workspace-write`）
- `--dangerously-bypass-approvals-and-sandbox`（别名 `--yolo`）：**极度危险**，跳过所有确认提示和沙箱限制，仅用于外部已隔离的环境

### 5. 工作目录与搜索
- `--cd` / `-C`：指定代理的工作根目录
- `--search`：启用实时网络搜索，使原生 `web_search` 工具可用
- `--add-dir`：添加额外的可写目录

### 6. 显示控制
- `--no-alt-screen`：禁用备用屏幕模式，以内联模式运行 TUI，保留终端滚动历史（适用于 Zellij 等严格遵循 xterm 规范的终端复用器）

### 7. 配置覆盖
- `config_overrides`：内部字段，用于存储 CLI 传递的配置覆盖值

## 具体技术实现

### 数据结构

```rust
#[derive(Parser, Debug)]
#[command(version)]
pub struct Cli {
    #[arg(value_name = "PROMPT", value_hint = clap::ValueHint::Other)]
    pub prompt: Option<String>,
    
    #[arg(long = "image", short = 'i', value_name = "FILE", value_delimiter = ',', num_args = 1..)]
    pub images: Vec<PathBuf>,
    
    // ... 其他字段
}
```

- 使用 `clap` 库的 derive 宏实现命令行解析
- `#[command(version)]` 自动添加 `--version` 支持
- `ValueHint::Other` 为提示语参数提供适当的 shell 补全提示
- `value_delimiter = ','` 和 `num_args = 1..` 支持多值参数

### 关键依赖类型

- `ApprovalModeCliArg`：来自 `codex_utils_cli`，审批模式的 CLI 参数类型
- `CliConfigOverrides`：来自 `codex_utils_cli`，配置覆盖的 CLI 参数类型
- `SandboxModeCliArg`：来自 `codex_utils_cli`，沙箱模式的 CLI 参数类型

### 冲突约束

```rust
#[arg(
    long = "dangerously-bypass-approvals-and-sandbox",
    alias = "yolo",
    default_value_t = false,
    conflicts_with_all = ["approval_policy", "full_auto"]
)]
pub dangerously_bypass_approvals_and_sandbox: bool,
```

- `--yolo` 与 `--ask-for-approval` 和 `--full-auto` 互斥，防止用户同时指定冲突的安全策略

## 关键代码路径与文件引用

### 定义位置
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/cli.rs`

### 调用方
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/main.rs`：顶层入口，解析 `TopCli` 并调用 `run_main`
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/lib.rs`：
  - `run_main` 函数接收 `Cli` 参数
  - 处理 `--full-auto` 和 `--dangerously-bypass-approvals-and-sandbox` 标志
  - 处理 `--search` 标志映射到 `web_search` 配置
  - 处理 `--oss` 和 `--local-provider` 相关的模型提供商逻辑

### 导出
- `pub use cli::Cli;` 在 `lib.rs` 中，使外部可以访问 CLI 定义

## 依赖与外部交互

### 外部依赖
- `clap`：命令行参数解析框架
- `codex_utils_cli`：提供 `ApprovalModeCliArg`、`CliConfigOverrides`、`SandboxModeCliArg`
- `std::path::PathBuf`：文件路径处理

### 内部模块交互
- 与 `lib.rs` 中的配置加载逻辑紧密耦合
- 与 `main.rs` 中的顶层 CLI 结构（`TopCli`）配合，支持 `-c` 配置覆盖

### 配置覆盖流程
```
main.rs (TopCli)
    ↓
lib.rs (run_main)
    ↓
解析 raw_overrides → cli_kv_overrides
    ↓
load_config_as_toml_with_cli_overrides()
```

## 风险、边界与改进建议

### 安全风险
1. **`--yolo` 标志的极端危险性**：该标志明确标记为"EXTREMELY DANGEROUS"，允许无限制执行任意命令。虽然设计用于外部已隔离的环境，但用户可能误用。
   - **建议**：考虑添加额外的确认提示或环境变量检查

2. **`--full-auto` 的便捷性与安全平衡**：虽然提供了便利，但可能让用户忽视安全策略的重要性。
   - **建议**：在首次使用时显示警告信息

### 边界情况
1. **内部标志的可见性**：`resume_*` 和 `fork_*` 字段虽然标记为 `#[clap(skip)]`，但仍存在于公共结构中，可能被误用。
   - **建议**：考虑使用单独的私有结构体封装内部标志

2. **路径解析**：`--cd` 和 `--add-dir` 接受 `PathBuf`，但未在 CLI 层进行存在性验证，依赖后续逻辑处理无效路径。

### 改进建议
1. **文档完善**：部分字段（如 `config_overrides`）缺乏文档注释，建议补充说明其用途和填充时机。

2. **验证增强**：考虑在 CLI 解析阶段添加更多验证，如：
   - `--image` 参数的图片文件存在性和格式验证
   - `--model` 参数的模型名称有效性验证

3. **互斥关系**：当前 `--yolo` 仅与 `approval_policy` 和 `full_auto` 互斥，可能需要考虑与其他安全相关标志的互斥关系。

4. **默认值一致性**：`--oss` 和 `--local-provider` 的交互逻辑较为复杂，建议简化或提供更清晰的帮助文本。
