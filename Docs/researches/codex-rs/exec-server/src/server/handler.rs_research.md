# ExecServerHandler 研究文档

## 场景与职责

`ExecServerHandler` 是 codex-exec-server 的核心状态管理器，负责维护服务器端 JSON-RPC 连接的生命周期状态。它实现了 LSP（Language Server Protocol）风格的初始化握手协议，确保客户端与服务器之间的连接建立遵循严格的顺序要求。

该 handler 位于 `codex-rs/exec-server/src/server/handler.rs`，是 exec-server 模块中最基础的状态机组件。

## 功能点目的

### 1. 初始化状态管理
- **目的**: 确保每个连接只能执行一次 `initialize` 请求，防止重复初始化导致的状态混乱
- **实现**: 使用 `AtomicBool` 类型的 `initialize_requested` 标志位，通过原子操作保证线程安全

### 2. 初始化完成确认
- **目的**: 在客户端发送 `initialized` 通知后，标记连接已完全就绪
- **实现**: 使用 `initialized` 标志位记录状态，并验证 `initialized` 通知必须在 `initialize` 请求之后

### 3. 状态验证
- **目的**: 提供严格的状态转换检查，防止协议违规
- **实现**: 
  - 重复 `initialize` 请求返回错误（code: -32600, invalid_request）
  - `initialized` 通知在 `initialize` 之前到达返回错误

## 具体技术实现

### 数据结构

```rust
pub(crate) struct ExecServerHandler {
    initialize_requested: AtomicBool,  // 是否已收到 initialize 请求
    initialized: AtomicBool,           // 是否已完成 initialized 通知
}
```

使用 `AtomicBool` 而非 `Mutex<bool>` 的原因：
- 状态检查是简单的布尔标志操作，无需复杂锁机制
- `Ordering::SeqCst` 确保多线程环境下的可见性和顺序性

### 关键流程

#### 初始化流程
```
Client                    ExecServerHandler
  |                              |
  |---- initialize ----------->  |---- 检查 initialize_requested
  |                              |     若已为 true，返回错误
  |<--- InitializeResponse ----  |     否则设为 true，返回空响应
  |                              |
  |---- initialized ---------->  |---- 检查 initialize_requested
  |                              |     若为 false，返回错误
  |                              |     否则设 initialized = true
```

#### 状态转换图
```
[初始状态]
    |
    v
[initialize_requested = false, initialized = false]
    |
    | initialize 请求
    v
[initialize_requested = true, initialized = false]
    |
    | initialized 通知
    v
[initialize_requested = true, initialized = true]
```

### 关键代码路径

#### 1. 创建 Handler
```rust
pub(crate) fn new() -> Self {
    Self {
        initialize_requested: AtomicBool::new(false),
        initialized: AtomicBool::new(false),
    }
}
```

#### 2. 处理 initialize 请求
```rust
pub(crate) fn initialize(&self) -> Result<InitializeResponse, JSONRPCErrorError> {
    if self.initialize_requested.swap(true, Ordering::SeqCst) {
        return Err(invalid_request(
            "initialize may only be sent once per connection".to_string(),
        ));
    }
    Ok(InitializeResponse {})
}
```

- 使用 `swap` 原子操作：返回旧值并设置新值为 true
- 若旧值为 true，说明已初始化过，返回错误

#### 3. 处理 initialized 通知
```rust
pub(crate) fn initialized(&self) -> Result<(), String> {
    if !self.initialize_requested.load(Ordering::SeqCst) {
        return Err("received `initialized` notification before `initialize`".into());
    }
    self.initialized.store(true, Ordering::SeqCst);
    Ok(())
}
```

- 必须先检查 `initialize_requested`，确保协议顺序
- 成功后设置 `initialized` 标志

#### 4. 关闭处理
```rust
pub(crate) async fn shutdown(&self) {}
```

- 当前为空实现，预留用于后续资源清理

## 依赖与外部交互

### 内部依赖

| 依赖项 | 路径 | 用途 |
|--------|------|------|
| `JSONRPCErrorError` | `codex_app_server_protocol` | JSON-RPC 错误类型定义 |
| `InitializeResponse` | `crate::protocol` | 初始化响应结构体 |
| `invalid_request` | `crate::server::jsonrpc` | 错误构造辅助函数 |

### 外部调用方

| 调用方 | 路径 | 调用方式 |
|--------|------|----------|
| `dispatch_request` | `processor.rs:84` | 处理 initialize 请求 |
| `handle_notification` | `processor.rs:113` | 处理 initialized 通知 |
| `run_connection` | `processor.rs:18` | 连接结束时调用 shutdown |
| `LocalBackend` | `local_backend.rs` | 进程内直接调用 |

### 协议定义

```rust
// protocol.rs
pub const INITIALIZE_METHOD: &str = "initialize";
pub const INITIALIZED_METHOD: &str = "initialized";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeParams {
    pub client_name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeResponse {}
```

## 风险、边界与改进建议

### 当前风险

1. **空 shutdown 实现**
   - 风险：如果后续添加资源管理，当前空实现可能导致资源泄漏
   - 建议：明确文档说明或添加 TODO 注释

2. **无超时机制**
   - 风险：客户端可能永远不发 `initialized` 通知，导致状态停留在半初始化
   - 建议：考虑添加初始化超时机制

3. **状态不可查询**
   - 风险：外部无法获知当前初始化状态，调试困难
   - 建议：添加 `is_initialized()` 等查询方法

### 边界情况

1. **并发 initialize 请求**
   - 由于使用 `AtomicBool::swap`，并发请求只有一个会成功，其余返回错误
   - 这是符合预期的行为

2. **连接断开后的状态**
   - Handler 随连接生命周期存在，连接断开即丢弃
   - 无需处理重连复用场景

3. **进程内 vs 远程模式**
   - LocalBackend 直接调用 handler 方法
   - WebSocket 模式通过 processor 转发
   - 两种路径行为一致

### 改进建议

1. **添加状态查询接口**
```rust
pub(crate) fn is_initialize_requested(&self) -> bool {
    self.initialize_requested.load(Ordering::SeqCst)
}

pub(crate) fn is_initialized(&self) -> bool {
    self.initialized.load(Ordering::SeqCst)
}
```

2. **丰富 InitializeResponse**
   - 当前为空结构体，可添加服务器能力声明
   - 参考 LSP 协议添加 `capabilities` 字段

3. **增强错误信息**
   - 当前错误信息为静态字符串
   - 可添加连接标识等上下文信息便于调试

4. **metrics 支持**
   - 记录初始化耗时、失败次数等指标
   - 便于运维监控

### 相关文件引用

- 本文件：`codex-rs/exec-server/src/server/handler.rs`
- 协议定义：`codex-rs/exec-server/src/protocol.rs`
- 请求处理：`codex-rs/exec-server/src/server/processor.rs`
- 本地后端：`codex-rs/exec-server/src/client/local_backend.rs`
- JSON-RPC 工具：`codex-rs/exec-server/src/server/jsonrpc.rs`
