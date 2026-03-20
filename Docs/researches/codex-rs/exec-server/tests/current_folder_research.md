# DIR codex-rs/exec-server/tests 研究文档

## 概述

`codex-rs/exec-server/tests` 目录包含 `codex-exec-server` crate 的集成测试套件。这些测试验证执行服务器的核心功能，包括 WebSocket 通信、JSON-RPC 协议处理、初始化流程和进程管理。

---

## 场景与职责

### 测试目录定位

该测试目录位于 `codex-rs/exec-server` crate 中，负责验证执行服务器（exec-server）的端到端行为。执行服务器是一个独立的二进制程序，通过 WebSocket 提供远程进程执行服务。

### 核心职责

1. **WebSocket 通信测试**：验证服务器与客户端之间的 WebSocket 连接建立、消息传输和错误处理
2. **JSON-RPC 协议测试**：验证 JSON-RPC 2.0 风格的消息编码/解码、请求-响应匹配和错误处理
3. **初始化流程测试**：验证 `initialize`/`initialized` 握手协议的正确性
4. **进程管理测试**：验证 `process/start` 等进程控制 API 的行为（当前为 stub 实现）
5. **健壮性测试**：验证服务器对畸形输入的处理能力

### 测试架构特点

- **集成测试模式**：所有测试都是集成测试，通过启动真实的 `codex-exec-server` 二进制进程进行测试
- **跨平台限制**：测试仅在 Unix 系统上运行（`#![cfg(unix)]`）
- **异步测试**：使用 `tokio::test` 进行异步测试，多线程运行

---

## 功能点目的

### 1. 测试基础设施（`common/`）

#### `common/mod.rs`
- **目的**：测试模块入口，暴露 `exec_server` 子模块
- **内容**：简单的模块声明 `pub(crate) mod exec_server;`

#### `common/exec_server.rs`
- **目的**：提供测试用的执行服务器实例管理（test harness）
- **核心功能**：
  - 自动查找并启动 `codex-exec-server` 二进制文件
  - 建立 WebSocket 连接并管理连接生命周期
  - 提供便捷的 JSON-RPC 消息发送和接收接口
  - 自动清理（`Drop` 实现确保进程终止）

### 2. 初始化测试（`initialize.rs`）

- **目的**：验证执行服务器的基本初始化流程
- **测试场景**：
  - 客户端发送 `initialize` 请求
  - 服务器返回正确的 `InitializeResponse`
  - 验证请求 ID 匹配

### 3. 进程管理测试（`process.rs`）

- **目的**：验证进程控制 API 的行为
- **测试场景**：
  - 先完成初始化握手
  - 发送 `process/start` 请求
  - 验证服务器返回 "method not found" 错误（当前为 stub 实现）
  - 错误码 `-32601` 符合 JSON-RPC 规范

### 4. WebSocket 健壮性测试（`websocket.rs`）

- **目的**：验证服务器对异常输入的处理能力
- **测试场景**：
  - 发送非 JSON 格式的原始文本（`not-json`）
  - 验证服务器返回错误响应（错误码 `-32600` Invalid Request）
  - 验证服务器在错误后仍能正常处理后续请求
  - 完成正常的 `initialize` 握手验证恢复能力

---

## 具体技术实现

### 关键数据结构

#### `ExecServerHarness`（测试 harness）

```rust
pub(crate) struct ExecServerHarness {
    child: Child,                                    // 服务器子进程
    websocket: WebSocketStream<...>,                 // WebSocket 连接
    next_request_id: i64,                            // 请求 ID 生成器
}
```

- **职责**：封装测试所需的服务器进程和通信通道
- **生命周期管理**：`Drop` 实现确保测试结束时进程被终止

#### JSON-RPC 消息类型（来自 `codex-app-server-protocol`）

```rust
// 请求消息
pub struct JSONRPCRequest {
    pub id: RequestId,           // 请求标识（String 或 i64）
    pub method: String,          // 方法名
    pub params: Option<Value>,   // 参数
    pub trace: Option<W3cTraceContext>, // 分布式追踪
}

// 响应消息
pub struct JSONRPCResponse {
    pub id: RequestId,
    pub result: Value,
}

// 错误消息
pub struct JSONRPCError {
    pub id: RequestId,
    pub error: JSONRPCErrorError,
}

pub struct JSONRPCErrorError {
    pub code: i64,               // 错误码（如 -32601 Method Not Found）
    pub message: String,
    pub data: Option<Value>,
}
```

#### 初始化协议类型

```rust
// codex-rs/exec-server/src/protocol.rs
pub const INITIALIZE_METHOD: &str = "initialize";
pub const INITIALIZED_METHOD: &str = "initialized";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeParams {
    pub client_name: String,     // 客户端标识
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeResponse {}  // 当前为空响应
```

### 关键流程

#### 1. 测试服务器启动流程

```rust
pub(crate) async fn exec_server() -> anyhow::Result<ExecServerHarness> {
    // 1. 查找二进制文件
    let binary = cargo_bin("codex-exec-server")?;
    
    // 2. 预留 WebSocket 地址（绑定到随机端口）
    let websocket_url = reserve_websocket_url()?;
    
    // 3. 启动服务器进程
    let mut child = Command::new(binary);
    child.args(["--listen", &websocket_url]);
    let child = child.spawn()?;
    
    // 4. 等待 WebSocket 就绪并连接
    let (websocket, _) = connect_websocket_when_ready(&websocket_url).await?;
    
    Ok(ExecServerHarness { child, websocket, next_request_id: 1 })
}
```

**超时配置**：
- `CONNECT_TIMEOUT`: 5 秒（连接超时）
- `CONNECT_RETRY_INTERVAL`: 25 毫秒（重试间隔）
- `EVENT_TIMEOUT`: 5 秒（事件等待超时）

#### 2. WebSocket 连接建立流程

```rust
async fn connect_websocket_when_ready(url: &str) -> Result<...> {
    let deadline = Instant::now() + CONNECT_TIMEOUT;
    loop {
        match connect_async(url).await {
            Ok(websocket) => return Ok(websocket),
            Err(err) if is_connection_refused(&err) && not_timeout() => {
                sleep(CONNECT_RETRY_INTERVAL).await;  // 重试
            }
            Err(err) => return Err(err),
        }
    }
}
```

**设计考虑**：服务器启动需要时间，因此需要轮询等待连接成功。

#### 3. JSON-RPC 请求发送流程

```rust
impl ExecServerHarness {
    pub(crate) async fn send_request(
        &mut self,
        method: &str,
        params: serde_json::Value,
    ) -> anyhow::Result<RequestId> {
        let id = RequestId::Integer(self.next_request_id);
        self.next_request_id += 1;
        
        let message = JSONRPCMessage::Request(JSONRPCRequest {
            id: id.clone(),
            method: method.to_string(),
            params: Some(params),
            trace: None,
        });
        
        self.websocket.send(Message::Text(encoded.into())).await?;
        Ok(id)
    }
}
```

#### 4. 事件接收与匹配流程

```rust
pub(crate) async fn wait_for_event<F>(
    &mut self,
    mut predicate: F,
) -> anyhow::Result<JSONRPCMessage>
where
    F: FnMut(&JSONRPCMessage) -> bool,
{
    let deadline = Instant::now() + EVENT_TIMEOUT;
    loop {
        let event = self.next_event_with_timeout(remaining).await?;
        if predicate(&event) {
            return Ok(event);
        }
        // 不匹配则继续等待
    }
}
```

### 协议常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `INITIALIZE_METHOD` | `"initialize"` | 初始化请求方法名 |
| `INITIALIZED_METHOD` | `"initialized"` | 初始化完成通知方法名 |
| 错误码 `-32600` | Invalid Request | 畸形请求 |
| 错误码 `-32601` | Method Not Found | 方法不存在 |
| 错误码 `-32602` | Invalid Params | 参数错误 |

---

## 关键代码路径与文件引用

### 测试文件

| 文件 | 行数 | 描述 |
|------|------|------|
| `tests/common/mod.rs` | 1 | 测试模块入口 |
| `tests/common/exec_server.rs` | 188 | 测试 harness 实现 |
| `tests/initialize.rs` | 34 | 初始化流程测试 |
| `tests/process.rs` | 65 | 进程管理 API 测试 |
| `tests/websocket.rs` | 60 | WebSocket 健壮性测试 |

### 被测代码（exec-server crate）

| 文件 | 描述 |
|------|------|
| `src/bin/codex-exec-server.rs` | 二进制入口，解析 `--listen` 参数 |
| `src/server.rs` | 服务器模块入口，暴露 `run_main` |
| `src/server/transport.rs` | WebSocket 传输层实现 |
| `src/server/processor.rs` | JSON-RPC 消息处理器 |
| `src/server/handler.rs` | 业务逻辑处理器（initialize/initialized） |
| `src/server/jsonrpc.rs` | JSON-RPC 辅助函数（错误构造等） |
| `src/protocol.rs` | 协议类型定义（InitializeParams/Response） |
| `src/connection.rs` | 连接抽象（WebSocket/stdio） |

### 依赖 crate

| Crate | 用途 |
|-------|------|
| `codex-app-server-protocol` | JSON-RPC 消息类型定义 |
| `codex-utils-cargo-bin` | 测试时定位二进制文件 |
| `tokio-tungstenite` | WebSocket 客户端连接 |
| `futures` | Sink/Stream trait |

---

## 依赖与外部交互

### 编译时依赖

```toml
[dev-dependencies]
anyhow = { workspace = true }
codex-utils-cargo-bin = { workspace = true }
pretty_assertions = { workspace = true }
```

### 运行时依赖

测试运行时需要：
1. **编译好的 `codex-exec-server` 二进制文件**：通过 `codex_utils_cargo_bin::cargo_bin()` 定位
2. **可用的 TCP 端口**：测试使用 `127.0.0.1:0` 让系统自动分配端口
3. **Unix 环境**：所有测试文件都有 `#![cfg(unix)]` 属性限制

### 与 app-server-protocol 的交互

测试大量使用 `codex-app-server-protocol` 中定义的类型：

```rust
use codex_app_server_protocol::JSONRPCMessage;
use codex_app_server_protocol::JSONRPCResponse;
use codex_app_server_protocol::JSONRPCError;
use codex_app_server_protocol::RequestId;
```

这些类型定义了 Codex 项目内部使用的 JSON-RPC 协议变体。

### 测试执行流程

```
测试代码 (tests/*.rs)
    ↓
ExecServerHarness::exec_server()
    ↓
cargo_bin("codex-exec-server")  // 定位二进制
    ↓
spawn("codex-exec-server --listen ws://127.0.0.1:RANDOM")
    ↓
connect_async("ws://127.0.0.1:RANDOM")  // WebSocket 连接
    ↓
发送 JSON-RPC 请求 ←→ 服务器处理 ←→ 接收响应
    ↓
Drop::drop() 终止服务器进程
```

---

## 风险、边界与改进建议

### 当前限制与风险

1. **平台限制**
   - 测试仅在 Unix 上运行（`#![cfg(unix)]`）
   - Windows 平台缺乏测试覆盖

2. **Stub 实现**
   - `process/start` 等核心 API 当前返回 "not implemented" 错误
   - 测试仅验证错误行为，未测试实际功能

3. **并发测试风险**
   - 测试使用随机端口，但高并发时可能出现端口冲突
   - 没有测试多个客户端同时连接的场景

4. **超时硬编码**
   - 超时值（5秒）是硬编码的，在慢速 CI 环境可能不稳定

### 边界情况

1. **畸形消息处理**
   - 已测试：非 JSON 文本输入
   - 未测试：有效的 JSON 但无效的 JSON-RPC 结构
   - 未测试：超大消息、空消息、二进制消息

2. **连接生命周期**
   - 已测试：正常关闭（通过 `Drop`）
   - 未测试：网络中断、服务器崩溃、半开连接

3. **初始化状态机**
   - 已测试：正常初始化流程
   - 未测试：重复初始化、未初始化就调用其他方法

### 改进建议

1. **扩展测试覆盖**
   ```rust
   // 建议添加：
   - test_initialize_twice_rejected()  // 重复初始化应被拒绝
   - test_call_before_initialize()      // 未初始化调用应报错
   - test_concurrent_connections()      // 多客户端并发
   - test_large_message()               // 大消息处理
   - test_binary_websocket_message()    // Binary 帧而非 Text 帧
   ```

2. **参数化超时**
   ```rust
   // 建议：从环境变量读取超时值
   const EVENT_TIMEOUT: Duration = Duration::from_secs(
       env::var("EXEC_SERVER_TEST_TIMEOUT")
           .ok()
           .and_then(|s| s.parse().ok())
           .unwrap_or(5)
   );
   ```

3. **Windows 支持**
   - 移除或条件编译 Unix 特定的代码
   - 在 Windows CI 上运行测试

4. **日志验证**
   - 当前测试不验证服务器日志输出
   - 建议添加 `tracing` 日志的断言验证

5. **性能基准**
   - 添加基础性能测试（连接建立时间、消息往返延迟）

### 代码质量建议

1. **exec_server.rs 第 35-38 行**：`Drop` 实现使用 `start_kill()` 可能导致僵尸进程，建议等待进程退出：n   ```rust
   impl Drop for ExecServerHarness {
       fn drop(&mut self) {
           let _ = self.child.start_kill();
           // 建议添加：let _ = self.child.wait();
       }
   }
   ```

2. **错误消息匹配**：`websocket.rs` 中的错误消息前缀匹配较脆弱，建议改用错误码断言

3. **测试隔离**：考虑使用 `serial_test` crate 确保测试串行执行，避免端口竞争

---

## 总结

`codex-rs/exec-server/tests` 提供了执行服务器的基础集成测试，覆盖了：
- WebSocket 通信建立和消息交换
- JSON-RPC 协议的基本请求-响应流程
- 初始化握手协议
- 对畸形输入的健壮性

测试基础设施设计良好，使用 `ExecServerHarness` 封装了复杂的进程管理和连接逻辑。主要局限在于当前服务器实现为 stub，核心进程管理功能尚未实现对应的测试。
