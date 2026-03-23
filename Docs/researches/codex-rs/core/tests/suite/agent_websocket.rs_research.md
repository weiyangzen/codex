# agent_websocket.rs 研究文档

## 场景与职责

`agent_websocket.rs` 是 Codex Core 的集成测试文件，专注于测试 **WebSocket 传输协议** 功能。该功能使用 WebSocket 替代传统的 SSE（Server-Sent Events）作为与 OpenAI Responses API 的通信方式，提供更低的延迟和双向通信能力。

核心测试场景包括：
1. WebSocket 基础 Shell 命令链式调用
2. 首次对话的预热（startup prewarm）机制
3. WebSocket 握手延迟处理
4. WebSocket V2 协议支持（`responses_websockets=2026-02-06`）
5. Service Tier 动态切换（Fast/Standard）

## 功能点目的

### 1. WebSocket 传输协议
- 替代 HTTP SSE，提供更持久的连接
- 支持双向实时通信
- 减少连接建立开销

### 2. 启动预热机制 (Startup Prewarm)
- 首次对话前发送 `response.create` 请求（`generate: false`）
- 预热模型连接，减少首次对话延迟
- 在 WebSocket 握手延迟场景下保证用户体验

### 3. WebSocket V2 协议
- 支持 `previous_response_id` 链式对话
- 支持 `service_tier` 动态切换
- Beta 版本标识：`responses_websockets=2026-02-06`

### 4. Service Tier 控制
- **Fast (priority)**: 高优先级处理，更快的响应
- **Standard (auto)**: 标准处理，成本更低
- 支持每轮对话动态切换

## 具体技术实现

### 关键流程

**WebSocket 连接建立**:
```
客户端发起 WebSocket 握手
    ↓
服务端返回 101 Switching Protocols
    ↓
发送 startup prewarm 请求 (response.create, generate: false)
    ↓
等待 prewarm 完成
    ↓
发送实际对话请求 (response.create)
    ↓
接收 streaming 响应
```

**V2 协议对话链**:
```
Warmup: response.create (no previous_response_id)
    ↓
Turn 1: response.create (previous_response_id: warm-1)
    ↓
Turn 2: response.create (previous_response_id: resp-1)
```

### 核心数据结构

**WebSocketConnectionConfig**:
```rust
pub struct WebSocketConnectionConfig {
    pub requests: Vec<Vec<Value>>,  // 每个请求对应的响应事件序列
    pub response_headers: Vec<(String, String)>,
    pub accept_delay: Option<Duration>,  // 模拟握手延迟
    pub close_after_requests: bool,      // 是否发送 close 帧
}
```

**WebSocketTestServer**:
```rust
pub struct WebSocketTestServer {
    uri: String,
    connections: Arc<Mutex<Vec<Vec<WebSocketRequest>>>>,
    handshakes: Arc<Mutex<Vec<WebSocketHandshake>>>,
    request_log_updated: Arc<Notify>,
    shutdown: oneshot::Sender<()>,
    task: tokio::task::JoinHandle<()>,
}
```

**Beta Header 常量**:
```rust
const WS_V2_BETA_HEADER_VALUE: &str = "responses_websockets=2026-02-06";
```

### Service Tier 映射

| 内部枚举 | API 值 | 说明 |
|---------|--------|------|
| `ServiceTier::Fast` | `"priority"` | 高优先级 |
| `ServiceTier::Standard` | `"auto"` | 标准（默认值） |
| `None` | 不发送 | 使用服务端默认 |

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/agent_websocket.rs` - 本测试文件

### 被测试的核心代码
- `codex-rs/core/src/client/websocket.rs` - WebSocket 客户端实现
- `codex-rs/core/src/client/responses_client.rs` - Responses API 客户端
- `codex-rs/core/src/codex.rs` - Codex 核心，处理 transport 选择

### 协议定义
- `codex-rs/protocol/src/config_types.rs` - `ServiceTier` 枚举
- `codex-rs/protocol/src/protocol.rs` - 事件和 Op 定义

### 测试支持代码
- `codex-rs/core/tests/common/responses.rs`:
  - `start_websocket_server()` - 启动 WebSocket 测试服务器
  - `start_websocket_server_with_headers()` - 支持自定义配置
  - `WebSocketTestServer` - 测试服务器结构

## 依赖与外部交互

### 测试依赖
| 依赖 | 用途 |
|------|------|
| `tokio` | 异步运行时 |
| `tokio-tungstenite` | WebSocket 实现 |
| `serde_json` | JSON 序列化 |

### WebSocket 测试服务器

**事件构造辅助函数**:
- `ev_response_created(id)` - 响应创建事件
- `ev_completed(id)` - 响应完成事件
- `ev_assistant_message(id, text)` - 助手消息事件
- `ev_shell_command_call(id, command)` - Shell 命令调用事件

**请求验证**:
```rust
let connection = server.single_connection();
let first_turn = connection.first().expect("missing first turn request").body_json();
assert_eq!(first_turn["type"].as_str(), Some("response.create"));
```

### 网络跳过宏
```rust
skip_if_no_network!(Ok(()));
```
在沙箱环境中跳过需要网络的测试。

## 风险、边界与改进建议

### 当前风险点

1. **时间敏感的测试**
   - `websocket_first_turn_handles_handshake_delay_with_startup_prewarm` 使用 150ms 延迟
   - 在慢速 CI 环境中可能需要调整

2. **V2 协议硬编码**
   - Beta header 值硬编码为 `"responses_websockets=2026-02-06"`
   - 协议版本更新后需要同步修改

3. **Mock 服务器的简化**
   - 测试服务器不验证请求内容的完整性
   - 不模拟真实的 OpenAI 响应行为

### 边界情况

1. **WebSocket 断线重连**
   - 测试未覆盖连接中断后的自动重连

2. **并发连接**
   - 未测试多个并发 WebSocket 连接的场景

3. **大消息分片**
   - 未测试超大消息的分片传输

4. **错误处理**
   - 未测试 WebSocket 错误（如 1006 abnormal closure）的处理

### 改进建议

1. **增加重连测试**
   ```rust
   #[tokio::test]
   async fn websocket_reconnects_after_abnormal_closure() { ... }
   ```

2. **增加压力测试**
   - 测试大量并发连接
   - 测试长时间连接的稳定性

3. **协议版本管理**
   - 将 Beta header 值提取为配置项
   - 支持协议版本协商

4. **错误场景覆盖**
   ```rust
   // 建议添加：
   #[tokio::test]
   async fn websocket_handles_401_unauthorized() { ... }
   
   #[tokio::test]
   async fn websocket_handles_rate_limit() { ... }
   ```

5. **性能基准**
   - 对比 WebSocket 与 SSE 的延迟
   - 测量首次对话的 TTFB（Time To First Byte）

6. **兼容性测试**
   - 测试不同网络环境下的行为（高延迟、丢包）
   - 测试代理环境下的连接

7. **监控和可观测性**
   - 验证 WebSocket 连接指标的正确上报
   - 测试连接生命周期的日志记录
