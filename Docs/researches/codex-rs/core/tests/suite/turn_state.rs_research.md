# turn_state.rs 深入研究文档

## 场景与职责

`turn_state.rs` 是 Codex 核心测试套件中的关键测试文件，负责验证**回合状态（Turn State）**机制的正确性。Turn State 是一种粘性路由（Sticky Routing）机制，用于在单个用户回合（Turn）内的多个请求之间保持状态一致性，确保模型 API 能够正确跟踪和恢复回合上下文。

### 核心场景
1. **多轮请求状态保持**：单个用户输入可能触发多个模型请求（如工具调用后的继续对话）
2. **SSE 和 WebSocket 传输**：验证两种传输方式下 Turn State 的正确传递
3. **回合边界重置**：新回合开始时 Turn State 应该被清除

---

## 功能点目的

### 1. Turn State 机制

Turn State 是通过 HTTP 头 `x-codex-turn-state` 传递的 opaque token，用于：

- **粘性路由**：确保同一回合的多个请求路由到同一后端实例
- **状态恢复**：后端可以通过 Turn State 恢复回合上下文
- **故障转移**：在连接断开重连时保持回合连续性

### 2. 生命周期

```
用户提交 Turn
    │
    ▼
首次请求 ──► 后端返回 x-codex-turn-state: <token>
    │
    ▼
后续请求 ──► 请求头携带 x-codex-turn-state: <token>
    │
    ▼
回合完成 ──► Turn State 丢弃
    │
    ▼
新回合 ──► 首次请求不携带 Turn State
```

### 3. 相关 Header

| Header | 方向 | 用途 |
|--------|------|------|
| `x-codex-turn-state` | 请求/响应 | 回合状态 token |
| `x-codex-turn-metadata` | 请求 | 回合元数据（包含 turn_id）|

---

## 具体技术实现

### 关键流程

#### 1. Turn State 管理（`codex-rs/core/src/client.rs`）

```rust
pub struct ModelClientSession {
    client: ModelClient,
    websocket_session: WebsocketSession,
    /// Turn state for sticky routing.
    turn_state: Arc<OnceLock<String>>,  // OnceLock 确保只设置一次
}

impl ModelClientSession {
    pub fn new_session(&self) -> ModelClientSession {
        ModelClientSession {
            client: self.clone(),
            websocket_session: self.take_cached_websocket_session(),
            turn_state: Arc::new(OnceLock::new()),  // 每个新会话创建新的 OnceLock
        }
    }
}
```

#### 2. WebSocket 头构建

```rust
fn build_websocket_headers(
    &self,
    turn_state: Option<&Arc<OnceLock<String>>>,
    turn_metadata_header: Option<&str>,
) -> ApiHeaderMap {
    let turn_metadata_header = parse_turn_metadata_header(turn_metadata_header);
    let headers = build_responses_headers(
        self.state.beta_features_header.as_deref(),
        turn_state,           // 可能包含已设置的 turn_state
        turn_metadata_header.as_ref(),
    );
    // ...
}
```

#### 3. SSE 请求头构建（`codex-rs/codex-api/src/sse/responses.rs`）

```rust
pub fn build_responses_headers(
    beta_features: Option<&str>,
    turn_state: Option<&Arc<OnceLock<String>>>,
    turn_metadata: Option<&TurnMetadata>,
) -> HeaderMap {
    let mut headers = HeaderMap::new();
    
    // 如果 turn_state 已设置，添加到请求头
    if let Some(turn_state) = turn_state {
        if let Some(state) = turn_state.get() {
            headers.insert(X_CODEX_TURN_STATE_HEADER, HeaderValue::from_str(state).unwrap());
        }
    }
    
    // 添加 turn 元数据
    if let Some(metadata) = turn_metadata {
        headers.insert(X_CODEX_TURN_METADATA_HEADER, 
            HeaderValue::from_str(&serde_json::to_string(metadata).unwrap()).unwrap());
    }
    
    headers
}
```

#### 4. Turn State 解析与存储

```rust
// 从响应头中提取 Turn State
fn parse_turn_state_header(response: &Response) -> Option<String> {
    response
        .headers()
        .get(X_CODEX_TURN_STATE_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(String::from)
}

// 存储到 OnceLock
if let Some(state) = parse_turn_state_header(&response) {
    let _ = turn_state.set(state);  // OnceLock 确保只设置一次
}
```

### 数据结构

#### 1. `TurnMetadata`（协议层）

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TurnMetadata {
    pub turn_id: String,
    pub started_at: Option<u64>,
    // 其他元数据...
}
```

#### 2. `ModelClientSession` 状态

```rust
pub struct ModelClientSession {
    client: ModelClient,
    websocket_session: WebsocketSession,
    turn_state: Arc<OnceLock<String>>,  // 线程安全，只写一次
}

impl ModelClientSession {
    /// Creates a fresh turn-scoped streaming session.
    pub fn new_session(&self) -> ModelClientSession {
        ModelClientSession {
            client: self.clone(),
            websocket_session: self.take_cached_websocket_session(),
            turn_state: Arc::new(OnceLock::new()),  // 新回合 = 新的 OnceLock
        }
    }
}
```

#### 3. WebSocket 连接配置

```rust
#[derive(Debug, Clone)]
pub struct WebSocketConnectionConfig {
    pub requests: Vec<Vec<Value>>,           // 模拟的请求序列
    pub response_headers: Vec<(String, String)>, // 响应头（包含 turn_state）
    pub accept_delay: Option<Duration>,      // 握手延迟
    pub close_after_requests: bool,          // 请求完成后是否关闭
}
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/client.rs` | `ModelClientSession` 实现，Turn State 管理 |
| `codex-rs/core/src/state/turn.rs` | 回合状态（TurnState）数据结构 |
| `codex-rs/codex-api/src/sse/responses.rs` | SSE 响应处理，Header 构建 |
| `codex-rs/codex-api/src/endpoint/responses.rs` | Responses API 端点实现 |
| `codex-rs/codex-api/src/endpoint/responses_websocket.rs` | WebSocket 响应处理 |

### 测试支持文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/tests/common/responses.rs` | Mock 服务器和 WebSocket 测试服务器 |
| `codex-rs/core/tests/common/test_codex.rs` | 测试 harness 构建 |

### 关键代码路径

```
1. 回合开始
   codex-rs/core/src/client.rs
   └── ModelClient::new_session
       └── 创建新的 ModelClientSession，初始化空的 turn_state OnceLock

2. 首次请求
   codex-rs/core/src/client.rs
   └── ModelClientSession::stream
       └── 请求不包含 turn_state（OnceLock 未设置）
       └── 响应包含 x-codex-turn-state header
       └── 存储到 OnceLock

3. 后续请求
   codex-rs/core/src/client.rs
   └── ModelClientSession::stream
       └── build_websocket_headers
           └── 从 OnceLock 获取 turn_state 并添加到请求头

4. 新回合
   codex-rs/core/src/codex.rs
   └── 调用 ModelClient::new_session
       └── 创建新的 OnceLock，旧 turn_state 被丢弃
```

---

## 依赖与外部交互

### 内部依赖

```rust
// 测试依赖
use core_test_support::responses::{
    WebSocketConnectionConfig,      // WebSocket 测试配置
    ev_assistant_message,           // SSE 事件构造
    ev_completed,
    ev_response_created,
    ev_reasoning_item,
    ev_shell_command_call,
    mount_response_sequence,        // Mock SSE 序列
    sse,                            // SSE 构造
    sse_response,
    start_mock_server,              // 启动 Mock 服务器
    start_websocket_server_with_headers,  // 启动 WebSocket 测试服务器
};
use core_test_support::test_codex::test_codex;
```

### 协议常量

```rust
const TURN_STATE_HEADER: &str = "x-codex-turn-state";
const X_CODEX_TURN_STATE_HEADER: &str = "x-codex-turn-state";
const X_CODEX_TURN_METADATA_HEADER: &str = "x-codex-turn-metadata";
```

### 测试基础设施

#### Mock SSE 服务器（`wiremock`）

```rust
let first_response = sse(vec![
    ev_response_created("resp-1"),
    ev_reasoning_item("rsn-1", &["thinking"], &[]),
    ev_shell_command_call(call_id, "echo turn-state"),
    ev_completed("resp-1"),
]);

// 首次响应设置 turn_state
let responses = vec![
    sse_response(first_response).insert_header(TURN_STATE_HEADER, "ts-1"),
    sse_response(second_response),  // 后续响应不设置
    sse_response(third_response),
];
let request_log = mount_response_sequence(&server, responses).await;
```

#### WebSocket 测试服务器

```rust
let server = start_websocket_server_with_headers(vec![
    WebSocketConnectionConfig {
        requests: vec![vec![
            ev_response_created("resp-1"),
            ev_shell_command_call(call_id, "echo websocket"),
            ev_completed("resp-1"),
        ]],
        response_headers: vec![(TURN_STATE_HEADER.to_string(), "ts-1".to_string())],
        accept_delay: None,
        close_after_requests: true,
    },
    // ... 更多连接配置
]).await;
```

---

## 风险、边界与改进建议

### 已知风险

1. **Turn State 丢失**
   - 如果首次请求失败，Turn State 可能无法获取
   - 重连时可能需要重新建立 Turn State
   - **缓解**：实现 Turn State 恢复机制或优雅降级

2. **并发问题**
   - 多个并发请求可能竞争设置 Turn State
   - **缓解**：使用 `OnceLock` 确保只设置一次，后续请求读取相同值

3. **跨实例路由**
   - 如果负载均衡器将请求路由到不同实例，Turn State 可能无效
   - **缓解**：Turn State 包含实例标识，或后端共享状态

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 首次请求失败 | 无 Turn State，后续请求继续不携带 |
| 响应无 Turn State | OnceLock 保持未设置，后续请求不携带 |
| 回合内重连 | 新 WebSocket 连接，但 turn_state OnceLock 保持不变 |
| 新回合 | 创建新的 ModelClientSession，新的 OnceLock |
| 并发请求 | OnceLock 确保所有请求看到相同的 Turn State |

### 改进建议

1. **Turn State 持久化**
   - 在回合期间持久化 Turn State，防止进程重启丢失
   - 支持从持久化存储恢复回合

2. **可观测性增强**
   - 记录 Turn State 的创建、使用和丢弃事件
   - 在遥测中包含 Turn State 生命周期指标

3. **容错改进**
   - 当 Turn State 无效时，自动请求新的 Turn State
   - 实现 Turn State 刷新机制

4. **测试覆盖**
   - 增加网络中断和重连场景测试
   - 增加高并发场景测试
   - 增加后端实例切换场景测试

### 相关配置

```rust
// ModelProviderInfo 中的 WebSocket 配置
pub struct ModelProviderInfo {
    pub supports_websockets: bool,
    pub websocket_connect_timeout_ms: Option<u64>,
    // ...
}
```

---

## 测试用例详解

### 1. `responses_turn_state_persists_within_turn_and_resets_after`

**目的**：验证 SSE 传输下 Turn State 在回合内保持、回合间重置

**流程**：
1. 首次请求：验证无 `x-codex-turn-state` 头
2. 首次响应：返回 `x-codex-turn-state: ts-1`
3. 第二次请求：验证携带 `x-codex-turn-state: ts-1`
4. 第三次请求（新回合）：验证无 `x-codex-turn-state` 头

**验证点**：
- `turn_id` 在回合内保持一致
- 新回合生成新的 `turn_id`

### 2. `websocket_turn_state_persists_within_turn_and_resets_after`

**目的**：验证 WebSocket 传输下 Turn State 机制

**流程**：
1. 启动 WebSocket 测试服务器，配置 3 个连接
2. 第一个连接返回 Turn State
3. 第二个连接验证收到 Turn State
4. 第三个连接验证无 Turn State（新回合）

**验证点**：
- WebSocket 握手头正确传递 Turn State
- 回合边界正确重置 Turn State

### 关键断言

```rust
// 首次请求无 Turn State
assert_eq!(requests[0].header(TURN_STATE_HEADER), None);

// 后续请求携带 Turn State
assert_eq!(
    requests[1].header(TURN_STATE_HEADER),
    Some("ts-1".to_string())
);

// 新回合无 Turn State
assert_eq!(requests[2].header(TURN_STATE_HEADER), None);

// turn_id 验证
let first_turn_id = parse_turn_id(requests[0].header("x-codex-turn-metadata"));
let second_turn_id = parse_turn_id(requests[1].header("x-codex-turn-metadata"));
let third_turn_id = parse_turn_id(requests[2].header("x-codex-turn-metadata"));

assert_eq!(first_turn_id, second_turn_id);  // 同一回合
assert_ne!(second_turn_id, third_turn_id);  // 不同回合
```

---

## 架构关系图

```
┌─────────────────────────────────────────────────────────────┐
│                        Codex Session                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              ModelClient (Session-scoped)           │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │         ModelClientSession (Turn-scoped)    │   │   │
│  │  │  ┌─────────────────────────────────────┐   │   │   │
│  │  │  │  turn_state: Arc<OnceLock<String>>  │   │   │   │
│  │  │  │  - 首次请求: 未设置                  │   │   │   │
│  │  │  │  - 首次响应: 设置值                  │   │   │   │
│  │  │  │  - 后续请求: 读取值                  │   │   │   │
│  │  │  └─────────────────────────────────────┘   │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  │                    ▲                                │   │
│  │     新回合: new_session() 创建新实例                │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     OpenAI API Server                       │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │   SSE Endpoint  │    │ WebSocket Conn  │                │
│  │  x-codex-turn-state  │  x-codex-turn-state              │
│  └─────────────────┘    └─────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```
