# codex-rs/cloud-tasks/src/cli.rs 研究文档

## 场景与职责

`cli.rs` 是 Codex Cloud Tasks 子命令的命令行参数定义模块，使用 `clap` crate 实现声明式参数解析。该模块支持两种使用模式：

1. **TUI 模式**：直接运行 `codex cloud` 启动交互式终端界面
2. **CLI 模式**：使用子命令（exec, status, list, apply, diff）进行非交互式操作

该模块的设计遵循 Unix 哲学，提供简洁、可组合的命令行接口，同时与 `codex-utils-cli` 的 CLI 配置覆盖机制集成。

## 功能点目的

### 1. 主 CLI 结构 (`Cli`)

```rust
#[derive(Parser, Debug, Default)]
#[command(version)]
pub struct Cli {
    #[clap(skip)]
    pub config_overrides: CliConfigOverrides,  // 配置覆盖（内部使用）
    #[command(subcommand)]
    pub command: Option<Command>,              // 可选子命令
}
```

- 当 `command` 为 `None` 时启动 TUI 模式
- `config_overrides` 用于内部传递配置覆盖，不暴露为 CLI 参数

### 2. 子命令枚举 (`Command`)

| 子命令 | 用途 | 对应函数 |
|--------|------|----------|
| `Exec` | 提交新任务到云端 | `lib.rs::run_exec_command` |
| `Status` | 查询任务状态 | `lib.rs::run_status_command` |
| `List` | 列出任务 | `lib.rs::run_list_command` |
| `Apply` | 将任务 diff 应用到本地 | `lib.rs::run_apply_command` |
| `Diff` | 显示任务 diff | `lib.rs::run_diff_command` |

### 3. 参数验证

- **`parse_attempts`**：验证尝试次数在 1-4 范围内（用于 `--attempts` 和 `--attempt`）
- **`parse_limit`**：验证列表限制在 1-20 范围内（用于 `--limit`）

## 具体技术实现

### 数据结构定义

```rust
// 执行命令：提交新任务
#[derive(Debug, Args)]
pub struct ExecCommand {
    #[arg(value_name = "QUERY")]
    pub query: Option<String>,                    // 任务提示（可选，支持 stdin）
    
    #[arg(long = "env", value_name = "ENV_ID")]
    pub environment: String,                      // 目标环境（必需）
    
    #[arg(long = "attempts", default_value_t = 1usize, value_parser = parse_attempts)]
    pub attempts: usize,                          // Best-of-N 尝试次数
    
    #[arg(long = "branch", value_name = "BRANCH")]
    pub branch: Option<String>,                   // Git 分支（默认当前分支）
}

// 状态命令：查询单个任务
#[derive(Debug, Args)]
pub struct StatusCommand {
    #[arg(value_name = "TASK_ID")]
    pub task_id: String,                          // 任务 ID
}

// 列表命令：列出任务
#[derive(Debug, Args)]
pub struct ListCommand {
    #[arg(long = "env", value_name = "ENV_ID")]
    pub environment: Option<String>,              // 环境过滤
    
    #[arg(long = "limit", default_value_t = 20, value_parser = parse_limit)]
    pub limit: i64,                               // 返回数量限制
    
    #[arg(long = "cursor", value_name = "CURSOR")]
    pub cursor: Option<String>,                   // 分页游标
    
    #[arg(long = "json", default_value_t = false)]
    pub json: bool,                               // JSON 输出格式
}

// 应用命令：应用 diff 到本地
#[derive(Debug, Args)]
pub struct ApplyCommand {
    #[arg(value_name = "TASK_ID")]
    pub task_id: String,                          // 任务 ID
    
    #[arg(long = "attempt", value_parser = parse_attempts)]
    pub attempt: Option<usize>,                   // 尝试版本（1-based）
}

// Diff 命令：显示 diff
#[derive(Debug, Args)]
pub struct DiffCommand {
    #[arg(value_name = "TASK_ID")]
    pub task_id: String,                          // 任务 ID
    
    #[arg(long = "attempt", value_parser = parse_attempts)]
    pub attempt: Option<usize>,                   // 尝试版本（1-based）
}
```

### 验证函数实现

```rust
// 验证尝试次数：1-4
fn parse_attempts(input: &str) -> Result<usize, String> {
    let value: usize = input
        .parse()
        .map_err(|_| "attempts must be an integer between 1 and 4".to_string())?;
    if (1..=4).contains(&value) {
        Ok(value)
    } else {
        Err("attempts must be between 1 and 4".to_string())
    }
}

// 验证列表限制：1-20
fn parse_limit(input: &str) -> Result<i64, String> {
    let value: i64 = input
        .parse()
        .map_err(|_| "limit must be an integer between 1 and 20".to_string())?;
    if (1..=20).contains(&value) {
        Ok(value)
    } else {
        Err("limit must be between 1 and 20".to_string())
    }
}
```

## 关键代码路径与文件引用

### 文件内关键代码位置

| 行号 | 内容 |
|------|------|
| 1-3 | 导入声明（clap, codex_utils_cli） |
| 5-13 | `Cli` 结构体定义 |
| 15-27 | `Command` 枚举定义 |
| 29-61 | `ExecCommand` 和验证函数 |
| 63-79 | `StatusCommand` 定义 |
| 81-98 | `ListCommand` 定义 |
| 100-109 | `ApplyCommand` 定义 |
| 111-120 | `DiffCommand` 定义 |

### 跨文件引用关系

```
cli.rs
├── 被 lib.rs 引用
│   └── lib.rs:732-741 (run_main 函数中匹配子命令)
│   └── lib.rs:158-181 (run_exec_command 使用 ExecCommand)
│   └── lib.rs:494-508 (run_status_command 使用 StatusCommand)
│   └── lib.rs:510-575 (run_list_command 使用 ListCommand)
│   └── lib.rs:577-584 (run_diff_command 使用 DiffCommand)
│   └── lib.rs:586-605 (run_apply_command 使用 ApplyCommand)
├── 被上层模块引用
│   └── codex-cli/src/main.rs (通过 codex_cloud_tasks::Cli)
└── 引用外部 crate
    └── codex_utils_cli::CliConfigOverrides
```

### 命令路由流程

```rust
// lib.rs::run_main
pub async fn run_main(cli: Cli, _codex_linux_sandbox_exe: Option<PathBuf>) -> anyhow::Result<()> {
    if let Some(command) = cli.command {
        return match command {
            crate::cli::Command::Exec(args) => run_exec_command(args).await,
            crate::cli::Command::Status(args) => run_status_command(args).await,
            crate::cli::Command::List(args) => run_list_command(args).await,
            crate::cli::Command::Apply(args) => run_apply_command(args).await,
            crate::cli::Command::Diff(args) => run_diff_command(args).await,
        };
    }
    // 无子命令：启动 TUI
    // ...
}
```

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `clap` | 命令行参数解析（derive 特性启用声明式宏） |
| `codex-utils-cli` | CLI 配置覆盖类型 `CliConfigOverrides` |

### 与 codex-utils-cli 的集成

`CliConfigOverrides` 允许通过 CLI 参数覆盖配置文件设置，但当前实现中该字段被标记为 `#[clap(skip)]`，意味着：
- 配置覆盖可能通过其他机制（如环境变量）传递
- 或者该功能预留待实现

### 模块导出

```rust
// lib.rs
pub use cli::Cli;  // 公开导出 Cli 结构体
```

## 风险、边界与改进建议

### 已知风险

1. **验证函数复用**：`parse_attempts` 同时用于 `--attempts`（Exec）和 `--attempt`（Apply/Diff），但语义略有不同：
   - Exec：创建任务时的 Best-of-N 尝试次数（1-4）
   - Apply/Diff：选择要应用的特定尝试版本
   
   虽然数值范围相同，但建议分开以允许不同的限制。

2. **stdin 输入歧义**：`ExecCommand.query` 是 `Option<String>`，在 `lib.rs::resolve_query_input` 中处理 stdin 输入逻辑，这可能导致用户困惑：
   ```bash
   # 以下两种用法都有效，但行为不同
   codex cloud exec "prompt text"          # 直接参数
   echo "prompt text" | codex cloud exec   # stdin
   codex cloud exec -                      # 显式 stdin
   ```

### 边界情况

1. **空环境 ID**：`ExecCommand.environment` 是 `String` 而非 `Option<String>`，强制要求环境参数
2. **任务 ID 解析**：`parse_task_id` 在 `lib.rs` 中处理 URL 片段和查询参数的清理
3. **分页游标**：`ListCommand.cursor` 是透明传递的字符串，不做验证

### 改进建议

1. **添加全局选项**：考虑添加全局 `--format` 选项支持多种输出格式：
   ```rust
   #[derive(Debug, Clone, Copy, ValueEnum)]
   pub enum OutputFormat {
       Plain,
       Json,
       Yaml,
   }
   ```

2. **增强 Exec 命令**：支持从文件读取 prompt：
   ```rust
   #[arg(long = "file", value_name = "FILE")]
   pub file: Option<PathBuf>,
   ```

3. **验证函数改进**：为不同用途的尝试参数提供独立的验证函数：
   ```rust
   fn parse_best_of_n(input: &str) -> Result<usize, String> { /* 1-4 */ }
   fn parse_attempt_number(input: &str) -> Result<usize, String> { /* 1-20, 或动态根据任务 */ }
   ```

4. **文档增强**：为每个命令添加更多示例：
   ```rust
   #[derive(Debug, Args)]
   #[command(after_help = "Examples:\n  codex cloud exec --env prod 'fix bug'")]
   pub struct ExecCommand {
       // ...
   }
   ```

5. **配置覆盖暴露**：考虑将 `config_overrides` 暴露为实际 CLI 参数：
   ```rust
   #[arg(long = "api-key", env = "OPENAI_API_KEY")]
   pub api_key: Option<String>,
   ```

### 代码质量观察

1. **良好实践**：
   - 使用 `clap` 的 derive 宏实现声明式参数定义
   - 清晰的 `value_name` 元数据帮助生成帮助文本
   - 合理的默认值（`attempts=1`, `limit=20`）

2. **潜在改进**：
   - 考虑使用 `clap` 的 `value_enum` 替代自定义验证函数
   - 错误消息可以更加用户友好，提供建议值
