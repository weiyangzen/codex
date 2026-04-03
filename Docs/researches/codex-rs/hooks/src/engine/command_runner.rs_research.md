# command_runner.rs 深度研究文档

## 场景与职责

`command_runner.rs` 是 Codex Hooks 系统的**命令执行引擎**，负责将配置好的 Hook 处理器（ConfiguredHandler）转换为实际的子进程执行。它是 Hooks 系统与操作系统交互的核心边界层，承担着以下关键职责：

1. **跨平台 Shell 命令执行**：支持 Windows (cmd.exe) 和 Unix (sh/bash) 系统
2. **进程生命周期管理**：创建、输入写入、超时控制、资源清理
3. **执行结果标准化**：将各种执行结果（成功、失败、超时）统一为 `CommandRunResult` 结构
4. **安全隔离**：通过 `kill_on_drop` 确保异常时子进程被终止

该模块是 Hooks 系统的"最后一公里"，所有配置解析、事件匹配、输出解析都最终汇聚到这里执行。

## 功能点目的

### 1. 命令执行结果封装 (`CommandRunResult`)

```rust
pub(crate) struct CommandRunResult {
    pub started_at: i64,      // UTC 时间戳（秒）
    pub completed_at: i64,    // UTC 时间戳（秒）
    pub duration_ms: i64,     // 执行耗时毫秒
    pub exit_code: Option<i32>, // 进程退出码（None 表示异常终止）
    pub stdout: String,       // 标准输出
    pub stderr: String,       // 标准错误
    pub error: Option<String>, // 执行错误信息（如启动失败）
}
```

**设计意图**：
- 提供完整的可观测性数据（时间、耗时、退出码）
- 区分"进程正常退出"和"执行异常"（通过 `exit_code` vs `error`）
- 统一 UTF-8 字符串处理（使用 `String::from_utf8_lossy` 处理二进制输出）

### 2. 异步命令执行 (`run_command`)

**执行流程**：
1. 记录开始时间戳和计时器
2. 构建命令（`build_command`）
3. 配置工作目录和标准流重定向
4. 启动子进程
5. 异步写入输入 JSON 到 stdin
6. 等待进程完成或超时
7. 收集输出并返回结果

**关键设计决策**：
- **超时控制**：使用 `tokio::time::timeout`，默认 600 秒（来自 `handler.timeout_sec`）
- **输入传递**：通过 stdin 传递 JSON 输入，支持复杂数据结构
- **错误处理**：区分"启动失败"、"写入失败"、"执行超时"三种错误场景

### 3. 跨平台 Shell 支持

```rust
fn default_shell_command() -> Command {
    #[cfg(windows)]
    {
        let comspec = std::env::var("COMSPEC").unwrap_or_else(|_| "cmd.exe".to_string());
        let mut command = Command::new(comspec);
        command.arg("/C");
        command
    }

    #[cfg(not(windows))]
    {
        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
        let mut command = Command::new(shell);
        command.arg("-lc");
        command
    }
}
```

**Windows 支持**：
- 使用 `COMSPEC` 环境变量（通常为 cmd.exe）
- `/C` 参数执行命令后退出

**Unix 支持**：
- 使用 `SHELL` 环境变量（通常为 bash/sh）
- `-lc` 参数：`-l` 登录 shell，`-c` 执行命令

### 4. 命令构建逻辑 (`build_command`)

支持两种执行模式：
- **默认 Shell**：当 `shell.program` 为空时，使用系统默认 shell
- **自定义 Shell**：使用配置的 shell 程序和参数

## 具体技术实现

### 关键流程：命令执行

```rust
pub(crate) async fn run_command(
    shell: &CommandShell,
    handler: &ConfiguredHandler,
    input_json: &str,
    cwd: &Path,
) -> CommandRunResult {
    // 1. 时间记录
    let started_at = chrono::Utc::now().timestamp();
    let started = Instant::now();

    // 2. 构建命令
    let mut command = build_command(shell, handler);
    command
        .current_dir(cwd)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);  // 关键：确保资源清理

    // 3. 启动进程
    let mut child = match command.spawn() { ... };

    // 4. 写入输入
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(input_json.as_bytes()).await?;
    }

    // 5. 超时等待
    let timeout_duration = Duration::from_secs(handler.timeout_sec);
    match timeout(timeout_duration, child.wait_with_output()).await {
        Ok(Ok(output)) => { /* 成功 */ },
        Ok(Err(err)) => { /* 执行错误 */ },
        Err(_) => { /* 超时 */ },
    }
}
```

### 错误处理策略

| 错误场景 | 处理方式 | 返回结果 |
|---------|---------|---------|
| 进程启动失败 | 立即返回 | `exit_code: None, error: Some(...)` |
| stdin 写入失败 | 杀死进程后返回 | `exit_code: None, error: Some(...)` |
| 执行超时 | 超时错误 | `exit_code: None, error: Some("hook timed out...")` |
| 进程异常退出 | 捕获错误 | `exit_code: None, error: Some(...)` |

## 关键代码路径与文件引用

### 当前文件关键路径

```
codex-rs/hooks/src/engine/command_runner.rs
├── CommandRunResult (struct) - 结果封装
├── run_command (async fn) - 主执行入口
├── build_command (fn) - 命令构建
└── default_shell_command (fn) - 跨平台 shell 选择
```

### 调用方（上游）

```
codex-rs/hooks/src/engine/dispatcher.rs
└── execute_handlers()
    └── run_command()  // 并发执行多个 handler

codex-rs/hooks/src/engine/mod.rs
└── ClaudeHooksEngine
    └── run_session_start() / run_user_prompt_submit() / run_stop()
        └── dispatcher::execute_handlers()
```

### 被调用方（下游）

- **Tokio**: `tokio::process::Command`, `tokio::io::AsyncWriteExt`, `tokio::time::timeout`
- **Chrono**: `chrono::Utc::now().timestamp()`
- **标准库**: `std::process::Stdio`, `std::time::Instant`

## 依赖与外部交互

### 输入依赖

| 来源 | 类型 | 用途 |
|-----|------|------|
| `CommandShell` | struct | Shell 程序配置（program, args） |
| `ConfiguredHandler` | struct | 处理器配置（command, timeout_sec） |
| `input_json` | &str | 通过 stdin 传递给 hook 的输入数据 |
| `cwd` | &Path | 工作目录 |

### 输出消费

| 消费者 | 消费内容 |
|-------|---------|
| `dispatcher::execute_handlers` | `CommandRunResult` 列表 |
| `session_start::parse_completed` | 解析 stdout 获取上下文/停止信号 |
| `user_prompt_submit::parse_completed` | 解析 stdout 获取阻塞决策 |
| `stop::parse_completed` | 解析 stdout 获取停止/阻塞决策 |

### 外部系统交互

- **操作系统进程 API**：通过 Tokio 的异步进程管理
- **文件系统**：通过 `cwd` 设置工作目录
- **环境变量**：读取 `COMSPEC` (Windows) 或 `SHELL` (Unix)

## 风险、边界与改进建议

### 已知风险

1. **UTF-8 假设风险**
   ```rust
   stdout: String::from_utf8_lossy(&output.stdout).to_string()
   ```
   - Hook 输出非 UTF-8 内容时会丢失信息（使用 `U+FFFD` 替换）
   - **建议**：考虑添加原始字节输出选项用于调试

2. **超时粒度**
   - 超时仅覆盖 `wait_with_output`，不包含进程启动时间
   - **建议**：考虑整体超时包括启动和输入写入

3. **大输入处理**
   - 输入 JSON 通过内存管道一次性写入
   - 超大输入可能导致内存压力

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| Hook 命令为空字符串 | 在 discovery 阶段过滤，不会到达此处 | ✅ 合理 |
| 超时时间为 0 | `timeout_sec.max(1)` 确保至少 1 秒 | ✅ 合理 |
| 工作目录不存在 | `command.spawn()` 失败，返回 error | ✅ 合理 |
| 同时执行大量 Hook | `join_all` 并发执行，可能耗尽系统资源 | ⚠️ 需监控 |

### 改进建议

1. **资源限制**
   - 添加并发执行限制（semaphore）防止资源耗尽
   - 考虑添加内存限制（通过 cgroup/ulimit）

2. **可观测性增强**
   - 添加结构化日志记录命令执行详情
   - 支持 OpenTelemetry span 追踪

3. **安全加固**
   - 考虑添加命令白名单验证
   - 支持沙箱执行（如使用 seccomp-bpf）

4. **性能优化**
   - 对于频繁执行的 Hook，考虑进程池复用
   - 添加输出大小限制防止 OOM

### 测试覆盖

当前测试位于各事件处理模块（`session_start.rs`, `user_prompt_submit.rs`, `stop.rs`）的 `#[cfg(test)]` 中，通过 mock `CommandRunResult` 进行测试。建议添加：
- 集成测试：实际执行 shell 命令验证跨平台行为
- 超时测试：验证超时机制正确工作
- 并发测试：验证大量并发 Hook 执行的稳定性
