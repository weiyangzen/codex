# thread_unsubscribe.rs 研究文档

## 场景与职责

`thread_unsubscribe.rs` 是 Codex App Server V2 API 的集成测试文件，专注于测试 **Thread Unsubscribe（线程取消订阅）** 功能。该功能允许客户端主动断开与特定线程的连接，释放服务器端资源，同时保持线程数据持久化。

### 核心测试场景

1. **正常取消订阅**：验证线程卸载和通知发送
2. **运行时取消订阅**：验证在对话回合进行中取消订阅会中断当前回合
3. **状态缓存清除**：验证取消订阅后清除缓存状态，确保恢复时获取最新状态
4. **幂等性验证**：验证对已卸载线程重复取消订阅返回正确状态

---

## 功能点目的

### Thread Unsubscribe 功能

Thread Unsubscribe 是 Codex 资源管理的关键机制：

- **资源释放**：客户端通知服务器不再需要接收某线程的更新，服务器可释放相关内存和连接资源
- **会话管理**：支持多线程场景下的精细化会话控制
- **状态隔离**：取消订阅后，线程状态变化不会推送到客户端，直到重新订阅

### ThreadUnsubscribeStatus 枚举

```rust
pub enum ThreadUnsubscribeStatus {
    NotLoaded,      // 线程未加载
    NotSubscribed,  // 线程未订阅
    Unsubscribed,   // 已成功取消订阅
}
```

### 关键业务规则

1. 取消订阅会触发 `thread/closed` 通知
2. 取消订阅会触发 `thread/status/changed` 通知，状态变为 `NotLoaded`
3. 在对话回合进行中取消订阅会中断当前回合
4. 取消订阅会清除线程的状态缓存
5. 对已卸载的线程再次取消订阅返回 `NotLoaded` 状态

---

## 具体技术实现

### 测试用例 1: 正常取消订阅

```rust
async fn thread_unsubscribe_unloads_thread_and_emits_thread_closed_notification()
```

**流程**:
```
1. 创建线程
2. 发送 thread/unsubscribe 请求
3. 验证响应 status = Unsubscribed
4. 验证收到 thread/closed 通知
5. 验证收到 thread/status/changed 通知 (status = NotLoaded)
6. 验证 thread/loaded/list 返回空列表
```

### 测试用例 2: 运行时取消订阅（中断回合）

```rust
async fn thread_unsubscribe_during_turn_interrupts_turn_and_emits_thread_closed
```

**流程**:
```
1. 创建线程
2. 启动长耗时命令（sleep 10s）
3. 等待命令执行 item/started 通知
4. 发送 thread/unsubscribe 请求
5. 验证响应 status = Unsubscribed
6. 验证收到 thread/closed 通知
7. 验证模型请求数量稳定（未继续发送请求）
```

**关键实现细节**:
- 使用 `wait_for_responses_request_count_to_stabilize` 辅助函数验证请求计数稳定
- 通过 `wiremock::MockServer::received_requests()` 统计实际接收到的请求

### 测试用例 3: 状态缓存清除

```rust
async fn thread_unsubscribe_clears_cached_status_before_resume
```

**流程**:
```
1. 创建线程
2. 启动会导致失败的回合（模拟 server_error）
3. 验证线程状态为 SystemError
4. 取消订阅线程
5. 重新恢复（resume）线程
6. 验证线程状态为 Idle（而非缓存的 SystemError）
```

**关键验证点**:
- 取消订阅前：`thread.status == ThreadStatus::SystemError`
- 取消订阅后恢复：`resume.thread.status == ThreadStatus::Idle`

### 测试用例 4: 幂等性验证

```rust
async fn thread_unsubscribe_reports_not_loaded_after_thread_is_unloaded
```

**流程**:
```
1. 创建线程
2. 第一次取消订阅 → 验证 status = Unsubscribed
3. 等待 thread/closed 通知
4. 第二次取消订阅 → 验证 status = NotLoaded
```

### 辅助函数

#### wait_for_responses_request_count_to_stabilize

```rust
async fn wait_for_responses_request_count_to_stabilize(
    server: &wiremock::MockServer,
    expected_count: usize,
    settle_duration: Duration,
) -> Result<()>
```

**功能**: 轮询 Mock Server 的请求计数，直到达到预期值并保持稳定一段时间。

**实现逻辑**:
1. 每 10ms 检查一次请求计数
2. 如果计数超过预期，返回错误
3. 如果计数等于预期，开始计时稳定期
4. 稳定期达到后返回成功

#### wait_for_thread_status_not_loaded

```rust
async fn wait_for_thread_status_not_loaded(
    mcp: &mut McpProcess,
    thread_id: &str,
) -> Result<ThreadStatusChangedNotification>
```

**功能**: 等待并验证特定线程的 `thread/status/changed` 通知，状态为 `NotLoaded`。

---

## 关键代码路径与文件引用

### 测试文件
- **位置**: `codex-rs/app-server/tests/suite/v2/thread_unsubscribe.rs`
- **行数**: 439 行

### 协议定义
- **位置**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **相关结构**:
  - `ThreadUnsubscribeParams` (行 2722-2724)
  - `ThreadUnsubscribeResponse` (行 2726-2731)
  - `ThreadUnsubscribeStatus` (行 2733-2740)

### 服务器通知类型
- **位置**: `codex-rs/app-server-protocol/src/protocol/common.rs`
- **相关类型**:
  - `ServerNotification::ThreadClosed`
  - `ThreadStatusChangedNotification`

### 测试支持库
- **位置**: `codex-rs/app-server/tests/common/mcp_process.rs`
- **方法**: `send_thread_unsubscribe_request` (行 363-370)

### 状态管理
- **位置**: `codex-rs/core/src/agent/` (Agent 状态机实现)
- **相关**: 线程状态转换逻辑

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `tokio::time::timeout` | 测试超时控制 |
| `wiremock::MockServer` | Mock OpenAI Responses API |
| `pretty_assertions` | 增强断言输出 |

### 内部模块依赖

```
thread_unsubscribe.rs
├── app_test_support::McpProcess
├── app_test_support::create_mock_responses_server_repeating_assistant
├── app_test_support::create_mock_responses_server_sequence_unchecked
├── codex_app_server_protocol::ThreadUnsubscribeParams
├── codex_app_server_protocol::ThreadUnsubscribeResponse
├── codex_app_server_protocol::ThreadUnsubscribeStatus
├── codex_app_server_protocol::ServerNotification
├── codex_app_server_protocol::ThreadStatusChangedNotification
├── core_test_support::responses (用于失败场景测试)
└── pretty_assertions::assert_eq
```

### 平台适配

测试代码包含平台特定的 shell 命令：

```rust
#[cfg(target_os = "windows")]
let shell_command = vec![
    "powershell".to_string(),
    "-Command".to_string(),
    "Start-Sleep -Seconds 10".to_string(),
];
#[cfg(not(target_os = "windows"))]
let shell_command = vec!["sleep".to_string(), "10".to_string()];
```

---

## 风险、边界与改进建议

### 潜在风险

1. **竞态条件**
   - `wait_for_responses_request_count_to_stabilize` 依赖轮询，可能在高负载下不稳定
   - 测试使用 200ms 的稳定期，可能在慢速 CI 环境不足
   - **缓解**: 增加超时时间和稳定期，或改用事件驱动验证

2. **平台差异**
   - Windows 和 Unix 使用不同的 sleep 命令
   - PowerShell 和 shell 的行为差异可能导致测试不稳定
   - **缓解**: 使用抽象的执行层，或增加平台特定的等待逻辑

3. **Mock Server 时序**
   - 测试依赖 Mock Server 按顺序返回响应
   - 如果服务器内部有延迟，可能影响测试结果

### 边界情况

1. **并发取消订阅**: 测试未覆盖多个客户端同时取消订阅同一线程的场景
2. **网络中断**: 测试未模拟网络中断后取消订阅的行为
3. **大负载线程**: 测试未覆盖包含大量历史消息的线程取消订阅性能

### 改进建议

1. **增加压力测试**
   ```rust
   // 建议添加：并发取消订阅测试
   async fn concurrent_unsubscribe_stress_test() -> Result<()>
   
   // 建议添加：大量线程取消订阅测试
   async fn mass_unsubscribe_performance_test() -> Result<()>
   ```

2. **增强竞态条件处理**
   - 使用 `tokio::sync::Notify` 替代轮询
   - 增加更长的超时时间用于 CI 环境

3. **增加错误场景**
   ```rust
   // 建议添加：无效线程 ID 测试
   async fn unsubscribe_invalid_thread_id_returns_error() -> Result<()>
   
   // 建议添加：未初始化连接测试
   async fn unsubscribe_without_initialize_returns_error() -> Result<()>
   ```

4. **优化平台适配**
   - 提取平台特定的命令到测试配置
   - 使用统一的抽象接口

### 相关测试文件

- `thread_resume.rs`: 测试线程恢复功能（与取消订阅互补）
- `turn_interrupt.rs`: 测试回合中断功能
- `thread_status.rs`: 测试线程状态管理

### 性能考虑

`wait_for_responses_request_count_to_stabilize` 使用 10ms 轮询间隔：
- 优点：快速响应状态变化
- 缺点：CPU 使用率略高
- **建议**: 考虑使用指数退避策略
