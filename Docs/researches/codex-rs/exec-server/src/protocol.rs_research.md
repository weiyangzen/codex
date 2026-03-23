# protocol.rs 深入研究文档

## 场景与职责

`protocol.rs` 是 `codex-exec-server` crate 的协议定义模块，负责声明执行服务器特定的 RPC 方法和相关数据结构。该模块基于 `codex-app-server-protocol` crate 提供的 JSON-RPC 基础类型，定义了执行服务器专有的消息格式和协议常量。

## 功能点目的

### 1. 协议常量定义
- **目的**：集中管理 RPC 方法名称，避免硬编码字符串分散在代码各处
- **设计**：使用 `const` 定义方法名，编译期检查和内联优化

### 2. 类型安全的消息结构
- **目的**：为初始化握手提供强类型参数和响应
- **实现**：使用 `serde` 派生宏实现序列化/反序列化

### 3. 前后端契约
- **目的**：明确定义客户端和服务器之间的通信契约
- **当前范围**：目前仅包含初始化协议，预留扩展空间

## 具体技术实现

### 协议常量

```rust
// JSON-RPC 方法名称常量
pub const INITIALIZE_METHOD: &str = "initialize";
pub const INITIALIZED_METHOD: &str = "initialized";
```

### 初始化请求参数

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]  // 序列化为 camelCase
pub struct InitializeParams {
    pub client_name: String,  // 客户端标识名称
}
```

序列化示例：
```json
{
  "clientName": "codex-core"
}
```

### 初始化响应

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeResponse {}
```

当前为空结构体，预留未来扩展（如服务器能力声明、版本信息等）。

## 关键代码路径与文件引用

### 使用位置

| 文件 | 使用方式 |
|------|----------|
| `client.rs` | 导入 `INITIALIZE_METHOD`, `INITIALIZED_METHOD`, `InitializeParams`, `InitializeResponse` |
| `server/processor.rs` | 导入协议常量和类型，处理 `initialize` 请求和 `initialized` 通知 |
| `server/handler.rs` | 使用 `InitializeResponse` 作为 `initialize` 方法返回类型 |
| `client/local_backend.rs` | 使用 `InitializeResponse` 作为进程内后端返回类型 |
| `tests/initialize.rs` | 构造 `InitializeParams` 进行测试 |
| `tests/websocket.rs` | 构造 `InitializeParams` 进行测试 |
| `tests/process.rs` | 构造 `InitializeParams` 进行测试 |

### 导出位置

在 `lib.rs` 中公开导出：
```rust
pub use protocol::InitializeParams;
pub use protocol::InitializeResponse;
```

注意：协议常量 (`INITIALIZE_METHOD`, `INITIALIZED_METHOD`) 为 crate 内部使用，不对外导出。

### 依赖关系

```
protocol.rs
├── serde (Serialize, Deserialize)
└── 被以下模块使用：
    ├── client.rs
    ├── client/local_backend.rs
    ├── server/handler.rs
    ├── server/processor.rs
    └── tests/
```

## 依赖与外部交互

### 标准库依赖
- 无（仅使用 `serde`）

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `serde` | 序列化/反序列化派生宏 |

### 与 app-server-protocol 的关系

`protocol.rs` 定义的是执行服务器**专有**协议，基于 `codex-app-server-protocol` 定义的通用 JSON-RPC 类型：

```rust
// codex-app-server-protocol 提供基础类型
codex_app_server_protocol::JSONRPCMessage
codex_app_server_protocol::JSONRPCRequest
codex_app_server_protocol::JSONRPCResponse
// ...

// protocol.rs 定义执行服务器特定的参数和响应
protocol::InitializeParams
protocol::InitializeResponse
protocol::INITIALIZE_METHOD
protocol::INITIALIZED_METHOD
```

## 风险、边界与改进建议

### 当前设计特点

1. **极简设计**：当前仅包含初始化协议，符合 stub 阶段定位
2. **强类型**：所有数据结构都实现了 `Debug`, `Clone`, `PartialEq`, `Eq`
3. **命名规范**：使用 `camelCase` 序列化，符合 JSON 惯例

### 潜在风险

1. **协议版本缺失**：
   - 当前无协议版本字段
   - 未来协议演进可能导致兼容性问题

2. **InitializeResponse 为空**：
   - 未声明服务器能力
   - 客户端无法协商功能支持

3. **错误码未定义**：
   - 执行服务器特定的错误码分散在代码中
   - 如 `processor.rs` 中的 `-32601` (method_not_found)

### 改进建议

1. **添加协议版本**：
   ```rust
   #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
   #[serde(rename_all = "camelCase")]
   pub struct InitializeParams {
       pub client_name: String,
       pub protocol_version: String,  // 如 "1.0"
   }
   
   #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
   #[serde(rename_all = "camelCase")]
   pub struct InitializeResponse {
       pub protocol_version: String,
       pub server_version: String,
   }
   ```

2. **定义服务器能力**：
   ```rust
   #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
   #[serde(rename_all = "camelCase")]
   pub struct ServerCapabilities {
       pub process_management: bool,
       pub sandboxing: bool,
       pub max_processes: Option<u32>,
   }
   
   pub struct InitializeResponse {
       pub capabilities: ServerCapabilities,
   }
   ```

3. **集中错误码定义**：
   ```rust
   pub mod error_codes {
       // JSON-RPC 标准错误码
       pub const PARSE_ERROR: i64 = -32700;
       pub const INVALID_REQUEST: i64 = -32600;
       pub const METHOD_NOT_FOUND: i64 = -32601;
       pub const INVALID_PARAMS: i64 = -32602;
       pub const INTERNAL_ERROR: i64 = -32603;
       
       // 执行服务器特定错误码
       pub const PROCESS_START_FAILED: i64 = -32000;
       pub const PROCESS_NOT_FOUND: i64 = -32001;
       pub const SANDBOX_ERROR: i64 = -32002;
   }
   ```

4. **添加更多协议方法**：
   ```rust
   // 进程管理
   pub const PROCESS_START_METHOD: &str = "process/start";
   pub const PROCESS_STOP_METHOD: &str = "process/stop";
   pub const PROCESS_LIST_METHOD: &str = "process/list";
   
   // 沙箱管理
   pub const SANDBOX_CREATE_METHOD: &str = "sandbox/create";
   pub const SANDBOX_DESTROY_METHOD: &str = "sandbox/destroy";
   ```

5. **文档完善**：
   ```rust
   //! # 执行服务器协议
   //! 
   //! 基于 JSON-RPC 2.0 的子集（不包含 `jsonrpc: "2.0"` 字段）。
   //! 
   //! ## 初始化流程
   //! 
   //! 1. 客户端发送 `initialize` 请求
   //! 2. 服务器返回 `InitializeResponse`
   //! 3. 客户端发送 `initialized` 通知
   //! 4. 连接就绪，可发送其他请求
   ```

6. **使用类型状态模式**：
   ```rust
   // 区分未初始化和已初始化连接
   struct Uninitialized;
   struct Initialized;
   
   struct Connection<State = Uninitialized> {
       // ...
       _state: PhantomData<State>,
   }
   ```

### 协议演进方向

当前协议处于 stub 阶段，未来需要定义：

1. **进程生命周期管理**：
   - 启动、停止、信号发送
   - 状态查询、输出流订阅

2. **沙箱管理**：
   - 创建、配置、销毁
   - 资源限制、网络隔离

3. **文件系统操作**：
   - 在沙箱内读写文件
   - 挂载、同步

4. **安全机制**：
   - 认证、授权
   - 审计日志
