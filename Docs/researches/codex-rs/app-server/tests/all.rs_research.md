# codex-rs/app-server/tests/all.rs 研究文档

## 概述

`codex-rs/app-server/tests/all.rs` 是 Codex App Server 的集成测试入口文件，采用 Rust 的测试模块聚合模式。该文件本身非常简洁（仅3行），但其背后是一个完整的集成测试架构，通过 `mod suite` 聚合了分布在 `tests/suite/` 目录下的所有测试模块。

---

## 场景与职责

### 1.1 测试架构定位

| 层级 | 文件/目录 | 职责 |
|------|----------|------|
| 入口 | `tests/all.rs` | 单一集成测试二进制文件的入口点 |
| 测试模块 | `tests/suite/` | 按功能域组织的测试用例 |
| 测试支持库 | `tests/common/` | 共享的测试工具、Mock服务器、辅助函数 |

### 1.2 核心测试场景

该测试套件覆盖以下主要场景：

1. **协议兼容性测试**：验证 JSON-RPC 2.0 协议的正确实现
2. **Thread 生命周期管理**：创建、恢复、归档、删除对话线程
3. **Turn 执行流程**：用户输入处理、模型调用、工具执行
4. **认证与授权**：API Key、ChatGPT OAuth 登录流程
5. **WebSocket 传输层**：连接管理、消息路由、多客户端支持
6. **文件系统 API**：安全的文件读写、目录操作
7. **动态工具调用**：客户端注册工具的完整调用链路
8. **配置管理**：配置读取、写入、分层覆盖
9. **实时对话**：语音/音频输入处理
10. **MCP 服务器集成**：外部工具服务器的发现与调用

### 1.3 测试执行模式

```rust
// tests/all.rs
// Single integration test binary that aggregates all test modules.
// The submodules live in `tests/suite/`.
mod suite;
```

- 使用 `cargo test -p codex-app-server` 执行所有集成测试
- 使用 `serial_test` crate 控制测试串行执行（避免资源冲突）
- 通过 `wiremock` 模拟外部模型服务器

---

## 功能点目的

### 2.1 测试模块组织 (`tests/suite/mod.rs`)

```rust
mod auth;                           // 认证相关测试
mod conversation_summary;           // 对话摘要
mod fuzzy_file_search;              // 模糊文件搜索
mod v2;                             // v2 API 测试（主要）
```

### 2.2 V2 API 测试模块 (`tests/suite/v2/mod.rs`)

| 模块 | 测试目的 |
|------|---------|
| `account.rs` | 账户信息、登录状态查询 |
| `analytics.rs` | 分析事件上报 |
| `app_list.rs` | 应用列表查询 |
| `collaboration_mode_list.rs` | 协作模式列表 |
| `command_exec.rs` | 命令执行（Unix） |
| `compaction.rs` | 对话压缩 |
| `config_rpc.rs` | 配置 RPC 操作 |
| `connection_handling_websocket.rs` | WebSocket 连接管理 |
| `dynamic_tools.rs` | 动态工具注册与调用 |
| `fs.rs` | 文件系统操作 |
| `initialize.rs` | 客户端初始化握手 |
| `mcp_server_elicitation.rs` | MCP 服务器工具发现 |
| `model_list.rs` | 模型列表查询 |
| `plugin_*.rs` | 插件安装/卸载/查询 |
| `request_permissions.rs` | 权限请求流程 |
| `request_user_input.rs` | 用户输入请求 |
| `review.rs` | 代码审查 |
| `thread_*.rs` | 线程各种操作 |
| `turn_*.rs` | Turn 各种操作 |

### 2.3 测试支持库 (`tests/common/`)

| 模块 | 功能 |
|------|------|
| `lib.rs` | 公共导出、类型转换工具 |
| `mcp_process.rs` | MCP 进程管理（~1000行核心工具） |
| `mock_model_server.rs` | Mock 模型服务器 |
| `responses.rs` | SSE 响应构造器 |
| `auth_fixtures.rs` | 认证测试夹具（JWT 构造） |
| `config.rs` | 配置 TOML 生成 |
| `rollout.rs` | 历史对话数据构造 |
| `models_cache.rs` | 模型缓存构造 |
| `analytics_server.rs` | 分析事件 Mock 服务器 |

---

## 具体技术实现

### 3.1 MCP 进程管理 (`tests/common/mcp_process.rs`)

核心结构体 `McpProcess` 封装了与 App Server 的 JSON-RPC 通信：

```rust
pub struct McpProcess {
    next_request_id: AtomicI64,
    process: Child,                    // 保持进程存活
    stdin: Option<ChildStdin>,         // JSON-RPC 输入
    stdout: BufReader<ChildStdout>,    // JSON-RPC 输出
    pending_messages: VecDeque<JSONRPCMessage>,
}
```

**关键方法**：

| 方法 | 用途 |
|------|------|
| `new(codex_home)` | 启动 codex-app-server 进程 |
| `initialize()` | 执行初始化握手 |
| `send_*_request()` | 发送各类 JSON-RPC 请求 |
| `read_stream_until_*()` | 等待特定响应/通知 |
| `interrupt_turn_and_wait_for_aborted()` | 中断 Turn 并等待清理 |

### 3.2 Mock 模型服务器 (`tests/common/mock_model_server.rs`)

使用 `wiremock` 创建模拟的 OpenAI Responses API：

```rust
pub async fn create_mock_responses_server_sequence(
    responses: Vec<String>,
) -> MockServer {
    let server = responses::start_mock_server().await;
    let seq_responder = SeqResponder {
        num_calls: AtomicUsize::new(0),
        responses,
    };
    Mock::given(method("POST"))
        .and(path_regex(".*/responses$"))
        .respond_with(seq_responder)
        .expect(num_calls as u64)
        .mount(&server)
        .await;
    server
}
```

### 3.3 SSE 响应构造 (`tests/common/responses.rs`)

```rust
pub fn create_shell_command_sse_response(
    command: Vec<String>,
    workdir: Option<&Path>,
    timeout_ms: Option<u64>,
    call_id: &str,
) -> anyhow::Result<String> {
    let tool_call_arguments = serde_json::to_string(&json!({
        "command": command_str,
        "workdir": workdir.map(|w| w.to_string_lossy()),
        "timeout_ms": timeout_ms
    }))?;
    Ok(responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_function_call(call_id, "shell_command", &tool_call_arguments),
        responses::ev_completed("resp-1"),
    ]))
}
```

### 3.4 认证测试夹具 (`tests/common/auth_fixtures.rs`)

支持构造 ChatGPT 风格的 JWT Token：

```rust
pub fn encode_id_token(claims: &ChatGptIdTokenClaims) -> Result<String> {
    let header = json!({ "alg": "none", "typ": "JWT" });
    // ... 构造 JWT payload
    Ok(format!("{header_b64}.{payload_b64}.{signature_b64}"))
}

pub fn write_chatgpt_auth(
    codex_home: &Path,
    fixture: ChatGptAuthFixture,
    cli_auth_credentials_store_mode: AuthCredentialsStoreMode,
) -> Result<()>
```

### 3.5 典型测试模式

以 `thread_start.rs` 为例，展示测试结构：

```rust
#[tokio::test]
async fn thread_start_creates_thread_and_emits_started() -> Result<()> {
    // 1. 准备 Mock 服务器
    let server = create_mock_responses_server_repeating_assistant("Done").await;
    
    // 2. 创建临时 CODEX_HOME
    let codex_home = TempDir::new()?;
    create_config_toml(codex_home.path(), &server.uri())?;
    
    // 3. 启动 MCP 进程并初始化
    let mut mcp = McpProcess::new(codex_home.path()).await?;
    timeout(DEFAULT_READ_TIMEOUT, mcp.initialize()).await??;
    
    // 4. 发送请求
    let req_id = mcp.send_thread_start_request(ThreadStartParams {
        model: Some("gpt-5.1".to_string()),
        ..Default::default()
    }).await?;
    
    // 5. 验证响应
    let resp: JSONRPCResponse = timeout(
        DEFAULT_READ_TIMEOUT,
        mcp.read_stream_until_response_message(RequestId::Integer(req_id)),
    ).await??;
    let ThreadStartResponse { thread, .. } = to_response::<ThreadStartResponse>(resp)?;
    assert!(!thread.id.is_empty());
    
    // 6. 验证通知
    let notif = loop {
        let message = timeout(remaining, mcp.read_next_message()).await??;
        if notif.method == "thread/started" { break notif; }
    };
    
    Ok(())
}
```

---

## 关键代码路径与文件引用

### 4.1 测试入口与模块树

```
codex-rs/app-server/tests/
├── all.rs                          # 测试入口（3行）
├── suite/
│   ├── mod.rs                      # 测试模块聚合
│   ├── auth.rs                     # 认证测试（233行）
│   ├── conversation_summary.rs
│   ├── fuzzy_file_search.rs
│   └── v2/                         # V2 API 测试（主要）
│       ├── mod.rs                  # 47个测试模块
│       ├── thread_start.rs         # 线程创建（493行）
│       ├── turn_start.rs           # Turn 执行（1000+行）
│       ├── initialize.rs           # 初始化（319行）
│       ├── connection_handling_websocket.rs  # WebSocket（461行）
│       ├── dynamic_tools.rs        # 动态工具（660行）
│       ├── fs.rs                   # 文件系统（613行）
│       └── ...                     # 其他模块
└── common/                         # 测试支持库
    ├── Cargo.toml                  # 独立 crate 配置
    ├── lib.rs                      # 公共导出
    ├── mcp_process.rs              # MCP 进程管理（1000+行）
    ├── mock_model_server.rs        # Mock 服务器
    ├── responses.rs                # SSE 响应构造
    ├── auth_fixtures.rs            # 认证夹具（169行）
    ├── config.rs                   # 配置生成
    ├── rollout.rs                  # 历史数据构造（208行）
    └── ...
```

### 4.2 被测系统关键路径

```
codex-rs/app-server/src/
├── lib.rs                          # App Server 主库（883行）
├── main.rs                         # 二进制入口
├── message_processor.rs            # 消息处理器（核心）
├── codex_message_processor.rs      # Codex 消息处理
├── transport.rs                    # 传输层（stdio/WebSocket）
├── config_api.rs                   # 配置 API
├── fs_api.rs                       # 文件系统 API
├── dynamic_tools.rs                # 动态工具
└── ...
```

### 4.3 协议定义

```
codex-rs/app-server-protocol/src/
├── protocol/
│   ├── v2.rs                       # V2 协议定义
│   └── common.rs                   # 公共类型
```

---

## 依赖与外部交互

### 5.1 测试依赖 (`Cargo.toml` dev-dependencies)

```toml
[dev-dependencies]
app_test_support = { workspace = true }      # 本测试支持库
core_test_support = { workspace = true }     # core 测试支持
codex-utils-cargo-bin = { workspace = true } # 二进制路径解析
wiremock = { workspace = true }              # HTTP Mock
serial_test = { workspace = true }           # 串行测试控制
pretty_assertions = { workspace = true }     # 美观的断言输出
```

### 5.2 外部进程交互

| 进程 | 用途 | 控制方式 |
|------|------|---------|
| `codex-app-server` | 被测服务器 | `McpProcess` 启动 stdin/stdout |
| Mock HTTP Server | 模拟模型 API | `wiremock::MockServer` |
| Analytics Mock | 模拟分析事件接收 | `wiremock::MockServer` |

### 5.3 环境变量控制

| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 测试隔离的配置/数据目录 |
| `RUST_LOG` | 日志级别控制 |
| `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` | 请求来源覆盖（测试用） |
| `OPENAI_API_KEY` | 模拟 API Key 认证 |

### 5.4 跨 crate 依赖

```
codex-app-server tests
├──> codex-app-server-protocol    # JSON-RPC 协议类型
├──> codex-core                   # 核心功能
├──> codex-protocol               # 协议类型
├──> codex-utils-cargo-bin        # 二进制定位
└──> core_test_support            # core 测试工具
```

---

## 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 测试稳定性风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 竞态条件 | 异步测试中的时序依赖 | 使用 `timeout()` 包装，设置合理超时 |
| 端口冲突 | WebSocket 测试使用随机端口 | 绑定到 `127.0.0.1:0` 让 OS 分配 |
| 文件系统污染 | 测试创建临时文件 | 使用 `TempDir` 自动清理 |
| 环境泄漏 | 环境变量影响后续测试 | `McpProcess::new_with_env()` 显式控制 |

#### 6.1.2 测试覆盖率盲区

```rust
// tests/suite/v2/mod.rs 中的条件编译
#[cfg(unix)]
mod command_exec;                   // 仅 Unix 测试命令执行
#[cfg(unix)]
mod connection_handling_websocket_unix;  // 仅 Unix WebSocket
```

- Windows 特定行为覆盖不足
- 网络故障场景模拟有限
- 大规模并发测试缺失

### 6.2 边界情况处理

#### 6.2.1 输入验证边界

```rust
// turn_start.rs 中的超大输入测试
#[tokio::test]
async fn turn_start_rejects_combined_oversized_text_input() -> Result<()> {
    let first = "x".repeat(MAX_USER_INPUT_TEXT_CHARS / 2);
    let second = "y".repeat(MAX_USER_INPUT_TEXT_CHARS / 2 + 1);
    // 验证拒绝逻辑...
}
```

#### 6.2.2 连接边界

```rust
// connection_handling_websocket.rs
async fn assert_no_message(stream: &mut WsClient, wait_for: Duration) -> Result<()> {
    match timeout(wait_for, stream.next()).await {
        Err(_) => Ok(()),  // 预期超时（无消息）
        Ok(_) => bail!("unexpected frame"),
    }
}
```

### 6.3 改进建议

#### 6.3.1 架构层面

1. **测试并行化**
   - 当前使用 `serial_test` 串行执行，可考虑更细粒度的资源隔离
   - 为每个测试分配独立的临时端口/目录

2. **Mock 服务器增强**
   - 当前 Mock 仅支持顺序响应，可扩展为状态机模式
   - 增加延迟模拟、故障注入能力

3. **测试数据管理**
   - 引入工厂模式构造复杂测试数据
   - 使用快照测试（insta）验证协议消息格式

#### 6.3.2 代码层面

1. **超时统一**
   ```rust
   // 当前分散定义
   const DEFAULT_READ_TIMEOUT: Duration = Duration::from_secs(10);  // 多处重复
   
   // 建议：统一到 test_support
   pub const TEST_TIMEOUT: Duration = Duration::from_secs(10);
   ```

2. **错误消息断言**
   ```rust
   // 当前使用字符串包含检查
   assert!(err.error.message.contains("expected message"));
   
   // 建议：使用结构化错误码
   assert_eq!(err.error.code, EXPECTED_ERROR_CODE);
   ```

3. **测试文档化**
   - 增加更多 `// Given / When / Then` 注释
   - 使用 `rstest` 参数化测试减少重复代码

#### 6.3.3 监控与可观测性

1. **测试失败诊断**
   - 捕获并保存失败测试的完整日志
   - 保留 Mock 服务器接收的所有请求用于调试

2. **性能基准**
   - 增加关键路径的性能回归测试
   - 监控测试执行时间趋势

### 6.4 已知技术债务

1. **条件编译复杂性**
   ```rust
   // mcp_process.rs 中的平台差异
   #[cfg(windows)]
   const DEFAULT_READ_TIMEOUT: Duration = Duration::from_secs(25);
   #[cfg(not(windows))]
   const DEFAULT_READ_TIMEOUT: Duration = Duration::from_secs(10);
   ```

2. **测试夹具重复**
   - 多个测试文件包含类似的 `create_config_toml()` 函数
   - 建议提取到 `test_support` 并提供更多配置选项

3. **异步模式不一致**
   - 部分测试使用 `tokio::time::timeout`，部分依赖内置超时
   - 建议统一超时策略

---

## 附录：关键类型定义

### A.1 JSON-RPC 消息类型

```rust
// codex-app-server-protocol
pub enum JSONRPCMessage {
    Request(JSONRPCRequest),
    Response(JSONRPCResponse),
    Notification(JSONRPCNotification),
    Error(JSONRPCError),
}
```

### A.2 Thread 核心类型

```rust
pub struct ThreadStartResponse {
    pub thread: Thread,
    pub model_provider: String,
    pub reasoning_effort: Option<ReasoningEffort>,
    pub service_tier: Option<ServiceTier>,
}

pub struct Thread {
    pub id: String,
    pub name: Option<String>,
    pub preview: String,
    pub created_at: i64,
    pub ephemeral: bool,
    pub path: Option<PathBuf>,
    pub status: ThreadStatus,
}
```

### A.3 Turn 核心类型

```rust
pub struct TurnStartParams {
    pub thread_id: String,
    pub input: Vec<UserInput>,
    pub model: Option<String>,
    pub effort: Option<ReasoningEffort>,
    pub personality: Option<Personality>,
    pub collaboration_mode: Option<CollaborationMode>,
    // ...
}
```

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/app-server/tests/all.rs 及其依赖模块*
