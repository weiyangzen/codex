# connection_handling_websocket_unix.rs 研究文档

## 场景与职责

`connection_handling_websocket_unix.rs` 是 Codex App Server WebSocket 传输层的 Unix 特定信号处理测试套件，负责验证服务器在收到终止信号（SIGINT/Ctrl+C、SIGTERM）时的优雅关闭行为。该测试文件确保 App Server 能够在有正在运行的 Turn 时等待其完成后再退出，同时支持强制退出机制。

**平台限制**: 该测试文件使用 `#[cfg(unix)]` 条件编译，仅在 Unix 平台（Linux/macOS）上编译和运行。

## 功能点目的

### 1. Ctrl+C 优雅关闭测试
- **目的**: 验证收到 SIGINT 信号时，服务器等待正在运行的 Turn 完成后再退出
- **关键测试**:
  - `websocket_transport_ctrl_c_waits_for_running_turn_before_exit`:
    - 发送 SIGINT 信号
    - 验证进程在 300ms 内未退出（等待 Turn 完成）
    - 验证进程在 10 秒内优雅退出
    - 验证 WebSocket 连接正常断开

### 2. 双重 Ctrl+C 强制退出测试
- **目的**: 验证发送两次 SIGINT 信号时，服务器立即强制退出
- **关键测试**:
  - `websocket_transport_second_ctrl_c_forces_exit_while_turn_running`:
    - 发送第一个 SIGINT 信号
    - 验证进程未立即退出
    - 发送第二个 SIGINT 信号
    - 验证进程在 2 秒内强制退出

### 3. SIGTERM 优雅关闭测试
- **目的**: 验证收到 SIGTERM 信号时的优雅关闭行为
- **关键测试**:
  - `websocket_transport_sigterm_waits_for_running_turn_before_exit`:
    - 与 Ctrl+C 测试类似，但使用 SIGTERM 信号

### 4. 双重 SIGTERM 强制退出测试
- **目的**: 验证发送两次 SIGTERM 信号时的强制退出行为
- **关键测试**:
  - `websocket_transport_second_sigterm_forces_exit_while_turn_running`:
    - 与双重 Ctrl+C 测试类似，但使用 SIGTERM 信号

## 具体技术实现

### 关键流程

```
优雅关闭测试流程:
1. 创建 Mock Responses 服务器，配置延迟响应（3秒）
2. 创建临时 CODEX_HOME 目录并写入 config.toml
3. 启动 WebSocket App Server
4. 建立 WebSocket 连接
5. 发送 initialize 请求并验证响应
6. 发送 thread/start 请求创建线程
7. 发送 turn/start 请求启动 Turn（触发模型请求）
8. 等待模型请求发送到 Mock 服务器（确认 Turn 正在运行）
9. 发送 SIGINT/SIGTERM 信号
10. 验证进程在 300ms 内未退出（正在优雅等待）
11. 验证进程在超时内优雅退出
12. 验证 WebSocket 连接断开

强制退出测试流程:
1-8 步与优雅关闭测试相同
9. 发送第一个 SIGINT/SIGTERM 信号
10. 验证进程未立即退出
11. 发送第二个 SIGINT/SIGTERM 信号
12. 验证进程快速退出（2秒内）
```

### 数据结构

**测试夹具**:
```rust
struct GracefulCtrlCFixture {
    _codex_home: TempDir,           // 临时目录（自动清理）
    _server: wiremock::MockServer,  // Mock 服务器
    process: Child,                 // App Server 进程
    ws: WsClient,                   // WebSocket 连接
}
```

**信号发送函数**:
```rust
fn send_sigint(process: &Child) -> Result<()>
fn send_sigterm(process: &Child) -> Result<()>
fn send_signal(process: &Child, signal: &str) -> Result<()>
```

### 关键辅助函数

**夹具创建**:
```rust
async fn start_ctrl_c_restart_fixture(turn_delay: Duration) -> Result<GracefulCtrlCFixture>
```
- 启动 Mock 服务器，配置延迟 SSE 响应
- 创建临时配置目录
- 启动 WebSocket 服务器
- 初始化连接并启动 Turn
- 等待模型请求确认 Turn 正在运行

**信号发送**:
```rust
fn send_signal(process: &Child, signal: &str) -> Result<()>
```
- 使用 `kill` 命令发送信号
- 支持 `-INT` (SIGINT) 和 `-TERM` (SIGTERM)

**进程状态验证**:
```rust
async fn assert_process_does_not_exit_within(process: &mut Child, window: Duration) -> Result<()>
async fn wait_for_process_exit_within(process: &mut Child, window: Duration, timeout_context: &'static str) -> Result<ExitStatus>
```

**WebSocket 断开检测**:
```rust
async fn expect_websocket_disconnect(stream: &mut WsClient) -> Result<()>
```
- 等待 Close 帧或连接关闭
- 处理 Ping/Pong 保持连接

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/connection_handling_websocket_unix.rs`: 本测试文件
- `codex-rs/app-server/tests/suite/v2/connection_handling_websocket.rs`: 共享的 WebSocket 测试工具
- `codex-rs/app-server/tests/suite/v2/mod.rs`: 测试模块注册（带 `#[cfg(unix)]`）

### 共享工具（从 connection_handling_websocket 导入）
```rust
use super::connection_handling_websocket::{
    DEFAULT_READ_TIMEOUT, WsClient, connect_websocket, create_config_toml,
    read_response_for_id, send_initialize_request, send_request, spawn_websocket_server,
};
```

### App Server 信号处理实现
- `codex-rs/app-server/src/main.rs`: 信号处理注册
- `codex-rs/app-server/src/server.rs`: 优雅关闭逻辑（推断）

### 依赖库
- `tokio::process::Command`: 异步进程管理
- `std::process::Command`: 信号发送（kill 命令）
- `wiremock`: Mock HTTP 服务器

## 依赖与外部交互

### 外部依赖
- `tokio::process`: 异步进程管理
- `tempfile::TempDir`: 临时目录
- `wiremock`: Mock 服务器
- `std::process::Command`: 执行 kill 命令

### 内部依赖
- `connection_handling_websocket`: 共享的 WebSocket 测试工具
- `app_test_support`: 测试支持库
  - `create_final_assistant_message_sse_response()`: SSE 响应创建
  - `to_response()`: 响应解析
- `core_test_support::responses`: Mock 服务器工具

### 系统调用
- `kill -INT <pid>`: 发送 SIGINT 信号
- `kill -TERM <pid>`: 发送 SIGTERM 信号

### 平台限制
```rust
#[cfg(unix)]
mod connection_handling_websocket_unix;
```

## 风险、边界与改进建议

### 风险点
1. **时序敏感**: 测试依赖精确的时序（300ms 内不退出、10秒内退出），在慢速环境可能失败
2. **信号处理竞争**: 信号发送和进程状态检查之间存在竞态条件
3. **平台差异**: 不同 Unix 变体的信号处理可能有差异
4. **kill 命令依赖**: 依赖系统 `kill` 命令可用

### 边界情况
1. **Turn 立即完成**: 如果 Turn 在信号发送前完成，测试可能误判
2. **进程已退出**: 如果进程在信号发送前崩溃，测试会失败
3. **信号丢失**: 极少数情况下信号可能丢失
4. **僵尸进程**: 需要确保进程被正确回收

### 改进建议
1. **重试机制**: 添加重试逻辑处理时序敏感测试
2. **更精确的同步**: 使用显式同步机制而非固定延时
3. **其他信号**: 添加 SIGHUP、SIGUSR1/2 等信号测试
4. **子进程处理**: 验证子进程（如沙盒）是否也正确接收信号
5. **资源清理**: 验证临时文件、套接字等资源是否正确清理
6. **日志验证**: 验证优雅关闭期间的日志输出

### 测试覆盖
- Ctrl+C 优雅关闭: 1 个测试用例
- 双重 Ctrl+C 强制退出: 1 个测试用例
- SIGTERM 优雅关闭: 1 个测试用例
- 双重 SIGTERM 强制退出: 1 个测试用例
- 总计: 4 个测试用例，覆盖主要信号处理场景

### 架构意义
这些测试验证了 App Server 的生产级特性：
1. **优雅关闭**: 确保正在进行的 AI 对话不会突然中断
2. **快速退出**: 在需要时能够快速重启或关闭
3. **容器友好**: 符合容器化部署的信号处理最佳实践
