# execve_wrapper.rs 研究文档

## 场景与职责

`execve_wrapper.rs` 是 Unix 平台 shell 权限提升机制的**入口点实现**，定义了 execve 包装器二进制文件的 CLI 接口和主函数。当打补丁的 shell 尝试执行命令时，会调用此包装器，包装器再与权限提升服务器通信决定如何执行命令。

核心职责：
1. 定义 CLI 参数结构（`ExecveWrapperCli`）
2. 初始化日志记录（`tracing_subscriber`）
3. 解析命令行参数
4. 调用 `run_shell_escalation_execve_wrapper` 执行权限提升流程
5. 以适当的退出码退出进程

## 功能点目的

### 1. CLI 参数结构

```rust
#[derive(Parser)]
pub struct ExecveWrapperCli {
    file: String,

    #[arg(trailing_var_arg = true)]
    argv: Vec<String>,
}
```

- `file`：要执行的文件路径（由 shell 的 exec 调用提供）
- `argv`：参数列表（包含 argv[0]），使用 `trailing_var_arg = true` 捕获所有剩余参数

**使用方式**：
```bash
# 由打补丁的 shell 调用
execve_wrapper /bin/ls ls -la /
```

### 2. 主函数

```rust
#[tokio::main]
pub async fn main_execve_wrapper() -> anyhow::Result<()> {
    // 1. 初始化日志
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .with_writer(std::io::stderr)
        .with_ansi(false)
        .init();

    // 2. 解析参数
    let ExecveWrapperCli { file, argv } = ExecveWrapperCli::parse();

    // 3. 执行权限提升流程
    let exit_code = crate::run_shell_escalation_execve_wrapper(file, argv).await?;

    // 4. 以返回的退出码退出
    std::process::exit(exit_code);
}
```

## 具体技术实现

### 日志初始化

```rust
tracing_subscriber::fmt()
    .with_env_filter(EnvFilter::from_default_env())  // 从环境变量读取日志级别
    .with_writer(std::io::stderr)                     // 输出到 stderr
    .with_ansi(false)                                 // 禁用 ANSI 颜色（避免日志污染）
    .init();
```

**设计考虑**：
- 使用 `EnvFilter::from_default_env()` 允许通过 `RUST_LOG` 环境变量控制日志级别
- 输出到 stderr 而非 stdout，避免干扰命令的正常输出
- 禁用 ANSI 颜色，因为包装器的输出可能被重定向或处理

### 参数解析

使用 `clap` 的 derive 宏简化参数解析：
- `trailing_var_arg = true`：将所有剩余参数捕获到 `argv` Vec 中
- 这意味着包装器可以接受任意数量的参数

### 进程退出

```rust
std::process::exit(exit_code);
```

**注意**：使用 `std::process::exit` 而非返回 `Result` 是为了：
1. 确保进程以正确的退出码终止
2. 避免 `Drop` 实现可能带来的副作用（如刷新缓冲区等）
3. 符合 Unix 工具的行为预期

## 关键代码路径与文件引用

### 本文件内关键行

| 行号 | 内容 | 说明 |
|------|------|------|
| 1 | `//! Entrypoints for execve interception helper binaries.` | 模块文档 |
| 3-4 | `use clap::Parser; use tracing_subscriber::EnvFilter;` | 外部依赖 |
| 6-12 | `ExecveWrapperCli` | CLI 参数结构 |
| 14-25 | `main_execve_wrapper` | 主函数 |

### 依赖文件

- `escalate_client.rs`：`run_shell_escalation_execve_wrapper` 函数

### 被依赖文件

| 文件 | 用途 |
|------|------|
| `mod.rs` | 重新导出 `main_execve_wrapper` |
| `src/bin/main_execve_wrapper.rs` | 调用 `main_execve_wrapper` |

### 二进制入口点

```rust
// src/bin/main_execve_wrapper.rs
#[cfg(not(unix))]
fn main() {
    eprintln!("codex-execve-wrapper is only implemented for UNIX");
    std::process::exit(1);
}

#[cfg(unix)]
pub use codex_shell_escalation::main_execve_wrapper as main;
```

非 Unix 平台提供友好的错误消息，Unix 平台直接使用 `main_execve_wrapper`。

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `clap::Parser` | CLI 参数解析 |
| `tracing_subscriber::EnvFilter` | 日志级别过滤 |
| `tracing_subscriber::fmt` | 日志格式化 |

### 环境变量

| 变量 | 用途 |
|------|------|
| `RUST_LOG` | 控制日志级别（如 `RUST_LOG=debug`） |
| `CODEX_ESCALATE_SOCKET` | 权限提升 socket 的 FD（由父进程设置） |
| `EXEC_WRAPPER` | 本包装器的路径（由父进程设置） |

### 调用链

```
打补丁的 Shell
    └── execve(EXEC_WRAPPER, [file, argv...], env)
            └── main_execve_wrapper()
                    └── ExecveWrapperCli::parse()
                    └── run_shell_escalation_execve_wrapper(file, argv)
                            └── [与权限提升服务器通信]
                    └── std::process::exit(exit_code)
```

## 风险、边界与改进建议

### 已知风险

1. **日志初始化失败**：如果 `tracing_subscriber::fmt().init()` 失败（如已经被初始化），会导致 panic。虽然在这个单入口点的二进制中不太可能发生，但需要注意。

2. **参数解析错误**：如果参数格式不正确，`clap` 会打印帮助信息并退出，退出码为 2（符合 Unix 惯例）。

3. **tokio 运行时**：使用 `#[tokio::main]` 创建异步运行时，如果创建失败会导致 panic。

### 边界情况

1. **空参数列表**：`argv` 可能为空（如果只提供 `file` 而没有其他参数），这是合法的 execve 调用

2. **特殊字符**：`file` 和 `argv` 中的特殊字符（如空格、引号）由 shell 负责转义，包装器接收的是已经解析后的字符串

3. **环境变量**：包装器继承 shell 的环境变量，包括 `CODEX_ESCALATE_SOCKET` 和 `EXEC_WRAPPER`

4. **信号处理**：包装器本身不处理信号，信号处理由权限提升服务器负责

### 改进建议

1. **参数验证**：可以添加对 `file` 的基本验证（如非空检查）：
   ```rust
   if file.is_empty() {
       eprintln!("Error: file argument is empty");
       std::process::exit(1);
   }
   ```

2. **更详细的日志**：可以添加启动日志，记录接收到的参数：
   ```rust
   tracing::debug!("execve wrapper invoked: file={}, argv={:?}", file, argv);
   ```

3. **错误码映射**：当前直接使用服务器返回的退出码，可以考虑映射特定的错误码：
   ```rust
   match crate::run_shell_escalation_execve_wrapper(file, argv).await {
       Ok(exit_code) => std::process::exit(exit_code),
       Err(e) => {
           tracing::error!("execve wrapper error: {}", e);
           std::process::exit(126);  // 126 = Command invoked cannot execute
       }
   }
   ```

4. **信号处理**：可以考虑添加基本的信号处理，如 SIGTERM 的优雅退出

5. **性能优化**：如果包装器被频繁调用，可以考虑：
   - 使用 `tokio::runtime::Builder` 自定义运行时参数
   - 添加连接池复用与权限提升服务器的连接

### 测试覆盖

本文件本身没有直接测试，测试通过以下方式覆盖：

1. **集成测试**：`escalate_server.rs` 中的测试模拟完整的客户端-服务器交互
2. **二进制测试**：`codex-rs/core/src/tools/runtimes/shell/unix_escalation_tests.rs` 测试了与核心逻辑的集成

由于这是一个简单的入口点，主要逻辑在 `escalate_client.rs` 中测试，这种设计是合理的。

### 安全考虑

1. **参数注入**：`file` 和 `argv` 来自 shell 的 exec 调用，理论上可能被恶意构造。但由于包装器只是将这些参数传递给服务器决策，实际的安全检查在服务器端完成。

2. **环境变量继承**：包装器继承所有环境变量，包括可能敏感的信息。服务器应该谨慎处理这些环境变量。

3. **权限检查**：包装器本身不检查执行权限，完全依赖服务器的决策。这符合"最小权限"原则——包装器只负责通信，决策权在服务器。
