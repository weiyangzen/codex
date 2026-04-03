# connection_handling_websocket.rs 研究文档

## 场景与职责

`connection_handling_websocket.rs` 是 Codex App Server WebSocket 传输层的连接处理测试套件，负责验证 WebSocket 连接的生命周期管理、请求路由、健康检查端点和安全策略。该测试文件确保 App Server 在 WebSocket 模式下能够正确处理多连接并发、请求隔离和安全限制。

## 功能点目的

### 1. 多连接请求路由测试
- **目的**: 验证每个 WebSocket 连接独立处理请求，响应不会泄漏到其他连接
- **关键测试**:
  - `websocket_transport_routes_per_connection_handshake_and_responses`: 
    - 验证 initialize 响应仅发送到发起连接的客户端
    - 验证未初始化的连接返回 "Not initialized" 错误
    - 验证相同 request-id 在不同连接上独立路由

### 2. 健康检查端点测试
- **目的**: 验证 WebSocket 服务器同时提供 HTTP 健康检查端点
- **关键测试**:
  - `websocket_transport_serves_health_endpoints_on_same_listener`:
    - 验证 `/readyz` 返回 HTTP 200
    - 验证 `/healthz` 返回 HTTP 200
    - 验证健康检查后可正常建立 WebSocket 连接

### 3. Origin 头安全策略测试
- **目的**: 验证服务器拒绝带有 Origin 头的请求（防止 CSRF/Web 攻击）
- **关键测试**:
  - `websocket_transport_rejects_requests_with_origin_header`:
    - 验证 HTTP 请求带 Origin 头返回 403 Forbidden
    - 验证 WebSocket 握手带 Origin 头被拒绝

## 具体技术实现

### 关键流程

```
WebSocket 服务器启动流程:
1. 创建 Mock Responses 服务器
2. 创建临时 CODEX_HOME 目录并写入 config.toml
3. 启动 App Server 进程: codex-app-server --listen ws://127.0.0.1:0
4. 从 stderr 解析绑定的 WebSocket 地址 (ws://127.0.0.1:<port>)
5. 返回进程句柄和绑定地址

多连接测试流程:
1. 建立两个 WebSocket 连接 (ws1, ws2)
2. ws1 发送 initialize 请求 (id=1)
3. 验证 ws1 收到响应，ws2 未收到任何消息
4. ws2 发送 config/read 请求 (id=2)（未初始化）
5. 验证 ws2 收到 "Not initialized" 错误
6. ws2 发送 initialize 请求 (id=3)
7. 两个连接使用相同 request-id (77) 发送 config/read
8. 验证各自收到独立响应

健康检查流程:
1. 启动 WebSocket 服务器
2. HTTP GET /readyz -> 200 OK
3. HTTP GET /healthz -> 200 OK
4. WebSocket 连接并初始化成功

Origin 拒绝流程:
1. 启动 WebSocket 服务器
2. HTTP GET /healthz 带 Origin 头 -> 403 Forbidden
3. WebSocket 握手带 Origin 头 -> HTTP 403 拒绝
```

### 数据结构

**WebSocket 消息类型**:
```rust
pub(super) type WsClient = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;
```

**JSON-RPC 消息封装**:
```rust
pub enum JSONRPCMessage {
    Request(JSONRPCRequest),
    Response(JSONRPCResponse),
    Error(JSONRPCError),
    Notification(JSONRPCNotification),
}
```

**Initialize 参数**:
```rust
pub struct InitializeParams {
    pub client_info: ClientInfo,
    pub capabilities: Option<InitializeCapabilities>,
}

pub struct ClientInfo {
    pub name: String,
    pub title: Option<String>,
    pub version: String,
}
```

### 关键辅助函数

**服务器启动**:
```rust
pub(super) async fn spawn_websocket_server(codex_home: &Path) -> Result<(Child, SocketAddr)>
```
- 启动 App Server 进程
- 监听 stderr 输出解析绑定地址
- 处理 ANSI 转义序列

**连接建立**:
```rust
pub(super) async fn connect_websocket(bind_addr: SocketAddr) -> Result<WsClient>
```
- 带重试和超时机制的 WebSocket 连接

**消息处理**:
```rust
pub(super) async fn read_jsonrpc_message(stream: &mut WsClient) -> Result<JSONRPCMessage>
```
- 处理 Text、Ping/Pong、Close 等帧类型
- 自动回复 Ping 帧

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/connection_handling_websocket.rs`: 本测试文件
- `codex-rs/app-server/tests/suite/v2/connection_handling_websocket_unix.rs`: Unix 特定测试（信号处理）
- `codex-rs/app-server/tests/suite/v2/mod.rs`: 测试模块注册

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v1.rs`: Initialize 相关类型
- `codex-rs/app-server-protocol/src/protocol/common.rs`: ClientRequest/ServerRequest 定义

### App Server 实现
- `codex-rs/app-server/src/main.rs`: 服务器入口
- `codex-rs/app-server/src/transport/websocket.rs`: WebSocket 传输实现（推断）

### 依赖库
- `tokio_tungstenite`: WebSocket 客户端/服务器
- `futures::SinkExt/StreamExt`: 异步流处理
- `reqwest`: HTTP 客户端（健康检查）

## 依赖与外部交互

### 外部依赖
- `tokio::process`: 异步进程管理
- `tokio_tungstenite`: WebSocket 实现
- `reqwest`: HTTP 客户端
- `tempfile::TempDir`: 临时目录

### 内部依赖
- `app_test_support`: 测试支持库
  - `create_mock_responses_server_sequence_unchecked()`: Mock 服务器创建
- `codex_utils_cargo_bin::cargo_bin()`: 二进制文件路径解析

### 网络交互
- Mock Responses 服务器（用于配置）
- WebSocket 服务器（被测对象）
- HTTP 健康检查端点

### 环境变量
- `CODEX_HOME`: 配置根目录
- `RUST_LOG`: 日志级别（测试中设为 debug）

## 风险、边界与改进建议

### 风险点
1. **端口竞争**: 使用 `ws://127.0.0.1:0` 让系统分配端口，但解析 stderr 输出可能存在竞态
2. **ANSI 转义处理**: 手动解析 ANSI 转义序列可能不完整
3. **平台差异**: WebSocket 实现可能在不同平台有细微差异

### 边界情况
1. **连接数限制**: 未测试最大并发连接数
2. **消息大小**: 未测试大消息处理
3. **网络中断**: 未测试连接中断后的恢复
4. **超时处理**: 默认 5 秒读取超时

### 改进建议
1. **压力测试**: 添加高并发连接测试
2. **长连接测试**: 验证长时间空闲连接的保持
3. **断线重连**: 测试客户端断线后的行为
4. **消息顺序**: 验证大量消息的顺序保证
5. **内存泄漏**: 长时间运行测试验证资源释放
6. **TLS 支持**: 添加 wss:// 测试（如支持）

### 测试覆盖
- 多连接隔离: 1 个测试用例
- 健康检查: 1 个测试用例
- 安全策略: 1 个测试用例
- 总计: 3 个测试用例，覆盖核心 WebSocket 功能

### 相关 Unix 特定测试
`connection_handling_websocket_unix.rs` 包含:
- Ctrl+C 优雅关闭测试
- SIGTERM 优雅关闭测试
- 双重信号强制退出测试
