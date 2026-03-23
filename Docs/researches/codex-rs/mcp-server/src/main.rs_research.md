# main.rs 研究文档

## 场景与职责

`main.rs` 是 Codex MCP 服务器的二进制入口点，负责启动 MCP 服务器进程。它使用 `codex_arg0` 库的调度机制，确保正确的运行时环境和辅助工具路径设置。

**核心职责：**
1. 作为 `codex-mcp-server` 二进制文件的入口点
2. 使用 `arg0_dispatch_or_else` 设置运行时环境
3. 委托给 `lib.rs` 的 `run_main` 函数执行实际逻辑

## 功能点目的

### 极简入口设计

```rust
use codex_arg0::Arg0DispatchPaths;
use codex_arg0::arg0_dispatch_or_else;
use codex_mcp_server::run_main;
use codex_utils_cli::CliConfigOverrides;

fn main() -> anyhow::Result<()> {
    arg0_dispatch_or_else(|arg0_paths: Arg0DispatchPaths| async move {
        run_main(arg0_paths, CliConfigOverrides::default()).await?;
        Ok(())
    })
}
```

**设计要点：**
- 极简代码，将所有逻辑委托给库
- 使用 `arg0_dispatch_or_else` 处理 arg0 调度（支持多别名二进制）
- 默认使用空的 CLI 配置覆盖

## 具体技术实现

### Arg0 调度机制

`arg0_dispatch_or_else` 来自 `codex_arg0` 库，执行以下操作：

1. **检查 argv[0]**：确定当前可执行文件的调用名称
2. **特殊别名处理**：
   - 如果名为 `codex-linux-sandbox` → 直接执行沙箱主函数
   - 如果名为 `apply_patch` → 执行补丁应用
   - 如果名为 `codex-execve-wrapper` → 执行 shell 升级包装器
3. **环境设置**：
   - 加载 `~/.codex/.env` 环境变量
   - 创建临时目录并添加符号链接（`apply_patch`, `codex-linux-sandbox` 等）
   - 将临时目录添加到 PATH
4. **Tokio 运行时创建**：构建多线程运行时
5. **执行回调**：调用提供的异步闭包

### 参数传递

```rust
|arg0_paths: Arg0DispatchPaths| async move {
    run_main(arg0_paths, CliConfigOverrides::default()).await?;
    Ok(())
}
```

- `Arg0DispatchPaths`：包含辅助可执行文件的路径
  - `codex_linux_sandbox_exe`：Linux 沙箱可执行文件路径
  - `main_execve_wrapper_exe`：execve 包装器路径
- `CliConfigOverrides::default()`：空的 CLI 配置覆盖

## 关键代码路径与文件引用

### 依赖关系

| 依赖 | 路径 | 用途 |
|------|------|------|
| `arg0_dispatch_or_else` | `codex_arg0` | Arg0 调度和运行时设置 |
| `Arg0DispatchPaths` | `codex_arg0` | 辅助可执行文件路径 |
| `run_main` | `codex_mcp_server` | 库入口函数 |
| `CliConfigOverrides` | `codex_utils_cli` | CLI 配置覆盖类型 |

### 调用链

```
main.rs::main()
    └─> arg0_dispatch_or_else(|arg0_paths| async { ... })
        ├─> 检查 argv[0] 进行特殊处理
        ├─> 加载 .env 文件
        ├─> 创建临时目录和符号链接
        ├─> 修改 PATH
        ├─> 创建 Tokio 运行时
        └─> run_main(arg0_paths, CliConfigOverrides::default())
            └─> lib.rs::run_main() [完整 MCP 服务器逻辑]
```

## 依赖与外部交互

### 与 codex_arg0 的交互

**Arg0DispatchPaths 结构：**
```rust
pub struct Arg0DispatchPaths {
    pub codex_linux_sandbox_exe: Option<PathBuf>,
    pub main_execve_wrapper_exe: Option<PathBuf>,
}
```

**临时目录结构：**
```
~/.codex/tmp/arg0/codex-arg0-XXXXXX/
├── .lock              # 锁文件
├── apply_patch        -> /path/to/codex (符号链接)
├── applypatch         -> /path/to/codex (符号链接)
├── codex-linux-sandbox -> /path/to/codex (符号链接, Linux)
└── codex-execve-wrapper -> /path/to/codex (符号链接, Unix)
```

### 环境变量

**加载的变量（来自 ~/.codex/.env）：**
- 所有非 `CODEX_` 前缀的环境变量
- `CODEX_` 前缀变量被过滤（安全考虑）

**设置的变量：**
- `PATH`：添加临时目录到开头

## 风险、边界与改进建议

### 已知风险

1. **配置覆盖限制**：当前使用 `CliConfigOverrides::default()`，不支持命令行参数
   - 这意味着无法通过命令行传递 `-c key=value` 覆盖

2. **错误处理简化**：所有错误通过 `anyhow::Result` 传播，可能丢失上下文

3. **无信号处理**：不处理 SIGTERM/SIGINT，依赖 Tokio 的默认行为

### 边界情况

| 场景 | 行为 |
|------|------|
| 通过符号链接调用 | `arg0_dispatch_or_else` 正确处理 argv[0] |
| PATH 修改失败 | 打印警告但继续执行 |
| 临时目录创建失败 | 返回错误，进程退出 |
| .env 文件不存在 | 静默忽略 |

### 改进建议

1. **支持命令行参数**：
   ```rust
   fn main() -> anyhow::Result<()> {
       let overrides = parse_cli_args()?;  // 解析 --config key=value
       arg0_dispatch_or_else(|arg0_paths| async move {
           run_main(arg0_paths, overrides).await?;
           Ok(())
       })
   }
   ```

2. **添加版本标志**：
   ```rust
   if args.contains("--version") {
       println!("{}", env!("CARGO_PKG_VERSION"));
       return Ok(());
   }
   ```

3. **信号处理**：
   ```rust
   use tokio::signal;
   
   tokio::select! {
       result = run_main(...) => result,
       _ = signal::ctrl_c() => {
           info!("Received SIGINT, shutting down gracefully...");
           Ok(())
       }
   }
   ```

4. **日志级别控制**：
   ```rust
   if let Ok(rust_log) = std::env::var("RUST_LOG") {
       // 已在 lib.rs 中通过 EnvFilter::from_default_env() 支持
   }
   ```

### 测试覆盖

`main.rs` 本身不包含测试，测试覆盖在：
- `lib.rs`：单元测试和集成测试
- `tests/`：端到端测试
- `tests/common/mcp_process.rs`：MCP 进程测试辅助

### 部署考虑

**单二进制部署：**
- MCP 服务器作为 `codex` CLI 的一部分部署
- 通过符号链接 `codex-mcp-server` 指向主 `codex` 二进制
- `arg0_dispatch_or_else` 确保正确的行为分派

**独立部署：**
- 可以直接运行 `codex-mcp-server` 二进制
- 需要确保 `CODEX_HOME` 目录存在且有正确权限
