# codex-rs/app-server-test-client/src/lib.rs 研究文档

## 场景与职责

`codex-app-server-test-client` 是一个用于测试和调试 Codex App Server 的 CLI 工具。它作为 App Server 的客户端，通过 JSON-RPC over WebSocket 或 stdio 协议与 App Server 通信，用于：

1. **功能测试**：验证 App Server 的各种 API 功能（thread/turn、登录、模型列表等）
2. **集成测试**：与 App Server 进行端到端交互测试
3. **调试工具**：观察原始 JSON-RPC 消息流、模拟用户交互
4. **自动化测试**：支持 CI/CD 中的自动化测试场景

该 crate 既是库（`lib.rs`）也是可执行程序（`main.rs`），库部分提供了完整的客户端实现，可被其他测试代码复用。

## 功能点目的

### 1. 连接管理
- **WebSocket 连接**：连接到已运行的 App Server WebSocket 端点
- **stdio 连接**：启动 codex 二进制文件作为子进程，通过 stdin/stdout 通信
- **后台服务器管理**：支持启动后台 App Server 进程

### 2. CLI 命令集
| 命令 | 用途 |
|------|------|
| `serve` | 在后台启动 WebSocket App Server |
| `send-message` | 发送用户消息（V1 API） |
| `send-message-v2` | 发送用户消息（V2 API） |
| `resume-message-v2` | 恢复线程并发送消息 |
| `thread-resume` | 恢复线程并持续流式接收通知 |
| `watch` | 初始化连接并打印所有入站消息 |
| `trigger-cmd-approval` | 触发命令执行审批流程 |
| `trigger-patch-approval` | 触发文件变更审批流程 |
| `no-trigger-cmd-approval` | 测试不触发审批的场景 |
| `send-follow-up-v2` | 测试同一线程中的连续对话 |
| `trigger-zsh-fork-multi-cmd-approval` | 测试 zsh fork 多命令审批 |
| `test-login` | 测试 ChatGPT 登录流程 |
| `get-account-rate-limits` | 获取账户速率限制 |
| `model-list` | 列出可用模型 |
| `thread-list` | 列出存储的线程 |
| `thread-increment-elicitation` | 增加线程的 elicitation 暂停计数器 |
| `thread-decrement-elicitation` | 减少线程的 elicitation 暂停计数器 |
| `live-elicitation-timeout-pause` | 实时测试 elicitation 暂停超时机制 |

### 3. 核心客户端功能
- **JSON-RPC 请求/响应处理**：完整的请求-响应匹配机制
- **通知处理**：异步处理服务器推送的通知
- **审批自动化**：自动处理命令执行和文件变更审批请求
- **追踪支持**：集成 OpenTelemetry 追踪

## 具体技术实现

### 关键数据结构

```rust
// 端点枚举：支持两种连接方式
enum Endpoint {
    SpawnCodex(PathBuf),  // 启动 codex 二进制文件
    ConnectWs(String),    // 连接现有 WebSocket
}

// 传输层抽象
enum ClientTransport {
    Stdio {
        child: Child,
        stdin: Option<ChildStdin>,
        stdout: BufReader<ChildStdout>,
    },
    WebSocket {
        url: String,
        socket: Box<WebSocket<MaybeTlsStream<TcpStream>>>,
    },
}

// 主客户端结构
struct CodexClient {
    transport: ClientTransport,
    pending_notifications: VecDeque<JSONRPCNotification>,
    command_approval_behavior: CommandApprovalBehavior,
    command_approval_count: usize,
    command_approval_item_ids: Vec<String>,
    command_execution_statuses: Vec<CommandExecutionStatus>,
    command_execution_outputs: Vec<String>,
    // ... 其他状态字段
}

// 审批行为配置
enum CommandApprovalBehavior {
    AlwaysAccept,      // 总是接受
    AbortOn(usize),    // 在指定索引处中止
}
```

### 关键流程

#### 1. 连接建立流程
```rust
fn connect(endpoint: &Endpoint, config_overrides: &[String]) -> Result<Self> {
    match endpoint {
        Endpoint::SpawnCodex(codex_bin) => Self::spawn_stdio(codex_bin, config_overrides),
        Endpoint::ConnectWs(url) => Self::connect_websocket(url),
    }
}
```

**stdio 连接**：
1. 使用 `std::process::Command` 启动 codex 子进程
2. 配置 stdin/stdout 为管道模式
3. 设置 PATH 环境变量包含 codex 二进制目录
4. 传递 `--config` 配置覆盖参数

**WebSocket 连接**：
1. 使用 `tungstenite::connect` 建立 WebSocket 连接
2. 10 秒超时重试机制
3. 支持 TLS 和普通 TCP 连接

#### 2. 请求-响应流程
```rust
fn send_request<T>(&mut self, request: ClientRequest, request_id: RequestId, method: &str) -> Result<T> {
    // 1. 序列化请求并添加追踪上下文
    // 2. 通过 transport 发送
    // 3. 循环读取响应，匹配 request_id
    // 4. 处理中间的通知和服务器请求
}
```

#### 3. 通知流处理（stream_turn）
```rust
fn stream_turn(&mut self, thread_id: &str, turn_id: &str) -> Result<()> {
    loop {
        let notification = self.next_notification()?;
        match server_notification {
            ServerNotification::TurnCompleted(payload) => break,
            ServerNotification::AgentMessageDelta(delta) => print!("{}", delta.delta),
            ServerNotification::CommandExecutionOutputDelta(delta) => {
                self.note_helper_output(&delta.delta);
                print!("{}", delta.delta);
            }
            ServerNotification::ItemStarted(payload) => { /* 跟踪 item 状态 */ }
            ServerNotification::ItemCompleted(payload) => { /* 更新执行状态 */ }
            // ... 其他通知类型
        }
    }
}
```

#### 4. 审批处理流程
```rust
fn handle_command_execution_request_approval(&mut self, request_id: RequestId, params: CommandExecutionRequestApprovalParams) -> Result<()> {
    // 1. 打印审批详情（命令、工作目录、原因等）
    // 2. 根据 command_approval_behavior 决定决策
    // 3. 发送审批响应
    let decision = match self.command_approval_behavior {
        CommandApprovalBehavior::AlwaysAccept => CommandExecutionApprovalDecision::Accept,
        CommandApprovalBehavior::AbortOn(index) if self.command_approval_count == index => {
            CommandExecutionApprovalDecision::Cancel
        }
        _ => CommandExecutionApprovalDecision::Accept,
    };
    self.send_server_request_response(request_id, &response)?;
}
```

### 协议与命令

#### JSON-RPC 消息类型
- **ClientRequest**：客户端发起的请求（initialize、thread/start、turn/start 等）
- **ServerRequest**：服务器发起的请求（commandExecution/requestApproval、fileChange/requestApproval）
- **ServerNotification**：服务器推送的通知（turn/started、turn/completed、item/started 等）

#### V2 API 主要方法
| 方法 | 描述 |
|------|------|
| `initialize` | 初始化连接，交换能力信息 |
| `thread/start` | 创建新线程 |
| `thread/resume` | 恢复现有线程 |
| `thread/list` | 列出线程 |
| `turn/start` | 开始新 turn |
| `account/login/start` | 启动登录流程 |
| `account/rateLimits/read` | 获取速率限制 |
| `model/list` | 列出模型 |
| `thread/increment_elicitation` | 增加 elicitation 计数 |
| `thread/decrement_elicitation` | 减少 elicitation 计数 |

### 配置与参数

#### CLI 全局参数
- `--codex-bin`：指定 codex 二进制文件路径
- `--url`：指定 WebSocket URL
- `--config`：配置覆盖（可重复）
- `--dynamic-tools`：动态工具规范（JSON 或 @文件）

#### 通知过滤
```rust
const NOTIFICATIONS_TO_OPT_OUT: &[&str] = &[
    "command/exec/outputDelta",
    "item/agentMessage/delta",
    "item/plan/delta",
    "item/fileChange/outputDelta",
    "item/reasoning/summaryTextDelta",
    "item/reasoning/textDelta",
];
```

## 关键代码路径与文件引用

### 核心文件
- `codex-rs/app-server-test-client/src/lib.rs`：主库实现（约 2200 行）
- `codex-rs/app-server-test-client/src/main.rs`：入口点（7 行）
- `codex-rs/app-server-test-client/scripts/live_elicitation_hold.sh`：elicitation 测试辅助脚本

### 依赖 crate
| Crate | 用途 |
|-------|------|
| `codex-app-server-protocol` | JSON-RPC 协议定义（v1/v2 API） |
| `codex-core` | 核心配置加载 |
| `codex-otel` | OpenTelemetry 追踪 |
| `codex-protocol` | 核心协议类型（AskForApproval、SandboxPolicy 等） |
| `codex-utils-cli` | CLI 配置覆盖工具 |

### 协议相关文件
- `codex-rs/app-server-protocol/src/protocol/v2.rs`：V2 API 协议定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`：通用协议类型
- `codex-rs/app-server-protocol/src/protocol/v1.rs`：V1 API 协议定义

### 关键函数路径
```
run() -> match CliCommand:
    - serve() -> BackgroundAppServer::spawn()
    - send_message_v2() -> with_client() -> CodexClient::connect():
        - initialize()
        - thread_start()
        - turn_start()
        - stream_turn():
            - next_notification()
            - handle_server_request():
                - handle_command_execution_request_approval()
                - approve_file_change_request()
```

## 依赖与外部交互

### 外部进程交互
1. **codex 二进制文件**：通过 stdio 或 WebSocket 与 App Server 通信
2. **lsof/kill**：`serve` 命令使用 lsof 查找并杀死占用端口的进程
3. **nohup/sh**：后台启动 App Server

### 网络交互
1. **WebSocket 连接**：`ws://` 或 `wss://` 协议
2. **重试机制**：连接失败时 50ms 间隔重试，最多 10 秒

### 文件系统交互
1. **日志文件**：`/tmp/codex-app-server-test-client/app-server.log`
2. **动态工具文件**：通过 `@path` 语法读取 JSON 文件
3. **辅助脚本**：`scripts/live_elicitation_hold.sh`

### 环境变量
- `CODEX_BIN`：codex 二进制文件路径
- `CODEX_APP_SERVER_URL`：App Server WebSocket URL
- `CODEX_HOME`：配置目录

## 风险、边界与改进建议

### 已知风险

1. **进程管理风险**
   - `BackgroundAppServer` 和 `CodexClient` 的 Drop 实现使用 `kill()` 强制终止子进程
   - 存在资源泄漏风险，特别是在异常退出时
   - 建议：使用更优雅的进程生命周期管理，如进程组信号发送

2. **WebSocket 重连缺失**
   - 当前实现连接失败后直接报错，没有自动重连机制
   - 长时间运行的测试可能因网络波动失败
   - 建议：添加指数退避重连策略

3. **审批状态机复杂性**
   - `command_approval_behavior` 和 `command_approval_count` 的状态管理分散在多个函数中
   - 多线程并发测试时可能出现竞态条件
   - 建议：将审批逻辑抽取到独立的状态机结构

4. **硬编码路径**
   - `/tmp/codex-app-server-test-client` 是硬编码的临时目录
   - 在多用户环境可能冲突
   - 建议：使用 `tempfile` crate 生成唯一临时目录

### 边界情况

1. **消息乱序处理**
   - `pending_notifications` 队列用于缓存响应前的通知
   - 但队列大小无限制，极端情况下可能 OOM
   - 建议：添加队列大小限制和溢出策略

2. **stdio 缓冲区**
   - 大量输出时可能阻塞在管道缓冲区
   - 建议：使用异步 I/O 或独立线程消费 stdout

3. **WebSocket 帧处理**
   - 当前忽略 Binary/Ping/Pong 帧
   - 某些代理可能发送这些帧，导致意外行为
   - 建议：正确处理 Ping/Pong 以保持连接活跃

### 改进建议

1. **测试覆盖率**
   - 添加单元测试覆盖 JSON-RPC 序列化/反序列化
   - 添加模拟 App Server 用于离线测试

2. **可观测性**
   - 添加结构化日志（JSON 格式）便于解析
   - 支持导出测试结果为 JUnit/XML 格式

3. **配置管理**
   - 支持配置文件批量定义测试场景
   - 支持环境变量模板替换

4. **性能优化**
   - 对于高频通知场景，添加批处理或采样选项
   - 优化大消息体的内存分配

5. **安全加固**
   - 对动态工具 JSON 进行 Schema 验证
   - 限制脚本执行路径，防止路径遍历攻击

### 代码质量

1. **复杂度**：`lib.rs` 超过 2000 行，建议按功能拆分为子模块：
   - `client.rs`：CodexClient 实现
   - `commands.rs`：CLI 命令处理
   - `transport.rs`：传输层抽象
   - `tracing.rs`：追踪和日志

2. **错误处理**：大量使用 `anyhow::Result`，建议关键路径使用自定义错误类型以提供更详细的错误上下文

3. **文档**：缺少模块级和函数级文档，建议添加 `///` 文档注释
