# main.rs 研究文档

## 场景与职责

`main.rs` 是 `codex-execpolicy` crate 的**二进制入口点**，提供独立的 CLI 可执行文件。它是整个 crate 的用户交互界面，负责：

1. **命令行参数解析**：使用 `clap` 解析用户输入
2. **子命令分发**：根据用户选择的子命令执行相应逻辑
3. **错误处理**：统一处理并报告执行错误
4. **程序退出码**：根据执行结果设置适当的退出码

该模块是库（`lib.rs`）的薄包装，大部分逻辑委托给 `ExecPolicyCheckCommand`。

## 功能点目的

### 1. CLI 枚举定义

```rust
#[derive(Parser)]
#[command(name = "codex-execpolicy")]
enum Cli {
    /// Evaluate a command against a policy.
    Check(ExecPolicyCheckCommand),
}
```

设计选择：
- 使用枚举定义子命令，便于扩展新的子命令
- 文档注释（`///`）自动成为 CLI help 文本
- 目前只有一个 `Check` 子命令，但为未来扩展预留空间

### 2. 主函数

```rust
fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli {
        Cli::Check(cmd) => cmd.run(),
    }
}
```

特点：
- 使用 `anyhow::Result` 作为返回类型，自动处理错误显示
- 模式匹配确保所有子命令都被处理（编译时检查）
- 简洁明了，逻辑委托给子命令的实现

## 具体技术实现

### 执行流程

```
main()
  └── Cli::parse()  [clap 解析参数]
        └── match cli
              └── Cli::Check(cmd)
                    └── cmd.run()  [execpolicycheck.rs]
                          └── 加载策略 → 评估命令 → 输出 JSON
```

### 错误处理

使用 `anyhow` 的错误处理机制：

1. **成功**：`Ok(())` → 进程退出码 0
2. **失败**：`Err(e)` → 打印错误信息，进程退出码非 0

`anyhow` 自动处理错误链的格式化显示。

### 退出码行为

| 场景 | 退出码 | 说明 |
|------|--------|------|
| 成功执行 | 0 | 正常完成 |
| 策略解析错误 | 非 0 | 文件不存在或语法错误 |
| 参数错误 | 非 0 | `clap` 自动处理并退出 |

注意：决策结果（allow/prompt/forbidden）不影响退出码，只影响 JSON 输出。

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_execpolicy::execpolicycheck::ExecPolicyCheckCommand` | 实际的命令执行逻辑 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理和上下文 |
| `clap` | 命令行参数解析 |

### 调用关系

```
main.rs (二进制入口)
  └── lib.rs (库)
        └── execpolicycheck.rs
              └── 其他模块
```

## 风险、边界与改进建议

### 风险点

1. **功能单一**：目前只有一个子命令，作为独立二进制价值有限
2. **错误信息**：依赖 `anyhow` 的默认格式，可能不够用户友好
3. **退出码粒度**：所有错误使用相同的非 0 退出码，难以脚本区分

### 边界条件

1. **无参数**：`clap` 自动显示 help 并退出
2. `--help` / `-h`：`clap` 自动生成 help 文本
3. `--version`：`clap` 自动生成版本信息
4. **无效参数**：`clap` 自动报告错误并退出

### 改进建议

1. **更多子命令**：
   ```rust
   enum Cli {
       Check(ExecPolicyCheckCommand),
       /// Validate policy files without evaluating commands
       Validate(ValidateCommand),
       /// Initialize a new policy file with examples
       Init(InitCommand),
       /// Explain a decision for a command
       Explain(ExplainCommand),
   }
   ```

2. **自定义退出码**：
   ```rust
   fn main() {
       if let Err(e) = run() {
           match e.downcast_ref::<Error>() {
               Some(Error::InvalidPolicy) => std::process::exit(2),
               Some(Error::NoMatch) => std::process::exit(3),
               _ => std::process::exit(1),
           }
       }
   }
   ```

3. **日志支持**：添加 `--verbose` / `-v` 标志控制日志级别
   ```rust
   #[arg(short, long, action = clap::ArgAction::Count)]
   verbose: u8,
   ```

4. **配置文件支持**：支持从配置文件读取默认参数

5. **Shell 补全**：集成 `clap_complete` 生成 shell 补全脚本

6. **人类友好输出**：添加 `--human` 标志，输出更易读的格式而非 JSON

### 使用示例

```bash
# 编译并运行
cargo run -p codex-execpolicy -- check -r default.rules git status

# 安装后使用
cargo install --path codex-rs/execpolicy
codex-execpolicy check -r default.rules git status

# 查看帮助
codex-execpolicy --help
codex-execpolicy check --help
```

### 与 Cargo.toml 的关系

```toml
[[bin]]
name = "codex-execpolicy"
path = "src/main.rs"
```

二进制名称与包名一致，安装后可通过 `codex-execpolicy` 命令调用。
