# DIR codex-rs/exec-server/tests/common 研究文档

## 场景与职责

`codex-rs/exec-server/tests/common` 是 `codex-exec-server` crate 的集成测试共享基础设施目录。该目录包含测试辅助模块，用于在集成测试中启动、连接和管理 `codex-exec-server` 进程。

### 核心职责

1. **测试进程生命周期管理**: 提供 `ExecServerHarness` 结构体，封装了 exec-server 二进制文件的启动、WebSocket 连接建立和进程终止
2. **JSON-RPC 通信抽象**: 封装 WebSocket 上的 JSON-RPC 消息发送和接收，支持请求、通知和原始文本发送
3. **测试超时和重试机制**: 内置连接超时、事件等待超时和连接重试逻辑，确保测试的健壮性
4. **跨构建系统兼容**: 通过 `codex_utils_cargo_bin` 支持 Cargo 和 Bazel 两种构建系统的测试环境

### 在测试架构中的位置

```
codex-rs/exec-server/tests/
├── common/
│   ├── mod.rs              # 模块入口，导出 exec_server 子模块
│   └── exec_server.rs      # 核心测试基础设施
├── initialize.rs           # 初始化流程测试
├── process.rs              # 进程管理测试
└── websocket.rs            # WebSocket 通信测试
```

该目录是集成测试层的基础设施，被所有 `tests/*.rs` 文件依赖使用。

---

## 功能点目的

### 1. ExecServerHarness 结构体

**目的**: 为集成测试提供高层次的 exec-server 进程控制抽象。

**核心功能**:
- 自动进程清理（通过 `Drop` trait 在测试失败时自动 kill 子进程）
- 请求 ID 自动生成和追踪
- WebSocket 连接状态管理

### 2. 连接建立机制

**目的**: 解决测试中的"竞态条件"问题——确保在连接 WebSocket 之前服务器已启动监听。

**实现策略**:
- `reserve_websocket_url()`: 预先绑定到 `127.0.0.1:0` 获取随机可用端口，然后立即释放
- `connect_websocket_when_ready()`: 带重试的 WebSocket 连接，处理 `ConnectionRefused` 错误

### 3. JSON-RPC 消息封装

**目的**: 简化测试代码中的协议交互，隐藏序列化/反序列化细节。

**提供的方法**:
- `send_request()`: 发送 JSON-RPC 请求，自动分配递增的 ID
- `send_notification()`: 发送 JSON-RPC 通知（无响应）
- `send_raw_text()`: 发送原始文本（用于测试错误处理）
- `next_event()`: 接收下一个事件（带默认超时）
- `wait_for_event()`: 条件等待特定事件

---

## 具体技术实现

### 关键数据结构

```rust
// ExecServerHarness 结构体定义
pub(crate) struct ExecServerHarness {
    child: Child,                                    // tokio 子进程句柄
    websocket: WebSocketStream<MaybeTlsStream<TcpStream>>,  // WebSocket 连接
    next_request_id: i64,                            // 自增请求 ID 计数器
}
```

### 超时常量配置

```rust
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);        // 连接超时
const CONNECT_RETRY_INTERVAL: Duration = Duration::from_millis(25); // 重试间隔
const EVENT_TIMEOUT: Duration = Duration::from_secs(5);          // 事件等待超时
```

### 核心流程: 服务器启动

```rust
pub(crate) async fn exec_server() -> anyhow::Result<ExecServerHarness> {
    // 1. 解析二进制路径（支持 Cargo 和 Bazel）
    let binary = cargo_bin("codex-exec-server")?;
    
    // 2. 预留 WebSocket 地址（随机端口）
    let websocket_url = reserve_websocket_url()?;
    
    // 3. 启动子进程
    let mut child = Command::new(binary);
    child.args(["--listen", &websocket_url]);
    let child = child.spawn()?;
    
    // 4. 等待 WebSocket 就绪并连接
    let (websocket, _) = connect_websocket_when_ready(&websocket_url).await?;
    
    Ok(ExecServerHarness { child, websocket, next_request_id: 1 })
}
```

### 核心流程: 带重试的 WebSocket 连接

```rust
async fn connect_websocket_when_ready(websocket_url: &str) -> Result<...> {
    let deadline = Instant::now() + CONNECT_TIMEOUT;
    loop {
        match connect_async(websocket_url).await {
            Ok(websocket) => return Ok(websocket),
            Err(err) if Instant::now() < deadline && is_connection_refused(&err) => {
                sleep(CONNECT_RETRY_INTERVAL).await;  // 服务器未就绪，等待重试
            }
            Err(err) => return Err(err.into()),
        }
    }
}
```

### 核心流程: 消息接收循环

```rust
async fn next_event_with_timeout(&mut self, timeout_duration: Duration) -> Result<JSONRPCMessage> {
    loop {
        let frame = timeout(timeout_duration, self.websocket.next()).await???;
        match frame {
            Message::Text(text) => return Ok(serde_json::from_str(text.as_ref())?),
            Message::Binary(bytes) => return Ok(serde_json::from_slice(bytes.as_ref())?),
            Message::Close(_) => return Err(...),  // 连接关闭
            Message::Ping(_) | Message::Pong(_) => {}  // 心跳忽略
            _ => {}
        }
    }
}
```

### JSON-RPC 协议集成

测试基础设施使用 `codex_app_server_protocol` crate 定义的类型:

- `JSONRPCMessage`: 统一的消息枚举（Request/Notification/Response/Error）
- `JSONRPCRequest` / `JSONRPCResponse`: 请求和响应结构
- `JSONRPCNotification`: 通知结构
- `RequestId`: 请求 ID 类型（支持 String 或 Integer）

---

## 关键代码路径与文件引用

### 当前目录文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `common/mod.rs` | 1 | 模块入口，导出 `exec_server` 子模块 |
| `common/exec_server.rs` | 188 | 核心测试基础设施实现 |

### 调用方（测试文件）

| 文件 | 用途 |
|------|------|
| `tests/initialize.rs` | 测试 `initialize` RPC 方法 |
| `tests/process.rs` | 测试 `process/start` stub 行为 |
| `tests/websocket.rs` | 测试 WebSocket 错误恢复能力 |

### 被调用方（依赖的 crates）

| Crate | 模块 | 用途 |
|-------|------|------|
| `codex-exec-server` | `lib.rs` | 被测库，提供 `InitializeParams`, `InitializeResponse` |
| `codex-app-server-protocol` | `jsonrpc_lite.rs` | JSON-RPC 消息类型定义 |
| `codex-utils-cargo-bin` | `lib.rs` | 跨构建系统二进制定位 |

### 关键依赖链

```
tests/common/exec_server.rs
    ├── codex_utils_cargo_bin::cargo_bin()  [二进制定位]
    ├── codex_app_server_protocol::*        [JSON-RPC 类型]
    ├── tokio::process::Command             [进程管理]
    ├── tokio_tungstenite::connect_async    [WebSocket 客户端]
    └── futures::SinkExt/StreamExt          [异步流操作]
```

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `serde_json` | JSON 序列化/反序列化 |
| `tokio` | 异步运行时和进程管理 |
| `tokio-tungstenite` | WebSocket 客户端 |
| `futures` | 异步流操作（SinkExt/StreamExt） |

### 内部 workspace 依赖

| Crate | 用途 |
|-------|------|
| `codex-app-server-protocol` | JSON-RPC 消息类型（`JSONRPCMessage`, `JSONRPCRequest`, `JSONRPCResponse`, `JSONRPCNotification`, `RequestId`） |
| `codex-exec-server` | 被测 crate 的协议类型（`InitializeParams`, `InitializeResponse`） |
| `codex-utils-cargo-bin` | 测试二进制定位工具 |

### 进程交互

```
测试进程 (cargo test)
    │
    ├── spawns ──► codex-exec-server 子进程
    │                  │
    │                  └── listens on ws://127.0.0.1:RANDOM_PORT
    │
    └── connects via WebSocket
                       │
                       └── JSON-RPC 双向通信
```

### 环境依赖

- **平台限制**: 所有测试标记为 `#![cfg(unix)]`，仅在 Unix 平台运行
- **网络**: 需要本地回环网络（`127.0.0.1`）
- **二进制**: 需要 `codex-exec-server` 二进制已编译

---

## 风险、边界与改进建议

### 当前风险

1. **平台限制**
   - 所有测试仅支持 Unix 平台（`#![cfg(unix)]`）
   - Windows 平台测试覆盖缺失

2. **竞态条件风险**
   - `reserve_websocket_url()` 使用 `bind(0)` 后 `drop(listener)`，在极端情况下端口可能被其他进程抢占
   - 虽然概率极低，但非原子操作

3. **超时硬编码**
   - 超时常量（5秒）在慢速 CI 环境或高负载机器上可能导致 flaky 测试

4. **错误处理简化**
   - `Drop` 实现中忽略 `start_kill()` 的错误结果，可能掩盖资源泄漏问题

### 边界情况

1. **WebSocket 帧类型处理**
   - 当前忽略 `Ping/Pong` 帧
   - 对未知帧类型使用通配符匹配（`_ => {}`）

2. **连接失败场景**
   - 仅处理 `ConnectionRefused` 错误的重试
   - 其他 IO 错误直接失败

3. **消息解析错误**
   - 二进制帧和文本帧分别解析，但共享相同的错误处理逻辑

### 改进建议

1. **可配置超时**
   ```rust
   // 建议：从环境变量读取超时配置
   const CONNECT_TIMEOUT: Duration = Duration::from_secs(
       env::var("EXEC_SERVER_TEST_TIMEOUT_SECS")
           .ok()
           .and_then(|s| s.parse().ok())
           .unwrap_or(5)
   );
   ```

2. **端口分配原子性**
   - 考虑使用文件锁或其他机制确保端口预留的原子性
   - 或改用 Unix Domain Socket（UDS）避免端口竞争

3. **Windows 支持**
   - 评估移除 `#![cfg(unix)]` 限制的可行性
   - 或创建 Windows 特定的测试基础设施

4. **日志增强**
   - 在 `Drop` 失败时记录警告日志
   - 在重试连接时记录调试信息

5. **测试覆盖率扩展**
   - 当前仅测试 `initialize` 和 `process/start` stub
   - 建议随着功能实现增加更多 RPC 方法测试

6. **资源泄漏检测**
   - 添加测试后进程清理验证
   - 使用 `tempfile` crate 管理临时资源

---

## 附录：测试用例概览

### initialize.rs
- **测试**: `exec_server_accepts_initialize`
- **目的**: 验证 exec-server 接受 `initialize` 请求并返回正确响应
- **关键断言**: 响应 ID 匹配、响应结构正确

### process.rs
- **测试**: `exec_server_stubs_process_start_over_websocket`
- **目的**: 验证 `process/start` 返回 "not implemented" 错误（stub 行为）
- **关键断言**: 错误码 -32601（Method Not Found）、特定错误消息

### websocket.rs
- **测试**: `exec_server_reports_malformed_websocket_json_and_keeps_running`
- **目的**: 验证服务器在收到畸形 JSON 后保持运行并返回错误
- **关键断言**: 错误码 -32600（Invalid Request）、后续 `initialize` 仍能成功

---

*文档生成时间: 2026-03-21*
*研究对象版本: codex-rs/exec-server/tests/common*
