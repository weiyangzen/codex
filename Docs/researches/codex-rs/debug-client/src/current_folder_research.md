# codex-rs/debug-client 深度研究文档

## 概述

`codex-debug-client` 是一个用于 `codex app-server` 的极简交互式调试客户端，专为协议 v2 设计。它通过 JSON-RPC 协议与 app-server 通信，提供交互式的线程管理、消息发送和实时事件处理功能。

---

## 一、场景与职责

### 1.1 定位与目标场景

| 维度 | 说明 |
|------|------|
| **定位** | 轻量级调试工具，用于开发和测试 `codex app-server` 的协议 v2 功能 |
| **目标用户** | 开发者、测试人员、协议集成者 |
| **运行模式** | 命令行交互式 REPL |
| **协议版本** | 仅支持 app-server-protocol v2 |

### 1.2 核心职责

1. **进程管理**：启动并管理 `codex app-server` 子进程
2. **协议握手**：执行 initialize/initialized 握手流程
3. **线程生命周期管理**：创建、恢复、切换、列举线程
4. **消息交互**：发送用户输入（turn/start）到指定线程
5. **事件处理**：异步读取并显示服务器通知和响应
6. **审批自动响应**：自动处理命令执行和文件变更的审批请求

### 1.3 与 TUI 的对比

| 特性 | debug-client | TUI |
|------|-------------|-----|
| 界面 | 命令行 REPL | 全屏终端 UI |
| 功能范围 | 核心协议调试 | 完整用户体验 |
| 输出模式 | 原始 JSON / 过滤模式 | 富文本渲染 |
| 使用场景 | 开发调试 | 终端用户 |
| 依赖复杂度 | 低 | 高（ratatui 等） |

---

## 二、功能点目的

### 2.1 命令行参数

| 参数 | 类型 | 默认值 | 用途 |
|------|------|--------|------|
| `--codex-bin` | String | "codex" | 指定 codex CLI 二进制文件路径 |
| `-c, --config` | Vec<String> | [] | 传递给 codex 的 `--config key=value` 覆盖 |
| `--thread-id` | Option<String> | None | 恢复现有线程而非创建新线程 |
| `--approval-policy` | String | "on-request" | 设置线程的审批策略 |
| `--auto-approve` | bool | false | 自动批准命令/文件变更请求 |
| `--final-only` | bool | false | 仅显示最终助手消息和工具调用 |
| `--model` | Option<String> | None | 可选的模型覆盖 |
| `--model-provider` | Option<String> | None | 可选的模型提供商覆盖 |
| `--cwd` | Option<String> | None | 可选的工作目录覆盖 |

### 2.2 交互式命令

| 命令 | 语法 | 功能 |
|------|------|------|
| 帮助 | `:help` / `:h` | 显示帮助信息 |
| 退出 | `:quit` / `:q` / `:exit` | 退出客户端 |
| 新建线程 | `:new` | 请求启动新线程 |
| 恢复线程 | `:resume <thread-id>` | 恢复指定线程 |
| 切换线程 | `:use <thread-id>` | 切换当前活动线程 |
| 刷新线程列表 | `:refresh-thread` | 列举可用线程 |
| 发送消息 | 直接输入文本 | 发送用户输入到当前线程 |

### 2.3 审批策略支持

客户端支持解析以下审批策略：
- `untrusted` / `unless-trusted` → `AskForApproval::UnlessTrusted`
- `on-failure` / `onFailure` → `AskForApproval::OnFailure`
- `on-request` / `onRequest` → `AskForApproval::OnRequest`（默认）
- `never` → `AskForApproval::Never`

---

## 三、具体技术实现

### 3.1 模块架构

```
codex-debug-client/
├── src/
│   ├── main.rs      # CLI 入口、主事件循环
│   ├── client.rs    # AppServerClient 实现（JSON-RPC 通信）
│   ├── commands.rs  # 命令解析（InputAction/UserCommand）
│   ├── output.rs    # 终端输出管理（提示符、颜色）
│   ├── reader.rs    # 异步读取服务器响应
│   └── state.rs     # 共享状态管理
├── Cargo.toml
└── README.md
```

### 3.2 核心数据结构

#### 3.2.1 客户端状态（State）

```rust
#[derive(Debug, Default)]
pub struct State {
    pub pending: HashMap<RequestId, PendingRequest>,  // 追踪待处理的请求
    pub thread_id: Option<String>,                     // 当前活动线程 ID
    pub known_threads: Vec<String>,                   // 已知的线程列表
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PendingRequest {
    Start,   // thread/start 请求
    Resume,  // thread/resume 请求
    List,    // thread/list 请求
}
```

#### 3.2.2 读取器事件（ReaderEvent）

```rust
#[derive(Debug, Clone)]
pub enum ReaderEvent {
    ThreadReady { thread_id: String },
    ThreadList { thread_ids: Vec<String>, next_cursor: Option<String> },
}
```

#### 3.2.3 输入动作（InputAction）

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InputAction {
    Message(String),           // 普通用户消息
    Command(UserCommand),      // 冒号命令
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UserCommand {
    Help,
    Quit,
    NewThread,
    Resume(String),
    Use(String),
    RefreshThread,
}
```

### 3.3 关键流程

#### 3.3.1 初始化流程

```
main()
  ├── 解析 CLI 参数 (Cli::parse)
  ├── 创建 Output 实例
  ├── 解析 approval_policy
  ├── AppServerClient::spawn()
  │   ├── 启动 codex app-server 子进程
  │   ├── 获取 stdin/stdout 管道
  │   └── 初始化状态
  ├── client.initialize()
  │   ├── 发送 ClientRequest::Initialize
  │   ├── 等待 InitializeResponse
  │   └── 发送 ClientNotification::Initialized
  ├── 启动新线程或恢复现有线程
  │   ├── start_thread() / resume_thread()
  │   └── 发送 thread/start 或 thread/resume 请求
  ├── 启动读取器线程
  │   └── start_reader() - 异步处理服务器消息
  └── 进入主事件循环
```

#### 3.3.2 主事件循环

```rust
loop {
    // 1. 排空所有待处理事件
    drain_events(&event_rx, &output);
    
    // 2. 显示提示符
    output.prompt(&prompt_thread).ok();
    
    // 3. 读取用户输入
    let line = lines.next().transpose()?;
    
    // 4. 解析输入
    match parse_input(&line) {
        Ok(None) => continue,  // 空输入
        Ok(Some(InputAction::Message(msg))) => {
            // 发送 turn/start 请求
            client.send_turn(&active_thread, msg)?;
        }
        Ok(Some(InputAction::Command(cmd))) => {
            // 处理命令
            if !handle_command(cmd, &client, &output, ...) {
                break;  // 退出命令
            }
        }
        Err(err) => output.client_line(&err.message()).ok(),
    }
}
```

#### 3.3.3 服务器消息处理流程（reader.rs）

```rust
start_reader()
  └── 在新线程中循环:
      ├── 读取一行从 stdout
      ├── 解析为 JSONRPCMessage
      └── 根据消息类型分发:
          ├── Request -> handle_server_request()
          │   ├── CommandExecutionRequestApproval -> 发送自动响应
          │   └── FileChangeRequestApproval -> 发送自动响应
          ├── Response -> handle_response()
          │   ├── PendingRequest::Start -> 更新状态，发送 ThreadReady 事件
          │   ├── PendingRequest::Resume -> 更新状态，发送 ThreadReady 事件
          │   └── PendingRequest::List -> 发送 ThreadList 事件
          └── Notification -> handle_filtered_notification() (如果 final_only)
              └── ItemCompleted -> emit_filtered_item() 格式化输出
```

### 3.4 协议交互细节

#### 3.4.1 使用的 app-server-protocol v2 类型

**请求类型（ClientRequest）：**
- `Initialize` - 初始化握手
- `ThreadStart` / `ThreadResume` - 线程生命周期
- `ThreadList` - 列举线程
- `TurnStart` - 发送用户输入

**响应类型：**
- `InitializeResponse`
- `ThreadStartResponse` / `ThreadResumeResponse`
- `ThreadListResponse`

**服务器请求（ServerRequest）：**
- `CommandExecutionRequestApproval` - 命令执行审批
- `FileChangeRequestApproval` - 文件变更审批

**通知（ServerNotification）：**
- `ItemCompleted` - 项目完成（用于 final-only 模式）

#### 3.4.2 线程启动参数构建

```rust
pub fn build_thread_start_params(
    approval_policy: AskForApproval,
    model: Option<String>,
    model_provider: Option<String>,
    cwd: Option<String>,
) -> ThreadStartParams {
    ThreadStartParams {
        model,
        model_provider,
        cwd,
        approval_policy: Some(approval_policy),
        experimental_raw_events: false,
        ..Default::default()
    }
}
```

### 3.5 输出管理

#### 3.5.1 输出结构

```rust
#[derive(Clone, Debug)]
pub struct Output {
    lock: Arc<Mutex<()>>,           // 输出同步锁
    prompt: Arc<Mutex<PromptState>>, // 提示符状态
    color: bool,                    // 是否启用颜色
}

struct PromptState {
    thread_id: Option<String>,
    visible: bool,
}
```

#### 3.5.2 输出方法

| 方法 | 输出目标 | 用途 |
|------|----------|------|
| `server_line()` | stdout | 服务器原始 JSON |
| `client_line()` | stderr | 客户端消息、错误 |
| `prompt()` | stderr | 显示提示符 `(thread-id)> ` |

#### 3.5.3 颜色标签

```rust
pub enum LabelColor {
    Assistant,  // 绿色 (32)
    Tool,       // 青色 (36)
    ToolMeta,   // 黄色 (33)
    Thread,     // 蓝色 (34)
}
```

### 3.6 过滤输出模式（final-only）

当启用 `--final-only` 时，客户端：
1. 抑制原始服务器 JSON 输出
2. 仅处理 `ItemCompleted` 通知
3. 格式化并显示以下项目类型：
   - `AgentMessage` - 助手消息
   - `Plan` - 计划
   - `CommandExecution` - 命令执行（含退出码、输出）
   - `FileChange` - 文件变更
   - `McpToolCall` - MCP 工具调用

---

## 四、关键代码路径与文件引用

### 4.1 文件引用表

| 文件 | 行数 | 核心功能 |
|------|------|----------|
| `main.rs` | 293 | CLI 入口、主循环、命令处理 |
| `client.rs` | 412 | AppServerClient、JSON-RPC 通信 |
| `commands.rs` | 156 | 输入解析、命令定义、单元测试 |
| `output.rs` | 121 | 终端输出、提示符、颜色 |
| `reader.rs` | 337 | 异步读取、服务器消息处理 |
| `state.rs` | 28 | 共享状态、事件类型 |

### 4.2 关键代码路径

#### 4.2.1 启动子进程

```rust
// client.rs:54-91
pub fn spawn(codex_bin: &str, config_overrides: &[String], ...) -> Result<Self> {
    let mut cmd = Command::new(codex_bin);
    for override_kv in config_overrides {
        cmd.arg("--config").arg(override_kv);
    }
    
    let mut child = cmd
        .arg("app-server")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())  // 继承 stderr 用于调试
        .spawn()?;
    // ...
}
```

#### 4.2.2 发送请求

```rust
// client.rs:272-283
fn send<T: Serialize>(&self, value: &T) -> Result<()> {
    let json = serde_json::to_string(value)?;
    let mut line = json;
    line.push('\n');
    let mut stdin = self.stdin.lock()?;
    let Some(stdin) = stdin.as_mut() else {
        anyhow::bail!("stdin already closed");
    };
    stdin.write_all(line.as_bytes())?;
    stdin.flush()?;
    Ok(())
}
```

#### 4.2.3 同步等待响应

```rust
// client.rs:285-322
fn read_until_response(&mut self, request_id: &RequestId) -> Result<JSONRPCResponse> {
    loop {
        buffer.clear();
        let bytes = reader.read_line(&mut buffer)?;
        if bytes == 0 {
            anyhow::bail!("server closed stdout while awaiting response");
        }
        
        let line = buffer.trim_end_matches(['\n', '\r']);
        if !line.is_empty() && !self.filtered_output {
            let _ = output.server_line(line);
        }
        
        let message = match serde_json::from_str::<JSONRPCMessage>(line) {
            Ok(message) => message,
            Err(_) => continue,
        };
        
        match message {
            JSONRPCMessage::Response(response) => {
                if &response.id == request_id {
                    return Ok(response);
                }
            }
            // 处理服务器请求...
            _ => {}
        }
    }
}
```

#### 4.2.4 自动审批处理

```rust
// reader.rs:109-142
fn handle_server_request(
    request: JSONRPCRequest,
    command_decision: &CommandExecutionApprovalDecision,
    file_decision: &FileChangeApprovalDecision,
    stdin: &Arc<Mutex<Option<ChildStdin>>>,
    output: &Output,
) -> anyhow::Result<()> {
    match server_request {
        ServerRequest::CommandExecutionRequestApproval { request_id, params } => {
            let response = CommandExecutionRequestApprovalResponse {
                decision: command_decision.clone(),  // Accept 或 Decline
            };
            output.client_line(&format!("auto-response for command approval..."))?;
            send_response(stdin, request_id, response)
        }
        // ...
    }
}
```

---

## 五、依赖与外部交互

### 5.1 依赖清单

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `clap` | 命令行参数解析 |
| `codex-app-server-protocol` | 协议类型定义（v1/v2） |
| `serde` / `serde_json` | 序列化/反序列化 |

### 5.2 外部交互

#### 5.2.1 与子进程交互

```
┌─────────────────┐         stdin          ┌─────────────────┐
│  debug-client   │ ─────────────────────> │  codex app-server│
│                 │ <───────────────────── │                 │
└─────────────────┘         stdout         └─────────────────┘
                                    stderr (继承到终端)
```

#### 5.2.2 与 app-server-protocol 的关系

```
codex-debug-client
    ├── 使用 ClientRequest / ClientNotification 发送消息
    ├── 使用 ServerRequest / ServerNotification 接收消息
    ├── 使用 ThreadStartParams / ThreadResumeParams 启动/恢复线程
    ├── 使用 TurnStartParams 发送用户输入
    └── 使用 ThreadItem 处理过滤输出
```

#### 5.2.3 协议版本兼容性

- **仅支持 v2**：debug-client 明确设计为仅支持 app-server-protocol v2
- **实验性功能**：通过 `InitializeCapabilities::experimental_api: true` 启用

### 5.3 调用方分析

当前项目中，`codex-debug-client` 是一个独立的可执行 crate，没有内部调用方。它是为以下场景设计的：

1. **开发者调试**：直接运行 `cargo run -p codex-debug-client`
2. **CI 测试**：可用于自动化协议测试
3. **协议文档示例**：作为协议 v2 的参考实现

---

## 六、风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 同步阻塞风险

**问题**：`read_until_response()` 在主线程中同步阻塞读取响应。

```rust
// client.rs:285-322
fn read_until_response(...) -> Result<JSONRPCResponse> {
    loop {
        let bytes = reader.read_line(&mut buffer)?;  // 阻塞
        // ...
    }
}
```

**影响**：如果在初始化或线程启动期间服务器无响应，客户端将挂起。

**缓解**：仅用于初始化阶段，后续使用异步读取器。

#### 6.1.2 锁中毒风险

多处使用 `lock().expect("... lock poisoned")`，如果某个线程 panic，锁将永久中毒。

#### 6.1.3 错误处理简化

许多错误仅通过 `output.client_line(&format!("...")).ok()` 输出，没有更健壮的错误恢复机制。

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| 服务器进程崩溃 | 读取器线程检测到 EOF，退出循环 |
| 无效 JSON | 忽略并继续读取下一行 |
| 未知线程 ID | `:use` 允许切换到未知线程，但会显示警告 |
| 无活动线程时发送消息 | 显示错误提示，要求使用 `:new` 或 `:resume` |
| 审批请求时 stdin 已关闭 | 返回错误，但通常不会导致崩溃 |

### 6.3 改进建议

#### 6.3.1 高优先级

1. **添加超时机制**
   ```rust
   // 为同步操作添加超时
   fn read_until_response_with_timeout(..., timeout: Duration) -> Result<...>
   ```

2. **改进锁中毒处理**
   ```rust
   // 使用 parking_lot 或更优雅的错误处理
   let state = self.state.lock().map_err(|_| Poisoned)?;
   ```

3. **添加重连支持**
   - 当前服务器崩溃后需要重启客户端
   - 可考虑添加自动重连机制

#### 6.3.2 中优先级

4. **增强过滤输出模式**
   - 支持更多 ThreadItem 类型的格式化
   - 添加时间戳显示选项
   - 支持输出到文件

5. **改进命令解析**
   - 支持引号参数（当前 `:resume "thread id"` 会失败）
   - 添加命令历史（readline 支持）

6. **配置持久化**
   - 保存最后使用的线程 ID
   - 保存命令历史

#### 6.3.3 低优先级

7. **WebSocket 支持**
   - 当前仅支持 stdio 传输
   - 可考虑添加 WebSocket 客户端模式

8. **脚本模式**
   - 支持从文件读取命令序列
   - 支持非交互式批处理

### 6.4 代码质量建议

1. **测试覆盖**
   - 当前仅有 `commands.rs` 有单元测试
   - 建议添加集成测试（使用 mock server）

2. **文档**
   - 添加更多内联文档
   - 添加架构图

3. **日志**
   - 当前使用简单的 stderr 输出
   - 可考虑集成 tracing

---

## 七、附录

### 7.1 协议 v2 关键类型速查

```rust
// ThreadStartParams (app-server-protocol/src/protocol/v2.rs:2449)
pub struct ThreadStartParams {
    pub model: Option<String>,
    pub model_provider: Option<String>,
    pub cwd: Option<String>,
    pub approval_policy: Option<AskForApproval>,
    pub sandbox: Option<SandboxMode>,
    // ... 更多字段
}

// ThreadItem 枚举 (app-server-protocol/src/protocol/v2.rs:4121)
pub enum ThreadItem {
    UserMessage { id: String, content: Vec<UserInput> },
    AgentMessage { id: String, text: String, ... },
    CommandExecution { id: String, command: String, ... },
    FileChange { id: String, changes: Vec<FileUpdateChange>, ... },
    // ... 更多变体
}
```

### 7.2 相关文件路径

```
codex-rs/
├── debug-client/
│   ├── src/
│   │   ├── main.rs
│   │   ├── client.rs
│   │   ├── commands.rs
│   │   ├── output.rs
│   │   ├── reader.rs
│   │   └── state.rs
│   ├── Cargo.toml
│   └── README.md
├── app-server-protocol/
│   └── src/
│       ├── protocol/
│       │   ├── v2.rs       # 协议 v2 类型定义
│       │   └── common.rs   # ClientRequest/ServerRequest 定义
│       └── lib.rs
└── app-server/
    └── src/
        ├── main.rs         # app-server 入口
        └── lib.rs          # 服务器实现
```

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/debug-client/src @ 研究时 HEAD*
