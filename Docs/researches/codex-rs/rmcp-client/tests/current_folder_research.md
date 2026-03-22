# codex-rs/rmcp-client/tests 目录研究文档

## 1. 场景与职责

### 1.1 目录定位

`codex-rs/rmcp-client/tests` 是 `codex-rmcp-client` crate 的集成测试目录，包含 3 个测试文件：

| 文件 | 行数 | 职责 |
|------|------|------|
| `process_group_cleanup.rs` | 93 | 验证 Unix 进程组清理机制 |
| `resources.rs` | 151 | 验证 MCP Resource 协议操作 |
| `streamable_http_recovery.rs` | 272 | 验证 Streamable HTTP 传输的会话恢复机制 |

### 1.2 测试场景概述

该测试目录覆盖以下核心场景：

1. **进程生命周期管理**：确保 MCP 子进程在客户端 drop 时被正确终止（Unix 进程组信号机制）
2. **MCP 协议功能验证**：通过 STDIO 传输测试 Resource 列表、模板和读取操作
3. **网络容错与恢复**：验证 Streamable HTTP 传输在会话过期（404）时的自动重连机制

### 1.3 与主代码的关系

```
codex-rs/rmcp-client/
├── src/
│   ├── lib.rs                    # 模块导出
│   ├── rmcp_client.rs            # RmcpClient 主实现 (1245 行)
│   ├── logging_client_handler.rs # ClientHandler 实现
│   ├── oauth.rs                  # OAuth 凭证管理 (922 行)
│   ├── bin/
│   │   ├── test_stdio_server.rs      # 测试辅助：STDIO MCP Server (470 行)
│   │   └── test_streamable_http_server.rs  # 测试辅助：HTTP MCP Server (419 行)
│   └── ...
└── tests/                        # 本目录：集成测试
    ├── process_group_cleanup.rs
    ├── resources.rs
    └── streamable_http_recovery.rs
```

---

## 2. 功能点目的

### 2.1 process_group_cleanup.rs - 进程组清理测试

**目的**：验证当 `RmcpClient` 被 drop 时，其子进程及孙子进程能够被正确终止。

**核心测试用例**：
- `drop_kills_wrapper_process_group`: 创建一个 shell 子进程，该子进程再创建后台 sleep 进程（孙子进程），验证 client drop 后孙子进程被终止

**技术背景**：
- 使用 Unix 进程组（process_group(0)）确保整个进程树被统一管理
- 通过 `ProcessGroupGuard` 在 drop 时发送 SIGTERM，超时后发送 SIGKILL

### 2.2 resources.rs - Resource 协议测试

**目的**：验证 MCP Resource 相关协议操作的正确性。

**核心测试用例**：
- `rmcp_client_can_list_and_read_resources`: 完整测试 Resource 生命周期
  - 初始化客户端（带 Elicitation 能力协商）
  - 列出 Resources（`list_resources`）
  - 列出 Resource Templates（`list_resource_templates`）
  - 读取 Resource 内容（`read_resource`）

**验证的数据结构**：
- `RawResource`: URI、名称、标题、描述、MIME 类型
- `RawResourceTemplate`: URI 模板、名称、标题、描述
- `ResourceContents::TextResourceContents`: 文本内容读取

### 2.3 streamable_http_recovery.rs - HTTP 会话恢复测试

**目的**：验证 Streamable HTTP 传输在会话失效后的自动恢复机制。

**核心测试用例**：

| 测试用例 | 目的 |
|----------|------|
| `streamable_http_404_session_expiry_recovers_and_retries_once` | 404 会话过期后自动重连并恢复 |
| `streamable_http_401_does_not_trigger_recovery` | 401 未授权不应触发恢复（避免无限循环）|
| `streamable_http_404_recovery_only_retries_once` | 验证恢复只尝试一次，连续失败则报错 |
| `streamable_http_non_session_failure_does_not_trigger_recovery` | 500 服务器错误不应触发恢复 |

**测试机制**：
- 通过控制端点 `/test/control/session-post-failure` 注入故障
- 模拟真实网络场景：会话 ID 失效、认证失败、服务器错误

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 进程组清理流程 (process_group_cleanup.rs)

```rust
// 测试流程
1. 创建 RmcpClient::new_stdio_client("/bin/sh", args, env)
   └── 命令: "sleep 300 & child_pid=$!; echo \"$child_pid\" > \"$CHILD_PID_FILE\"; cat >/dev/null"
   
2. 等待 PID 文件写入，获取孙子进程 PID
   └── wait_for_pid_file(&child_pid_file).await
   
3. 验证孙子进程正在运行
   └── process_exists(grandchild_pid) == true
   
4. 触发 client drop
   └── drop(client);
   
5. 验证孙子进程已终止
   └── wait_for_process_exit(grandchild_pid).await
```

**底层实现**（`rmcp_client.rs` 365-422 行）：

```rust
#[cfg(unix)]
struct ProcessGroupGuard {
    process_group_id: u32,
}

impl Drop for ProcessGroupGuard {
    fn drop(&mut self) {
        // 1. 发送 SIGTERM
        terminate_process_group(process_group_id)
        // 2. 2秒后发送 SIGKILL（如果进程仍在）
        std::thread::spawn(move || {
            std::thread::sleep(PROCESS_GROUP_TERM_GRACE_PERIOD);
            kill_process_group(process_group_id)
        });
    }
}
```

#### 3.1.2 Resource 操作流程 (resources.rs)

```rust
// 测试流程
1. 创建 STDIO 客户端
   RmcpClient::new_stdio_client(stdio_server_bin()?, ...).await?

2. 初始化（带 Elicitation 处理器）
   client.initialize(init_params(), timeout, send_elicitation).await?
   
3. 列出 Resources
   let list = client.list_resources(None, timeout).await?
   // 验证: memo://codex/example-note 存在
   
4. 列出 Resource Templates
   let templates = client.list_resource_templates(None, timeout).await?
   // 验证: memo://codex/{slug} 模板存在
   
5. 读取 Resource
   let read = client.read_resource(ReadResourceRequestParams { uri: RESOURCE_URI.to_string() }, timeout).await?
   // 验证: 内容匹配 MEMO_CONTENT
```

**协议数据结构**（`test_stdio_server.rs` 166-191 行）：

```rust
const MEMO_URI: &str = "memo://codex/example-note";
const MEMO_CONTENT: &str = "This is a sample MCP resource served by the rmcp test server.";

fn memo_resource() -> Resource {
    let raw = RawResource {
        uri: MEMO_URI.to_string(),
        name: "example-note".to_string(),
        title: Some("Example Note".to_string()),
        description: Some("A sample MCP resource exposed for integration tests.".to_string()),
        mime_type: Some("text/plain".to_string()),
        size: None,
        icons: None,
        meta: None,
    };
    Resource::new(raw, None)
}
```

#### 3.1.3 HTTP 会话恢复流程 (streamable_http_recovery.rs)

```rust
// 测试流程
1. 启动测试 HTTP Server
   spawn_streamable_http_server().await?  // 返回 (Child, base_url)
   
2. 创建 Streamable HTTP 客户端
   RmcpClient::new_streamable_http_client(
       "test-streamable-http",
       &format!("{base_url}/mcp"),
       Some("test-bearer".to_string()),  // bearer token
       None, None,
       OAuthCredentialsStoreMode::File,
       Arc::new(StdMutex::new(None)),
   ).await?

3. 初始化客户端
   client.initialize(init_params(), timeout, send_elicitation).await?
   
4. 预热调用
   call_echo_tool(&client, "warmup").await?  // 确保会话建立
   
5. 注入故障（通过控制端点）
   arm_session_post_failure(&base_url, 404, 1).await?  // 下次请求返回 404
   
6. 触发恢复
   let recovered = call_echo_tool(&client, "recovered").await?
   // 验证: 自动重连后成功返回
```

**恢复机制实现**（`rmcp_client.rs` 1075-1194 行）：

```rust
async fn run_service_operation<T, F, Fut>(...) -> Result<T> {
    let service = self.service().await?;
    match Self::run_service_operation_once(...).await {
        Ok(result) => Ok(result),
        Err(error) if Self::is_session_expired_404(&error) => {
            // 检测到 404 会话过期
            self.reinitialize_after_session_expiry(&service).await?;
            // 重试操作
            let recovered_service = self.service().await?;
            Self::run_service_operation_once(recovered_service, ...).await
        }
        Err(error) => Err(error.into()),
    }
}

async fn reinitialize_after_session_expiry(&self, failed_service: &Arc<...>) -> Result<()> {
    let _recovery_guard = self.session_recovery_lock.lock().await;  // 防止并发恢复
    
    // 双重检查：确保没有其他线程已恢复
    if !Arc::ptr_eq(service, failed_service) {
        return Ok(());  // 已恢复，无需操作
    }
    
    // 重新创建传输层
    let pending_transport = Self::create_pending_transport(&self.transport_recipe, ...).await?;
    
    // 重新连接并初始化
    let (service, oauth_persistor, process_group_guard) = 
        Self::connect_pending_transport(pending_transport, ...).await?;
    
    // 更新状态
    *guard = ClientState::Ready { ... };
}
```

### 3.2 关键数据结构

#### 3.2.1 RmcpClient 结构

```rust
pub struct RmcpClient {
    state: Mutex<ClientState>,                    // 连接状态
    transport_recipe: TransportRecipe,            // 传输配置（用于重连）
    initialize_context: Mutex<Option<InitializeContext>>,  // 初始化上下文（用于重连）
    session_recovery_lock: Mutex<()>,             // 恢复锁（防止并发）
    request_headers: Option<Arc<StdMutex<Option<HeaderMap>>>>,  // 请求头
}

enum ClientState {
    Connecting { transport: Option<PendingTransport> },
    Ready {
        _process_group_guard: Option<ProcessGroupGuard>,
        service: Arc<RunningService<RoleClient, LoggingClientHandler>>,
        oauth: Option<OAuthPersistor>,
    },
}

enum TransportRecipe {
    Stdio { program, args, env, env_vars, cwd },
    StreamableHttp { server_name, url, bearer_token, http_headers, env_http_headers, store_mode },
}
```

#### 3.2.2 Streamable HTTP 错误处理

```rust
#[derive(Debug, thiserror::Error)]
enum StreamableHttpResponseClientError {
    #[error("streamable HTTP session expired with 404 Not Found")]
    SessionExpired404,
    #[error(transparent)]
    Reqwest(#[from] reqwest::Error),
}

// 判断是否需要恢复
fn is_session_expired_404(error: &ClientOperationError) -> bool {
    matches!(error, 
        ClientOperationError::Service(
            rmcp::service::ServiceError::TransportSend(error)
        ) if error.downcast_ref::<StreamableHttpError<...>>()
            .is_some_and(|e| matches!(e, StreamableHttpError::Client(SessionExpired404)))
    )
}
```

### 3.3 协议与传输层

#### 3.3.1 MCP 协议版本

测试使用 MCP 协议版本 `ProtocolVersion::V_2025_06_18`，支持以下能力：

```rust
ClientCapabilities {
    experimental: None,
    extensions: None,
    roots: None,
    sampling: None,
    elicitation: Some(ElicitationCapability {
        form: Some(FormElicitationCapability { schema_validation: None }),
        url: None,
    }),
    tasks: None,
}
```

#### 3.3.2 传输方式

| 传输方式 | 测试文件 | 用途 |
|----------|----------|------|
| STDIO | `resources.rs`, `process_group_cleanup.rs` | 本地进程通信 |
| Streamable HTTP | `streamable_http_recovery.rs` | 网络服务通信 |

**Streamable HTTP 关键头**：
- `Mcp-Session-Id`: 会话标识
- `Last-Event-Id`: SSE 事件恢复
- `Accept: text/event-stream, application/json`

---

## 4. 关键代码路径与文件引用

### 4.1 测试文件内部引用

```
process_group_cleanup.rs
├── 依赖: codex_rmcp_client::RmcpClient
├── 依赖: std::process::Command (kill -0 检查进程存在)
└── 辅助函数: process_exists(), wait_for_pid_file(), wait_for_process_exit()

resources.rs
├── 依赖: codex_rmcp_client::{ElicitationAction, ElicitationResponse, RmcpClient}
├── 依赖: codex_utils_cargo_bin::CargoBinError (加载测试服务器二进制)
├── 依赖: rmcp::model::* (MCP 协议类型)
└── 辅助函数: stdio_server_bin(), init_params()

streamable_http_recovery.rs
├── 依赖: codex_rmcp_client::{ElicitationAction, ElicitationResponse, OAuthCredentialsStoreMode, RmcpClient}
├── 依赖: codex_utils_cargo_bin::CargoBinError
├── 依赖: rmcp::model::*
├── 依赖: tokio::net::TcpListener (绑定随机端口)
├── 依赖: reqwest (注入故障)
└── 辅助函数: streamable_http_server_bin(), init_params(), create_client(), 
    call_echo_tool(), arm_session_post_failure(), spawn_streamable_http_server(),
    wait_for_streamable_http_server()
```

### 4.2 被测试代码路径

```
rmcp_client.rs
├── RmcpClient::new_stdio_client() [514-543]
├── RmcpClient::new_streamable_http_client() [545-575]
├── RmcpClient::initialize() [577-631]
├── RmcpClient::list_resources() [694-708]
├── RmcpClient::list_resource_templates() [710-724]
├── RmcpClient::read_resource() [726-740]
├── RmcpClient::call_tool() [742-782]
├── RmcpClient::run_service_operation() [1075-1099]  # 恢复逻辑入口
├── RmcpClient::is_session_expired_404() [1123-1141]
├── RmcpClient::reinitialize_after_session_expiry() [1143-1194]
├── ProcessGroupGuard [365-422]  # Unix 进程组管理
└── StreamableHttpResponseClient [112-338]  # HTTP 客户端实现

test_stdio_server.rs
├── TestToolServer [29-447]  # MCP Server 实现
├── memo_resource() [166-178]
├── memo_template() [180-192]
└── main() [457-470]

test_streamable_http_server.rs
├── TestToolServer [51-266]
├── SessionFailureState [127-136]  # 故障注入状态
├── arm_session_post_failure() [372-387]  # 故障注入端点
├── fail_session_post_when_armed() [389-419]  # 故障注入中间件
└── main() [276-351]
```

### 4.3 依赖 crate

```
codex-rmcp-client
├── rmcp (MCP Rust SDK)
│   ├── model::* (协议类型)
│   ├── transport::StreamableHttpClientTransport
│   ├── transport::child_process::TokioChildProcess
│   └── service::{RunningService, RoleClient}
├── codex_client (build_reqwest_client_with_custom_ca)
├── codex_utils_pty::process_group (terminate_process_group, kill_process_group)
├── codex_utils_cargo_bin (cargo_bin 测试二进制定位)
└── tokio::process (异步进程管理)
```

---

## 5. 依赖与外部交互

### 5.1 测试辅助二进制

测试依赖两个编译为 bin 的测试服务器：

| 二进制 | 源码位置 | 用途 |
|--------|----------|------|
| `test_stdio_server` | `src/bin/test_stdio_server.rs` | STDIO 传输测试 |
| `test_streamable_http_server` | `src/bin/test_streamable_http_server.rs` | HTTP 传输测试 |

**Cargo.toml 配置**：
```toml
[[bin]]
name = "test_stdio_server"
path = "src/bin/test_stdio_server.rs"

[[bin]]
name = "test_streamable_http_server"
path = "src/bin/test_streamable_http_server.rs"
```

### 5.2 外部系统交互

#### 5.2.1 进程管理（Unix）

```rust
// 使用 kill -0 检查进程是否存在
std::process::Command::new("kill")
    .arg("-0")
    .arg(pid.to_string())
    .stderr(std::process::Stdio::null())
    .status()
```

#### 5.2.2 网络（Streamable HTTP 测试）

```rust
// 绑定随机端口
let listener = TcpListener::bind("127.0.0.1:0")?;
let port = listener.local_addr()?.port();

// 等待服务器就绪（TCP 连接测试）
tokio::time::timeout(remaining, TcpStream::connect(address)).await

// 故障注入（HTTP POST）
reqwest::Client::new()
    .post(format!("{base_url}{SESSION_POST_FAILURE_CONTROL_PATH}"))
    .json(&json!({"status": status, "remaining": remaining}))
    .send()
```

### 5.3 环境变量

| 变量 | 用途 | 设置位置 |
|------|------|----------|
| `CHILD_PID_FILE` | 孙子进程 PID 文件路径 | `process_group_cleanup.rs` 测试 |
| `MCP_STREAMABLE_HTTP_BIND_ADDR` | HTTP 服务器绑定地址 | `test_streamable_http_server.rs` |
| `MCP_EXPECT_BEARER` | 期望的 Bearer Token | `test_streamable_http_server.rs` |
| `CODEX_HOME` | 凭证文件存储路径（测试时临时设置） | `oauth.rs` 单元测试 |

---

## 6. 风险、边界与改进建议

### 6.1 当前风险点

#### 6.1.1 平台限制

```rust
// process_group_cleanup.rs 仅 Unix
#![cfg(unix)]
```
- **风险**：Windows 平台无进程组清理测试覆盖
- **影响**：Windows 上子进程可能成为僵尸进程

#### 6.1.2 竞态条件

```rust
// streamable_http_recovery.rs 中的测试
// 故障注入和请求之间可能存在竞态
arm_session_post_failure(&base_url, 404, 1).await?;
let recovered = call_echo_tool(&client, "recovered").await?;  // 依赖故障已注入
```

#### 6.1.3 超时硬编码

```rust
// 多处硬编码超时
const SESSION_POST_FAILURE_CONTROL_PATH: &str = "/test/control/session-post-failure";
Duration::from_secs(5)  // 初始化超时
Duration::from_millis(100)  // 轮询间隔
```

### 6.2 边界情况

#### 6.2.1 会话恢复边界

| 场景 | 当前行为 | 潜在问题 |
|------|----------|----------|
| 连续 404 | 只恢复一次，第二次报错 | 短暂网络抖动可能导致失败 |
| 恢复过程中服务端再次 404 | 报错 | 无指数退避 |
| 401 未授权 | 不触发恢复 | 符合预期（token 问题需人工处理）|
| 500 服务器错误 | 不触发恢复 | 符合预期（服务端问题）|

#### 6.2.2 进程清理边界

```rust
// 2 秒优雅期后强制 kill
const PROCESS_GROUP_TERM_GRACE_PERIOD: Duration = Duration::from_secs(2);
```
- 如果子进程正在执行关键操作（如写文件），可能被强制终止
- 无优雅关闭协议（如 MCP shutdown 请求）

### 6.3 改进建议

#### 6.3.1 测试覆盖

1. **增加 Windows 进程清理测试**
   ```rust
   #[cfg(windows)]
   mod windows_process_cleanup {
       // 使用 JobObject 实现类似进程组功能
   }
   ```

2. **增加并发恢复测试**
   ```rust
   async fn concurrent_session_recovery() {
       // 多个并发请求在 404 后应只触发一次恢复
   }
   ```

3. **增加 OAuth 刷新测试**
   - 当前测试使用固定 bearer token
   - 建议增加 token 过期自动刷新场景

#### 6.3.2 代码改进

1. **可配置恢复策略**
   ```rust
   pub struct RecoveryConfig {
       max_retries: u32,
       backoff_strategy: BackoffStrategy,
       retryable_statuses: Vec<u16>,
   }
   ```

2. **优雅关闭协议**
   ```rust
   impl Drop for RmcpClient {
       fn drop(&mut self) {
           // 先发送 MCP shutdown 请求
           // 超时后再使用进程组信号
       }
   }
   ```

3. **测试辅助工具提取**
   - `wait_for_pid_file`, `wait_for_process_exit` 等辅助函数可提取为通用测试工具
   - 建议创建 `codex_test_utils` crate

#### 6.3.3 监控与可观测性

1. **恢复事件指标**
   ```rust
   // 在 reinitialize_after_session_expiry 中增加
   tracing::info!("mcp_session_recovered", server_name = ..., duration_ms = ...);
   ```

2. **进程清理指标**
   ```rust
   // 在 ProcessGroupGuard::drop 中增加
   tracing::info!("mcp_process_group_terminated", pid = ..., grace_period_used = ...);
   ```

### 6.4 文档建议

1. **增加架构图**：RmcpClient 状态机图（Connecting -> Ready -> Recovery）
2. **增加故障处理矩阵**：什么错误会触发恢复、什么不会
3. **增加测试运行指南**：如何单独运行某类测试（如仅 HTTP 测试）

---

## 附录：测试运行命令

```bash
# 运行所有测试
cargo test -p codex-rmcp-client

# 仅运行进程组清理测试（Unix）
cargo test -p codex-rmcp-client --test process_group_cleanup

# 仅运行 Resource 测试
cargo test -p codex-rmcp-client --test resources

# 仅运行 HTTP 恢复测试
cargo test -p codex-rmcp-client --test streamable_http_recovery

# 运行特定测试用例
cargo test -p codex-rmcp-client streamable_http_404_session_expiry_recovers_and_retries_once
```

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/rmcp-client/tests 目录及其依赖代码*
