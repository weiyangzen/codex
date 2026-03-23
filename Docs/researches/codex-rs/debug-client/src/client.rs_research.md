# client.rs 深度研究文档

## 场景与职责

`client.rs` 是 debug-client 的核心模块，负责与 Codex app-server 建立和管理 JSON-RPC 2.0 连接。它是整个 debug-client 与后端服务通信的桥梁，封装了进程管理、请求/响应处理、状态跟踪等底层细节。

**核心定位**：
- 作为 app-server 的子进程管理器，通过 stdin/stdout 进行双向通信
- 实现 JSON-RPC 2.0 协议的客户端侧（简化版，不包含 `"jsonrpc": "2.0"` 字段）
- 维护请求 ID 生成、待处理请求跟踪、线程状态管理
- 支持同步阻塞调用和异步非阻塞调用两种模式

## 功能点目的

### 1. AppServerClient 结构体

```rust
pub struct AppServerClient {
    child: Child,                                    // 子进程句柄
    stdin: Arc<Mutex<Option<ChildStdin>>>,          // 标准输入（线程安全）
    stdout: Option<BufReader<ChildStdout>>,         // 标准输出缓冲读取器
    next_request_id: AtomicI64,                     // 原子自增请求 ID
    state: Arc<Mutex<State>>,                       // 共享状态（线程安全）
    output: Output,                                 // 输出处理器
    filtered_output: bool,                          // 是否过滤输出
}
```

**设计意图**：
- 使用 `Arc<Mutex<...>>` 模式实现跨线程共享，支持 reader 线程和主线程并发访问
- `stdin` 使用 `Option` 包装支持"获取并关闭"语义（`take()`）
- `AtomicI64` 保证请求 ID 生成的线程安全性和单调递增

### 2. 进程生命周期管理

**spawn 方法**（行54-91）：
```rust
pub fn spawn(
    codex_bin: &str,
    config_overrides: &[String],
    output: Output,
    filtered_output: bool,
) -> Result<Self>
```

- 启动 `codex app-server` 子进程
- 通过 `--config key=value` 传递配置覆盖
- 设置 stdin/stdout 为管道模式，stderr 继承父进程
- 返回客户端实例，此时连接已建立但尚未初始化

**shutdown 方法**（行247-252）：
```rust
pub fn shutdown(&mut self) {
    if let Ok(mut stdin) = self.stdin.lock() {
        let _ = stdin.take();  // 关闭 stdin 触发服务端 EOF
    }
    let _ = self.child.wait();  // 等待子进程结束
}
```

### 3. 初始化握手（行93-117）

实现 LSP 风格的 initialize/initialized 握手：

```rust
pub fn initialize(&mut self) -> Result<()>
```

流程：
1. 发送 `ClientRequest::Initialize` 请求，携带客户端信息和能力
2. 等待并解析 `InitializeResponse`
3. 发送 `ClientNotification::Initialized` 通知（无需响应）

**能力声明**（行103-106）：
```rust
capabilities: Some(InitializeCapabilities {
    experimental_api: true,  // 启用实验性 API
    opt_out_notification_methods: None,
})
```

### 4. 线程生命周期管理

**同步方法**（阻塞等待响应）：
- `start_thread`（行119-132）：创建新线程，返回 thread_id
- `resume_thread`（行134-147）：恢复已有线程

**异步方法**（非阻塞，通过 reader 线程处理响应）：
- `request_thread_start`（行149-158）：发送 start 请求，注册 pending
- `request_thread_resume`（行160-169）：发送 resume 请求，注册 pending
- `request_thread_list`（行171-189）：获取线程列表

**设计模式**：同步方法用于启动时的强制等待，异步方法用于交互式命令避免阻塞输入循环。

### 5. 消息发送与接收

**发送**（行272-283）：
```rust
fn send<T: Serialize>(&self, value: &T) -> Result<()>
```
- 序列化为 JSON，追加换行符（行分隔协议）
- 通过 Mutex 锁定 stdin 写入

**同步接收**（行285-322）：
```rust
fn read_until_response(&mut self, request_id: &RequestId) -> Result<JSONRPCResponse>
```
- 循环读取行，解析 JSON-RPC 消息
- 匹配响应 ID，处理服务端请求（如审批请求）
- 非目标响应丢弃（简化实现）

### 6. 服务端请求处理（行325-379）

`handle_server_request` 函数处理服务端发起的请求：

```rust
fn handle_server_request(
    request: JSONRPCRequest,
    stdin: &Arc<Mutex<Option<ChildStdin>>>,
) -> Result<()>
```

当前支持：
- `CommandExecutionRequestApproval`：命令执行审批
- `FileChangeRequestApproval`：文件变更审批

**默认策略**：自动拒绝（`Decline`），除非用户启用 `--auto-approve`

### 7. 参数构建辅助函数

**build_thread_start_params**（行381-395）：
```rust
pub fn build_thread_start_params(
    approval_policy: AskForApproval,
    model: Option<String>,
    model_provider: Option<String>,
    cwd: Option<String>,
) -> ThreadStartParams
```

**build_thread_resume_params**（行397-412）：
- 类似结构，额外需要 `thread_id`

## 具体技术实现

### 关键流程

**1. 连接建立流程**：
```
spawn() -> initialize() -> start_thread()/resume_thread()
   ↓           ↓                ↓
启动进程    握手协议         创建/恢复会话
```

**2. 消息流架构**：
```
主线程 → stdin → app-server
         ↑           ↓
      reader线程 ← stdout
         ↓
    Sender<ReaderEvent> → main loop
```

**3. 请求 ID 生成**（行267-270）：
```rust
fn next_request_id(&self) -> RequestId {
    let id = self.next_request_id.fetch_add(1, Ordering::SeqCst);
    RequestId::Integer(id)
}
```
- 使用 `SeqCst` 顺序一致性，确保多线程下 ID 唯一且单调

### 数据结构

**State 跟踪**（来自 state.rs）：
```rust
pub struct State {
    pub pending: HashMap<RequestId, PendingRequest>,  // 待处理请求
    pub thread_id: Option<String>,                     // 当前线程
    pub known_threads: Vec<String>,                    // 已知线程列表
}

pub enum PendingRequest {
    Start,   // thread/start 请求
    Resume,  // thread/resume 请求
    List,    // thread/list 请求
}
```

### 协议细节

**JSON-RPC 消息类型**（来自 jsonrpc_lite.rs）：
```rust
pub enum JSONRPCMessage {
    Request(JSONRPCRequest),       // 服务端 → 客户端的请求
    Notification(JSONRPCNotification),  // 单向通知
    Response(JSONRPCResponse),     // 响应
    Error(JSONRPCError),           // 错误
}
```

**关键协议方法**：
| 方法 | 方向 | 用途 |
|------|------|------|
| `thread/start` | C→S | 创建新线程 |
| `thread/resume` | C→S | 恢复线程 |
| `thread/list` | C→S | 列出线程 |
| `turn/start` | C→S | 发送用户输入 |
| `item/commandExecution/requestApproval` | S→C | 请求命令审批 |
| `item/fileChange/requestApproval` | S→C | 请求文件变更审批 |

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `state.rs` | `State`, `PendingRequest`, `ReaderEvent` 定义 |
| `output.rs` | `Output`, `LabelColor` 输出处理 |
| `reader.rs` | `start_reader` 启动后台读取线程 |

### 外部依赖

| Crate | 类型 | 用途 |
|-------|------|------|
| `codex-app-server-protocol` | 协议 | JSON-RPC 类型、请求/响应结构 |
| `anyhow` | 错误 | 错误处理和上下文 |
| `serde`/`serde_json` | 序列化 | JSON 编码/解码 |

### 关键代码路径

**启动流程**：
1. `main.rs:71-76` → `AppServerClient::spawn()`
2. `main.rs:77` → `client.initialize()`
3. `main.rs:79-94` → `start_thread()` / `resume_thread()`

**消息发送**：
1. `main.rs:130` → `client.send_turn()`
2. `client.rs:191-207` → 构建 `TurnStartParams` 并发送

**响应处理**：
1. `client.rs:209-226` → `start_reader()` 启动后台线程
2. `reader.rs:34-107` → 读取循环
3. `reader.rs:144-207` → `handle_response()` 分发到 `ReaderEvent`

## 依赖与外部交互

### 子进程交互

**启动命令**：
```bash
codex app-server --config key=value ...
```

**通信协议**：
- 输入：JSON-RPC 消息 + `\n`
- 输出：行分隔的 JSON-RPC 消息
- 编码：UTF-8

### 协议版本

仅支持 **app-server protocol v2**，不兼容 v1。v2 协议特点：
- 使用 camelCase 命名
- 支持实验性 API 标记
- 线程化会话管理

### 线程安全保证

| 组件 | 同步机制 | 说明 |
|------|----------|------|
| `stdin` | `Arc<Mutex<Option<...>>>` | 主线程和 reader 线程都可能写入 |
| `state` | `Arc<Mutex<State>>` | 主线程读取，reader 线程写入 |
| `next_request_id` | `AtomicI64` | 无锁原子操作 |

## 风险、边界与改进建议

### 当前风险

**1. 错误处理简化**
```rust
// client.rs:307-308
let message = match serde_json::from_str::<JSONRPCMessage>(line) {
    Ok(message) => message,
    Err(_) => continue,  // 静默丢弃解析错误
};
```
- 无法解析的行被静默忽略，可能丢失重要信息

**2. 服务端请求处理局限**
- `handle_server_request` 仅处理审批请求，其他请求类型被忽略
- 自动拒绝策略可能不符合用户预期

**3. 响应匹配严格性**
```rust
// client.rs:311-314
JSONRPCMessage::Response(response) => {
    if &response.id == request_id {
        return Ok(response);
    }
}
```
- 非目标响应被丢弃，不缓存或处理

### 边界情况

**1. 进程崩溃处理**
- `read_until_response` 在 EOF 时返回错误（行296-298）
- 但 reader 线程的 EOF 处理仅打印错误并退出（reader.rs:60-64）

**2. 并发请求限制**
- 同步方法阻塞时，无法处理其他响应
- 实际限制取决于调用模式（目前交互式使用无并发）

**3. 大消息处理**
- 使用 `BufReader` 缓冲，但无消息大小限制
- 极端大的 JSON 可能消耗大量内存

### 改进建议

**1. 错误可见性**
```rust
// 建议：添加日志或回调
Err(e) => {
    eprintln!("JSON parse error: {e}, line: {line}");
    continue;
}
```

**2. 响应缓存机制**
- 对于非目标响应，可缓存到队列供后续匹配
- 避免在并发场景下丢失响应

**3. 心跳/保活机制**
- 当前无心跳检测，依赖进程退出信号
- 建议添加定期 ping 或利用 TCP keepalive（如使用网络传输）

**4. 审批交互改进**
- 当前自动拒绝策略过于简单
- 可考虑添加交互式审批（通过主线程通道转发）

**5. 配置验证**
- `spawn` 方法不验证 `codex_bin` 是否存在
- 建议添加前置检查，提供清晰错误信息

### 测试覆盖

当前 `client.rs` 无单元测试，测试依赖：
- 集成测试在 `app-server` crate 中
- 手动测试通过 `cargo run -p codex-debug-client`

建议添加：
- Mock app-server 进行协议测试
- 状态机转换测试
- 错误路径测试
