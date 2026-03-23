# mcp_process.rs 研究文档

## 场景与职责

`mcp_process.rs` 实现了 `McpProcess` 结构体，是 MCP（Model Context Protocol）服务器集成测试的核心基础设施。它负责：

1. **进程生命周期管理**: 启动、通信和终止 MCP 服务器子进程
2. **JSON-RPC 通信**: 通过 stdin/stdout 与 MCP 服务器进行双向通信
3. **MCP 协议握手**: 实现初始化握手流程
4. **消息路由**: 区分和处理请求、响应、通知三种消息类型

该模块是测试代码与 MCP 服务器之间的桥梁，使测试能够以编程方式控制 MCP 服务器并验证其行为。

## 功能点目的

### 1. 进程管理
- 启动 `codex-mcp-server` 二进制文件作为子进程
- 配置环境变量（如 `CODEX_HOME`、`RUST_LOG`）
- 支持环境变量覆盖（用于测试不同配置场景）
- 实现进程清理（`Drop` trait）防止僵尸进程

### 2. JSON-RPC 通信
- 通过 stdin 发送 JSON-RPC 消息
- 通过 stdout 接收 JSON-RPC 消息
- 转发 stderr 到测试输出（便于调试）
- 实现消息序列化和反序列化

### 3. MCP 协议支持
- 实现 `initialize` 握手
- 发送 `tools/call` 请求（`codex` 工具调用）
- 处理 `elicitation/create` 请求（执行/补丁审批）
- 监听 `task_complete` 通知

### 4. 消息流控制
- 按 ID 匹配请求和响应
- 过滤通知消息
- 支持轮询读取直到特定消息类型

## 具体技术实现

### McpProcess 结构体

```rust
pub struct McpProcess {
    next_request_id: AtomicI64,           // 原子计数器，生成唯一请求 ID
    #[allow(dead_code)]
    process: Child,                       // 保留进程句柄直到 Drop
    stdin: ChildStdin,                    // 标准输入，用于发送消息
    stdout: BufReader<ChildStdout>,       // 标准输出，用于接收消息
}
```

### 进程创建流程

```rust
pub async fn new_with_env(
    codex_home: &Path,
    env_overrides: &[(&str, Option<&str>)],  // 支持设置/删除环境变量
) -> anyhow::Result<Self> {
    // 1. 查找 codex-mcp-server 二进制文件
    let program = codex_utils_cargo_bin::cargo_bin("codex-mcp-server")?;
    
    // 2. 配置命令
    let mut cmd = Command::new(program);
    cmd.stdin(Stdio::piped())
       .stdout(Stdio::piped())
       .stderr(Stdio::piped())
       .env("CODEX_HOME", codex_home)
       .env("RUST_LOG", "debug")
       .kill_on_drop(true);  // Tokio 最佳努力清理
    
    // 3. 应用环境变量覆盖
    for (k, v) in env_overrides {
        match v {
            Some(val) => cmd.env(k, val),
            None => cmd.env_remove(k),
        }
    }
    
    // 4. 启动进程并获取管道
    let mut process = cmd.spawn()?;
    let stdin = process.stdin.take().ok_or_else(|| ...)?;
    let stdout = process.stdout.take().ok_or_else(|| ...)?;
    
    // 5. 启动 stderr 转发任务
    if let Some(stderr) = process.stderr.take() {
        tokio::spawn(async move {
            while let Ok(Some(line)) = stderr_reader.next_line().await {
                eprintln!("[mcp stderr] {line}");
            }
        });
    }
    
    Ok(Self { ... })
}
```

### MCP 初始化握手

```rust
pub async fn initialize(&mut self) -> anyhow::Result<()> {
    // 1. 构建 Initialize 请求
    let request_id = self.next_request_id.fetch_add(1, Ordering::Relaxed);
    let params = InitializeRequestParams {
        capabilities: ClientCapabilities {
            elicitation: Some(ElicitationCapability {
                form: Some(FormElicitationCapability { ... }),
                url: None,
            }),
            ...
        },
        client_info: Implementation { ... },
        protocol_version: ProtocolVersion::V_2025_03_26,
    };
    
    // 2. 发送请求
    self.send_jsonrpc_message(JsonRpcMessage::Request(...)).await?;
    
    // 3. 读取响应并验证
    let initialized = self.read_jsonrpc_message().await?;
    // 验证 jsonrpc 版本、ID、serverInfo 等字段
    
    // 4. 发送 initialized 通知（握手完成确认）
    self.send_jsonrpc_message(JsonRpcMessage::Notification(...)).await?;
    
    Ok(())
}
```

### 工具调用流程

```rust
pub async fn send_codex_tool_call(
    &mut self,
    params: CodexToolCallParam,
) -> anyhow::Result<i64> {
    // 构建 tools/call 请求参数
    let codex_tool_call_params = CallToolRequestParams {
        name: "codex".into(),
        arguments: Some(serde_json::to_value(params)?.as_object().unwrap().clone()),
        ...
    };
    
    // 发送请求并返回 request_id（用于后续匹配响应）
    self.send_request("tools/call", Some(...)).await
}
```

### 消息读取和过滤

```rust
pub async fn read_stream_until_request_message(
    &mut self,
) -> anyhow::Result<JsonRpcRequest<CustomRequest>> {
    loop {
        let message = self.read_jsonrpc_message().await?;
        match message {
            JsonRpcMessage::Notification(_) => {
                eprintln!("notification: {message:?}");  // 记录通知，继续轮询
            }
            JsonRpcMessage::Request(jsonrpc_request) => {
                return Ok(jsonrpc_request);  // 返回请求
            }
            // 错误类型会导致测试失败
            _ => anyhow::bail!("unexpected message type"),
        }
    }
}

pub async fn read_stream_until_response_message(
    &mut self,
    request_id: RequestId,  // 指定要匹配的请求 ID
) -> anyhow::Result<JsonRpcResponse<serde_json::Value>> {
    loop {
        let message = self.read_jsonrpc_message().await?;
        match message {
            JsonRpcMessage::Response(jsonrpc_response) => {
                if jsonrpc_response.id == request_id {
                    return Ok(jsonrpc_response);  // 匹配到指定 ID 的响应
                }
            }
            // 其他类型处理...
        }
    }
}
```

### 进程清理（Drop 实现）

```rust
impl Drop for McpProcess {
    fn drop(&mut self) {
        // 1. 请求终止
        let _ = self.process.start_kill();
        
        // 2. 同步等待进程退出（最多 5 秒）
        let start = std::time::Instant::now();
        let timeout = std::time::Duration::from_secs(5);
        while start.elapsed() < timeout {
            match self.process.try_wait() {
                Ok(Some(_)) => return,  // 进程已退出
                Ok(None) => std::thread::sleep(std::time::Duration::from_millis(10)),
                Err(_) => return,
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 文件依赖图

```
mcp_process.rs
├── 使用:
│   ├── rmcp::model::* (MCP 协议类型)
│   ├── codex_mcp_server::CodexToolCallParam (工具调用参数)
│   ├── codex_utils_cargo_bin::cargo_bin (二进制定位)
│   ├── tokio::process::* (异步进程)
│   └── serde_json (JSON 处理)
├── 被使用:
│   └── lib.rs (重新导出 McpProcess)
└── 测试使用:
    └── tests/suite/codex_tool.rs
```

### 关键类型映射

| 本文件类型 | 来源 | 用途 |
|-----------|------|------|
| `JsonRpcMessage` | `rmcp::model` | JSON-RPC 消息枚举 |
| `JsonRpcRequest` | `rmcp::model` | 请求消息 |
| `JsonRpcResponse` | `rmcp::model` | 响应消息 |
| `JsonRpcNotification` | `rmcp::model` | 通知消息 |
| `InitializeRequestParams` | `rmcp::model` | 初始化参数 |
| `ClientCapabilities` | `rmcp::model` | 客户端能力声明 |
| `CodexToolCallParam` | `codex_mcp_server` | 工具调用配置 |
| `CallToolRequestParams` | `rmcp::model` | 工具调用请求 |

### 协议版本

```rust
protocol_version: ProtocolVersion::V_2025_03_26
```

使用 MCP 协议版本 2025-03-26，这是较新的协议版本。

## 依赖与外部交互

### 外部 crate 依赖

1. **rmcp**: MCP 协议的 Rust 实现
   - 提供 JSON-RPC 消息类型
   - 提供协议常量（如 `ProtocolVersion::V_2025_03_26`）

2. **tokio**: 异步运行时
   - `tokio::process`: 异步进程管理
   - `tokio::io`: 异步 I/O

3. **serde_json**: JSON 序列化/反序列化

4. **codex_mcp_server**: 被测试的 crate
   - 导入 `CodexToolCallParam` 类型

5. **codex_utils_cargo_bin**: 二进制文件定位
   - `cargo_bin()`: 在测试环境中定位编译后的二进制文件

6. **anyhow**: 错误处理

7. **pretty_assertions**: 测试断言（主要用于测试代码）

### 与 MCP 服务器的交互

```
测试代码
    │
    ▼
McpProcess::send_codex_tool_call()
    │
    ▼
JSON-RPC Request ──stdin──► codex-mcp-server 子进程
                               │
                               ▼
                           处理请求
                               │
                               ▼
JSON-RPC Response ◄──stdout──┘
    │
    ▼
McpProcess::read_stream_until_response_message()
```

## 风险、边界与改进建议

### 风险

1. **进程泄漏风险**:
   - `kill_on_drop` 是 "best effort"，不保证进程立即终止
   - `Drop` 实现中的同步等待可能阻塞异步运行时

2. **竞态条件**:
   - `next_request_id` 使用 `Ordering::Relaxed`，在极端并发场景可能有问题
   - 多线程测试中 ID 分配可能冲突

3. **协议版本硬编码**:
   - `ProtocolVersion::V_2025_03_26` 是硬编码的，协议升级时需要修改

4. **错误处理**:
   - 某些错误使用 `anyhow::bail!` 直接 panic，可能导致测试信息不足

### 边界情况

1. **超时处理**:
   - 当前没有内置超时机制，依赖测试框架的超时
   - 长时间运行的 MCP 操作可能导致测试挂起

2. **消息顺序**:
   - `read_stream_until_*` 方法会跳过不相关的消息
   - 如果消息顺序与预期不符，可能导致无限循环

3. **平台差异**:
   - Windows 上的进程管理可能有不同行为
   - Shell 命令解析在 Windows 和 Unix 上表现不同

4. **并发限制**:
   - 每个 `McpProcess` 实例对应一个子进程
   - 大量并发测试会创建大量进程

### 改进建议

1. **添加超时机制**:
   ```rust
   pub async fn read_stream_until_response_message_with_timeout(
       &mut self,
       request_id: RequestId,
       timeout: Duration,
   ) -> anyhow::Result<JsonRpcResponse<serde_json::Value>> {
       tokio::time::timeout(timeout, self.read_stream_until_response_message(request_id))
           .await
           .map_err(|_| anyhow::anyhow!("timeout waiting for response"))?
   }
   ```

2. **改进 ID 生成**:
   ```rust
   // 使用更严格的内存顺序
   let request_id = self.next_request_id.fetch_add(1, Ordering::SeqCst);
   ```

3. **进程清理增强**:
   ```rust
   impl Drop for McpProcess {
       fn drop(&mut self) {
           // 先尝试优雅终止
           let _ = self.process.start_kill();
           
           // 使用更短的轮询间隔
           let deadline = std::time::Instant::now() + Duration::from_secs(5);
           while std::time::Instant::now() < deadline {
               match self.process.try_wait() {
                   Ok(Some(status)) => {
                       eprintln!("MCP process exited with status: {status}");
                       return;
                   }
                   Ok(None) => std::thread::sleep(Duration::from_millis(5)),
                   Err(e) => {
                       eprintln!("Error waiting for MCP process: {e}");
                       return;
                   }
               }
           }
           
           eprintln!("Warning: MCP process did not exit within timeout");
       }
   }
   ```

4. **协议版本配置化**:
   ```rust
   pub struct McpProcessConfig {
       pub protocol_version: ProtocolVersion,
       pub init_timeout: Duration,
       pub response_timeout: Duration,
   }
   ```

5. **更好的错误上下文**:
   ```rust
   pub async fn initialize(&mut self) -> anyhow::Result<()> {
       let request_id = self.next_request_id.fetch_add(1, Ordering::SeqCst);
       
       let params = InitializeRequestParams { ... };
       let params_value = serde_json::to_value(&params)
           .with_context(|| "failed to serialize initialize params")?;
       
       self.send_jsonrpc_message(...)
           .await
           .with_context(|| "failed to send initialize request")?;
       
       let response = self.read_jsonrpc_message()
           .await
           .with_context(|| "failed to read initialize response")?;
       
       // ...
   }
   ```

6. **日志增强**:
   - 添加结构化日志，便于调试复杂的测试失败
   - 记录每个发送/接收消息的详细时间戳
