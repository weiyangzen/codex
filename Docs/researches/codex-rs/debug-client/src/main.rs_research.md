# main.rs 深度研究文档

## 场景与职责

`main.rs` 是 debug-client 的入口点和主控制循环，负责协调所有子模块完成交互式会话。它是应用程序的"大脑"，管理 CLI 参数解析、客户端生命周期、用户输入处理和事件分发。

**核心定位**：
- 命令行界面入口（使用 `clap` 派生宏）
- 主事件循环实现（同步阻塞 I/O）
- 模块协调器（client, commands, output, state）
- 错误处理和用户反馈

**使用场景**：
- 开发调试：快速测试 app-server 协议
- 自动化脚本：通过管道输入命令
- 交互式探索：手动与 AI 对话

## 功能点目的

### 1. CLI 参数定义

```rust
#[derive(Parser)]
#[command(author = "Codex", version, about = "Minimal app-server client")]
struct Cli {
    #[arg(long, default_value = "codex")]
    codex_bin: String,              // codex 二进制路径

    #[arg(short = 'c', long = "config", value_name = "key=value", action = ArgAction::Append)]
    config_overrides: Vec<String>,  // 配置覆盖

    #[arg(long)]
    thread_id: Option<String>,      // 恢复已有线程

    #[arg(long, default_value = "on-request")]
    approval_policy: String,        // 审批策略

    #[arg(long, default_value_t = false)]
    auto_approve: bool,             // 自动审批

    #[arg(long, default_value_t = false)]
    final_only: bool,               // 仅显示最终结果

    #[arg(long)]
    model: Option<String>,          // 模型覆盖

    #[arg(long)]
    model_provider: Option<String>, // 提供商覆盖

    #[arg(long)]
    cwd: Option<String>,            // 工作目录覆盖
}
```

**参数设计意图**：
- `--codex-bin`：支持非标准安装路径或测试版本
- `-c/--config`：灵活覆盖配置，支持多次使用
- `--thread-id`：会话恢复，支持断点续传
- `--approval-policy`：安全级别控制
- `--auto-approve`：自动化场景（需谨慎）
- `--final-only`：减少噪音，仅关注结果
- `--model/--model-provider`：快速切换模型
- `--cwd`：指定工作上下文

### 2. 主函数流程

**初始化阶段**（行66-99）：
```rust
fn main() -> Result<()> {
    let cli = Cli::parse();                    // 1. 解析 CLI
    let output = Output::new();                // 2. 创建输出处理器
    let approval_policy = parse_approval_policy(&cli.approval_policy)?;  // 3. 解析策略

    let mut client = AppServerClient::spawn(   // 4. 启动客户端
        &cli.codex_bin,
        &cli.config_overrides,
        output.clone(),
        cli.final_only,
    )?;
    client.initialize()?;                      // 5. 初始化握手

    // 6. 启动或恢复线程
    let thread_id = if let Some(thread_id) = cli.thread_id.as_ref() {
        client.resume_thread(...)?
    } else {
        client.start_thread(...)?
    };

    output.client_line(&format!("connected to thread {thread_id}")).ok();
    output.set_prompt(&thread_id);
```

**事件循环阶段**（行101-148）：
```rust
    let (event_tx, event_rx) = mpsc::channel();     // 7. 创建事件通道
    client.start_reader(event_tx, cli.auto_approve, cli.final_only)?;  // 8. 启动 reader

    print_help(&output);

    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();

    loop {
        drain_events(&event_rx, &output);           // 9. 处理待处理事件
        let prompt_thread = client.thread_id().unwrap_or_else(|| "no-thread".to_string());
        output.prompt(&prompt_thread).ok();         // 10. 显示提示符

        let Some(line) = lines.next() else { break };  // 11. 读取输入
        let line = line.context("read stdin")?;

        match parse_input(&line) {                  // 12. 解析输入
            Ok(None) => continue,
            Ok(Some(InputAction::Message(message))) => { /* 发送消息 */ }
            Ok(Some(InputAction::Command(command))) => { /* 处理命令 */ }
            Err(err) => { output.client_line(&err.message()).ok(); }
        }
    }

    client.shutdown();                              // 13. 清理
    Ok(())
}
```

### 3. 命令处理

**handle_command 函数**（行151-237）：
```rust
fn handle_command(
    command: UserCommand,
    client: &AppServerClient,
    output: &Output,
    approval_policy: AskForApproval,
    cli: &Cli,
) -> bool  // 返回 false 表示退出主循环
```

| 命令 | 行为 | 返回值 |
|------|------|--------|
| `Help` | 打印帮助 | `true` |
| `Quit` | 退出程序 | `false` |
| `NewThread` | 异步创建新线程 | `true` |
| `Resume` | 异步恢复线程 | `true` |
| `Use` | 切换当前线程（不加载） | `true` |
| `RefreshThread` | 请求线程列表 | `true` |

**关键区别**：
- `NewThread`/`Resume`：发送请求，通过 `ReaderEvent` 异步接收结果
- `Use`：仅本地状态切换，不与服务端交互

### 4. 审批策略解析

```rust
fn parse_approval_policy(value: &str) -> Result<AskForApproval> {
    match value {
        "untrusted" | "unless-trusted" | "unlessTrusted" => Ok(AskForApproval::UnlessTrusted),
        "on-failure" | "onFailure" => Ok(AskForApproval::OnFailure),
        "on-request" | "onRequest" => Ok(AskForApproval::OnRequest),
        "never" => Ok(AskForApproval::Never),
        _ => anyhow::bail!("unknown approval policy: {value}..."),
    }
}
```

**支持格式**：
- kebab-case: `on-request`, `unless-trusted`
- camelCase: `onRequest`, `unlessTrusted`
- 别名: `untrusted` = `unless-trusted`

### 5. 事件处理

**drain_events 函数**（行251-282）：
```rust
fn drain_events(event_rx: &mpsc::Receiver<ReaderEvent>, output: &Output)
```

**非阻塞接收**：使用 `try_recv()` 循环直到通道为空

**事件类型处理**：
```rust
match event {
    ReaderEvent::ThreadReady { thread_id } => {
        output.client_line(&format!("active thread is now {thread_id}")).ok();
        output.set_prompt(&thread_id);
    }
    ReaderEvent::ThreadList { thread_ids, next_cursor } => {
        // 显示线程列表
    }
}
```

### 6. 帮助输出

```rust
fn print_help(output: &Output) {
    let _ = output.client_line("commands:");
    let _ = output.client_line("  :help                 show this help");
    let _ = output.client_line("  :new                  start a new thread");
    let _ = output.client_line("  :resume <thread-id>   resume an existing thread");
    let _ = output.client_line("  :use <thread-id>      switch the active thread");
    let _ = output.client_line("  :refresh-thread       list available threads");
    let _ = output.client_line("  :quit                 exit");
    let _ = output.client_line("type a message to send it as a new turn");
}
```

## 具体技术实现

### 关键流程

**启动流程**：
```
parse CLI → spawn client → initialize → start/resume thread
                                              ↓
                                    start reader thread
                                              ↓
                                    main input loop
```

**消息发送流程**：
```
用户输入 → parse_input → InputAction::Message
                              ↓
                    client.send_turn(thread_id, message)
                              ↓
                    JSON-RPC request → app-server
```

**命令处理流程**：
```
用户输入 → parse_input → InputAction::Command
                              ↓
                    handle_command
                              ↓
              ┌───────────────┼───────────────┐
              ↓               ↓               ↓
           NewThread       Resume          Use
              ↓               ↓               ↓
    request_thread_start  request_thread_resume  use_thread
              ↓               ↓               ↓
         ReaderEvent::ThreadReady       立即更新 prompt
```

### 并发模型

```
主线程（main）:
    - 读取 stdin
    - 发送请求
    - 处理 ReaderEvent（通过 drain_events）

reader 线程（client.rs / reader.rs）:
    - 读取 stdout
    - 解析 JSON-RPC
    - 发送 ReaderEvent 到主线程
    - 自动响应审批请求
```

**同步机制**：
- `mpsc::channel`：reader → main 的单向事件流
- `Arc<Mutex<State>>`：共享状态（线程 ID、pending 请求）

### 数据结构关系

```
main()
    ├─ Cli                    // CLI 参数
    ├─ Output                 // 输出处理器（克隆共享）
    ├─ AppServerClient        // 客户端（mut）
    │   ├─ Arc<Mutex<State>>  // 共享状态
    │   └─ ...
    ├─ AskForApproval         // 审批策略
    └─ (mpsc::Sender, Receiver)  // 事件通道
```

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `client` | `client.rs` | `AppServerClient`, `build_thread_start_params`, `build_thread_resume_params` |
| `commands` | `commands.rs` | `InputAction`, `UserCommand`, `parse_input` |
| `output` | `output.rs` | `Output` |
| `state` | `state.rs` | `ReaderEvent` |

### 外部依赖

| Crate | 类型 | 用途 |
|-------|------|------|
| `clap` | CLI | 参数解析（derive 特性）|
| `anyhow` | 错误 | 错误处理和传播 |
| `codex-app-server-protocol` | 协议 | `AskForApproval` |

### 关键代码路径

**启动路径**：
1. `main:66` → `Cli::parse()`
2. `main:71-76` → `AppServerClient::spawn()`
3. `main:77` → `client.initialize()`
4. `main:79-94` → `start_thread()` / `resume_thread()`
5. `main:101-102` → `client.start_reader()`

**输入处理路径**：
1. `main:116-119` → `lines.next()` 读取输入
2. `main:121` → `parse_input(&line)`
3. `main:123-134` → 消息分支 → `client.send_turn()`
4. `main:136-139` → 命令分支 → `handle_command()`

**事件处理路径**：
1. `main:110` → `drain_events(&event_rx, &output)`
2. `main:251-282` → 匹配 `ReaderEvent` 类型

## 依赖与外部交互

### 子进程交互

**启动命令构建**（通过 `client.spawn`）：
```bash
{codex_bin} app-server [--config key=value ...]
```

**配置覆盖传递**：
```rust
for override_kv in config_overrides {
    cmd.arg("--config").arg(override_kv);
}
```

### 协议交互

**初始化握手**（`client.initialize()`）：
1. 发送 `ClientRequest::Initialize`
2. 接收 `InitializeResponse`
3. 发送 `ClientNotification::Initialized`

**线程管理**：
- `thread/start`：创建新会话
- `thread/resume`：恢复已有会话
- `thread/list`：获取会话列表

**消息发送**：
- `turn/start`：发送用户输入，启动新一轮对话

### 信号处理

**当前实现**：
- 无显式信号处理
- 依赖 `Drop` 实现（`client.shutdown()`）
- Ctrl+C 可能导致资源泄露

## 风险、边界与改进建议

### 当前风险

**1. 错误处理不一致**
```rust
// 某些错误使用 .ok() 静默忽略
output.client_line(&format!("...")).ok();
```
- 输出错误被忽略，用户可能看不到重要信息

**2. 无超时机制**
- `start_thread()` / `resume_thread()` 可能无限阻塞
- 服务端无响应时用户体验差

**3. 并发限制**
- 主循环是单线程的，一次只能处理一个命令
- 无法并发发送多个消息

**4. 资源泄露风险**
```rust
// 如果 main 提前返回（Err），shutdown 可能不被调用
client.initialize()?;  // 失败时 child 进程可能残留
```

### 边界情况

**1. EOF 处理**
```rust
let Some(line) = lines.next() else { break };
```
- 管道输入结束时正常退出
- 但可能丢失待处理响应

**2. 线程 ID 切换**
```rust
UserCommand::Use(thread_id) => {
    let known = client.use_thread(thread_id.clone());
    // ...
}
```
- `:use` 命令不验证线程是否存在
- 用户可能切换到无效线程后发送消息失败

**3. 审批策略与 auto-approve 的交互**
- `--approval-policy never` 与 `--auto-approve` 组合可能产生意外行为
- 当前实现中 `auto_approve` 仅影响 reader 线程的自动响应

### 改进建议

**1. 结构化日志**
```rust
// 建议：使用 tracing 替代 println/eprintln
use tracing::{info, error, warn};
```

**2. 超时机制**
```rust
// 建议：为同步调用添加超时
client.start_thread(...)
    .with_timeout(Duration::from_secs(30))
    .await?;
```

**3. 优雅关闭**
```rust
// 建议：使用 ctrlc crate 处理信号
ctrlc::set_handler(move || {
    shutdown_tx.send(()).ok();
})?;
```

**4. 配置验证**
```rust
// 建议：验证 codex_bin 存在性
if !Path::new(&cli.codex_bin).exists() {
    anyhow::bail!("codex binary not found: {}", cli.codex_bin);
}
```

**5. 命令历史**
```rust
// 建议：集成 rustyline 提供历史记录和编辑
use rustyline::DefaultEditor;
let mut rl = DefaultEditor::new()?;
let line = rl.readline(&prompt)?;
```

**6. 异步化**
```rust
// 建议：使用 tokio 实现真正的异步
#[tokio::main]
async fn main() -> Result<()> {
    // ...
}
```

### 代码质量

**优点**：
- 结构清晰，职责分离良好
- 使用 `?` 运算符进行错误传播
- 完整的 CLI 帮助

**可改进点**：
- 部分错误使用 `.ok()` 静默忽略
- 缺少结构化日志
- 无性能监控指标

### 与 AGENTS.md 规范符合度

检查项目规范：
- ✅ 使用 `format!` 内联变量（多处）
- ✅ 避免 `bool` 参数（使用 struct 封装）
- ✅ 使用 `anyhow` 进行错误处理
- ✅ 模块小于 500 LoC（实际 293 行）

无违规项。
