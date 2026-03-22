# thread_start.rs 研究文档

## 场景与职责

`thread_start.rs` 是 Codex App Server v2 API 的集成测试文件，专门测试**线程启动（Thread Start）**功能。该功能是 App Server 的核心入口，负责创建新的对话线程，初始化配置，建立与模型服务的连接，并准备会话环境。这是用户与 Codex 交互的第一步，其稳定性直接影响用户体验。

### 核心测试场景

1. **基础线程创建** - 验证可以创建新线程并接收 thread/started 通知
2. **项目配置加载** - 测试从工作目录的 `.codex/config.toml` 加载配置
3. **服务层级配置** - 验证 Flex 服务层级的设置
4. **指标服务名称** - 测试自定义服务名称的传递
5. **临时线程** - 验证 ephemeral（不持久化）线程的创建
6. **MCP 服务器初始化失败** - 测试必需 MCP 服务器失败时的错误处理
7. **云配置加载错误** - 验证云端配置加载失败时的认证错误传播

## 功能点目的

### Thread Start 的核心价值

- **会话初始化**: 为用户创建独立的对话上下文
- **配置聚合**: 合并用户配置、项目配置、命令行参数
- **资源准备**: 初始化 MCP 服务器、加载模型配置
- **持久化决策**: 决定会话是否持久化到磁盘

### 关键测试功能点

| 测试函数 | 目的 |
|---------|------|
| `thread_start_creates_thread_and_emits_started` | 验证基础线程创建和通知 |
| `thread_start_respects_project_config_from_cwd` | 验证项目级配置加载 |
| `thread_start_accepts_flex_service_tier` | 验证 Flex 服务层级 |
| `thread_start_accepts_metrics_service_name` | 验证服务名称配置 |
| `thread_start_ephemeral_remains_pathless` | 验证临时线程无路径 |
| `thread_start_fails_when_required_mcp_server_fails_to_initialize` | 验证 MCP 初始化失败处理 |
| `thread_start_surfaces_cloud_requirements_load_errors` | 验证云配置错误处理 |

## 具体技术实现

### 关键数据结构

#### ThreadStartParams
```rust
pub struct ThreadStartParams {
    pub model: Option<String>,                    // 覆盖模型
    pub cwd: Option<String>,                      // 工作目录
    pub ephemeral: Option<bool>,                  // 是否临时（不持久化）
    pub service_tier: Option<Option<ServiceTier>>, // 服务层级
    pub service_name: Option<String>,             // 指标服务名称
    pub persist_extended_history: Option<bool>,   // 是否持久化扩展历史
    // ... 其他参数
}
```

#### ThreadStartResponse
```rust
pub struct ThreadStartResponse {
    pub thread: Thread,              // 创建的线程信息
    pub model: String,               // 实际使用的模型
    pub model_provider: String,      // 模型提供者
    pub reasoning_effort: Option<ReasoningEffort>, // 推理努力程度
    pub service_tier: Option<ServiceTier>, // 服务层级
    // ... 其他配置
}
```

#### Thread 结构
```rust
pub struct Thread {
    pub id: String,                  // 线程唯一标识
    pub name: Option<String>,        // 线程名称（可选）
    pub preview: String,             // 内容预览
    pub path: Option<PathBuf>,       // rollout 文件路径（临时线程为 None）
    pub ephemeral: bool,             // 是否临时线程
    pub status: ThreadStatus,        // 线程状态
    pub created_at: i64,             // 创建时间戳
    pub updated_at: i64,             // 更新时间戳
    pub cwd: PathBuf,                // 工作目录
    pub model_provider: String,      // 模型提供者
    pub cli_version: String,         // CLI 版本
    pub source: SessionSource,       // 会话来源
    pub git_info: Option<GitInfo>,   // Git 信息
    pub turns: Vec<Turn>,            // 对话轮次
}
```

### 关键流程

#### 1. 基础线程创建流程

```
Client -> thread/start (params)
    |
    v
Server 验证初始化状态
    |
    v
加载配置（用户配置 + 项目配置 + 参数覆盖）
    |
    v
初始化 MCP 服务器
    |
    v
创建 Thread 对象
    |
    v
发送 thread/started 通知
    |
    v
返回 ThreadStartResponse
```

#### 2. 配置加载流程

```
thread/start (cwd=/project)
    |
    v
检查 /project/.codex/config.toml
    |
    v
合并配置（优先级：参数 > 项目 > 用户）
    |
    v
应用配置到 ThreadConfig
```

#### 3. 错误处理流程（MCP 失败）

```
thread/start
    |
    v
初始化 MCP 服务器
    |
    v
必需服务器 required_broken 失败
    |
    v
返回 JSON-RPC Error
    {
        code: -32600,
        message: "required MCP servers failed to initialize: required_broken",
        data: None
    }
```

### 核心代码路径

#### 配置加载
- **文件**: `codex-rs/app-server/src/config_api.rs`
- **函数**: `ConfigApi::read()`
- **职责**: 合并多层配置

#### MCP 初始化
- **文件**: `codex-rs/app-server/src/codex_message_processor.rs`
- **函数**: `initialize_mcp_servers()`
- **职责**: 启动配置的 MCP 服务器

#### 线程创建
- **文件**: `codex-rs/core/src/thread_manager.rs`（推测）
- **函数**: `ThreadManager::create_thread()`
- **职责**: 创建 CodexThread 实例

## 关键代码路径与文件引用

### 主要测试文件
- `codex-rs/app-server/tests/suite/v2/thread_start.rs` - 本文件，包含 7 个测试用例

### 被测实现文件
- `codex-rs/app-server/src/codex_message_processor.rs` - 处理 thread/start 请求
- `codex-rs/app-server/src/config_api.rs` - 配置加载
- `codex-rs/app-server/src/message_processor.rs` - 消息处理

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `ThreadStartParams`
  - `ThreadStartResponse`
  - `Thread`
  - `ThreadStatus`
  - `SessionSource`
  - `ServiceTier`

### 测试基础设施
- `codex-rs/app-server/tests/common/mcp_process.rs` - MCP 进程管理
- `codex-rs/app-server/tests/common/mock_model_server.rs` - Mock 模型服务器

## 依赖与外部交互

### 测试详解：基础线程创建

```rust
#[tokio::test]
async fn thread_start_creates_thread_and_emits_started() -> Result<()> {
    // 1. 创建 Mock 模型服务器
    let server = create_mock_responses_server_repeating_assistant("Done").await;
    
    // 2. 创建临时 CODEX_HOME
    let codex_home = TempDir::new()?;
    create_config_toml(codex_home.path(), &server.uri())?;
    
    // 3. 初始化 MCP 进程
    let mut mcp = McpProcess::new(codex_home.path()).await?;
    timeout(DEFAULT_READ_TIMEOUT, mcp.initialize()).await??;
    
    // 4. 发送 thread/start 请求
    let req_id = mcp.send_thread_start_request(ThreadStartParams {
        model: Some("gpt-5.1".to_string()),
        ..Default::default()
    }).await?;
    
    // 5. 验证响应
    let resp: JSONRPCResponse = timeout(
        DEFAULT_READ_TIMEOUT,
        mcp.read_stream_until_response_message(RequestId::Integer(req_id)),
    ).await??;
    
    let ThreadStartResponse { thread, model_provider, .. } = to_response::<ThreadStartResponse>(resp)?;
    
    // 6. 验证线程属性
    assert!(!thread.id.is_empty());
    assert!(thread.preview.is_empty());  // 新线程预览为空
    assert_eq!(model_provider, "mock_provider");
    assert!(thread.created_at > 0);
    assert!(!thread.ephemeral);  // 默认非临时
    assert_eq!(thread.status, ThreadStatus::Idle);
    assert!(thread.path.expect("thread path").is_absolute());
    assert!(!thread.path.as_ref().unwrap().exists());  // 新线程 rollout 尚未物化
    
    // 7. 验证 thread/started 通知
    let started: ThreadStartedNotification = loop {
        let message = timeout(remaining, mcp.read_next_message()).await??;
        if let JSONRPCMessage::Notification(notif) = message {
            if notif.method == "thread/started" {
                break serde_json::from_value(notif.params.expect("params"))?;
            }
        }
    };
    assert_eq!(started.thread, thread);
}
```

### 测试详解：项目配置加载

```rust
#[tokio::test]
async fn thread_start_respects_project_config_from_cwd() -> Result<()> {
    // 1. 创建 Mock 服务器
    let server = create_mock_responses_server_repeating_assistant("Done").await;
    let codex_home = TempDir::new()?;
    create_config_toml(codex_home.path(), &server.uri())?;
    
    // 2. 创建项目配置
    let workspace = TempDir::new()?;
    let project_config_dir = workspace.path().join(".codex");
    std::fs::create_dir_all(&project_config_dir)?;
    std::fs::write(
        project_config_dir.join("config.toml"),
        r#"model_reasoning_effort = "high""#,
    )?;
    
    // 3. 设置项目信任级别
    set_project_trust_level(codex_home.path(), workspace.path(), TrustLevel::Trusted)?;
    
    // 4. 启动线程，指定 cwd
    let req_id = mcp.send_thread_start_request(ThreadStartParams {
        cwd: Some(workspace.path().to_string_lossy().into_owned()),
        ..Default::default()
    }).await?;
    
    // 5. 验证项目配置被加载
    let ThreadStartResponse { reasoning_effort, .. } = to_response::<ThreadStartResponse>(resp)?;
    assert_eq!(reasoning_effort, Some(ReasoningEffort::High));
}
```

### 测试详解：临时线程

```rust
#[tokio::test]
async fn thread_start_ephemeral_remains_pathless() -> Result<()> {
    let server = create_mock_responses_server_repeating_assistant("Done").await;
    let codex_home = TempDir::new()?;
    create_config_toml(codex_home.path(), &server.uri())?;
    
    let mut mcp = McpProcess::new(codex_home.path()).await?;
    timeout(DEFAULT_READ_TIMEOUT, mcp.initialize()).await??;
    
    // 创建临时线程
    let req_id = mcp.send_thread_start_request(ThreadStartParams {
        model: Some("gpt-5.1".to_string()),
        ephemeral: Some(true),  // 关键参数
        ..Default::default()
    }).await?;
    
    let ThreadStartResponse { thread, .. } = to_response::<ThreadStartResponse>(resp)?;
    
    // 验证临时线程属性
    assert!(thread.ephemeral);
    assert_eq!(thread.path, None);  // 临时线程无路径
    
    // 验证序列化
    let thread_json = resp_result.get("thread").and_then(Value::as_object).unwrap();
    assert_eq!(
        thread_json.get("ephemeral").and_then(Value::as_bool),
        Some(true)
    );
}
```

### 测试详解：云配置错误

```rust
#[tokio::test]
async fn thread_start_surfaces_cloud_requirements_load_errors() -> Result<()> {
    // 1. 创建返回 401 的 Mock 服务器
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/backend-api/wham/config/requirements"))
        .respond_with(ResponseTemplate::new(401).set_body_string("<html>nope</html>"))
        .mount(&server).await;
    
    // 2. 设置过期的认证
    write_chatgpt_auth(
        codex_home.path(),
        ChatGptAuthFixture::new("chatgpt-token")
            .refresh_token("stale-refresh-token")
            .plan_type("business")
            .chatgpt_user_id("user-123")
            .chatgpt_account_id("account-123")
            .account_id("account-123"),
        AuthCredentialsStoreMode::File,
    )?;
    
    // 3. 启动线程，预期失败
    let req_id = mcp.send_thread_start_request(ThreadStartParams::default()).await?;
    
    // 4. 验证错误响应
    let err: JSONRPCError = timeout(
        DEFAULT_READ_TIMEOUT,
        mcp.read_stream_until_error_message(RequestId::Integer(req_id)),
    ).await??;
    
    assert!(err.error.message.contains("failed to load configuration"));
    assert_eq!(err.error.data, Some(json!({
        "reason": "cloudRequirements",
        "errorCode": "Auth",
        "action": "relogin",
        "statusCode": 401,
        "detail": "Your access token could not be refreshed...",
    })));
}
```

### 依赖关系

```
thread_start.rs
    |
    +-> app_test_support
    |       +-> McpProcess
    |       +-> create_mock_responses_server_repeating_assistant
    |       +-> ChatGptAuthFixture
    |       +-> write_chatgpt_auth
    |
    +-> codex_app_server_protocol
    |       +-> ThreadStartParams/Response
    |       +-> Thread/ThreadStatus
    |       +-> ThreadStartedNotification
    |       +-> ServiceTier
    |       +-> JSONRPCResponse/JSONRPCError
    |
    +-> codex_core
    |       +-> config::set_project_trust_level
    |       +-> auth::AuthCredentialsStoreMode
    |
    +-> codex_protocol
    |       +-> config_types::TrustLevel
    |       +-> config_types::ReasoningEffort
    |       +-> openai_models::ServiceTier
    |
    +-> wiremock
            +-> MockServer, Mock, ResponseTemplate
```

## 风险、边界与改进建议

### 当前测试覆盖的局限

1. **配置覆盖不完整**
   - 仅测试了 `model_reasoning_effort`
   - 其他配置项（approval_policy, sandbox_mode 等）未测试

2. **MCP 测试有限**
   - 仅测试了必需 MCP 失败
   - 未测试可选 MCP 失败、MCP 超时等

3. **并发测试缺失**
   - 未测试并发创建线程
   - 未测试配置竞争条件

4. **边界值测试不足**
   - 空 cwd
   - 无效模型名称
   - 超长 service_name

### 改进建议

1. **增加配置覆盖测试**
   ```rust
   #[tokio::test]
   async fn thread_start_applies_all_config_overrides() -> Result<()> {
       // 测试各种配置项的覆盖
       // - approval_policy
       // - sandbox_mode
       // - model_context_window
       // - etc.
   }
   ```

2. **增加错误场景测试**
   ```rust
   #[tokio::test]
   async fn thread_start_rejects_invalid_model() -> Result<()> {
       // 测试无效模型名称的处理
   }
   
   #[tokio::test]
   async fn thread_start_handles_untrusted_project() -> Result<()> {
       // 测试未信任项目的配置加载限制
   }
   ```

3. **增加并发测试**
   ```rust
   #[tokio::test]
   async fn thread_start_concurrent() -> Result<()> {
       // 测试并发创建多个线程
       // 验证线程 ID 唯一性
       // 验证资源正确分配
   }
   ```

4. **验证通知顺序**
   ```rust
   #[tokio::test]
   async fn thread_start_notification_order() -> Result<()> {
       // 验证 thread/started 在响应之后发送
       // 验证 thread/status/changed 的正确性
   }
   ```

### 实现层面的潜在风险

1. **配置安全**
   - 项目配置可能包含恶意设置
   - 需要信任级别检查（已实现但未充分测试）

2. **资源泄漏**
   - MCP 服务器进程可能僵死
   - 临时线程的资源清理

3. **竞态条件**
   - 配置加载和线程创建的竞态
   - 多个线程同时写入配置

4. **性能问题**
   - MCP 初始化可能很慢
   - 需要超时机制（已实现）

### 测试代码改进

1. **减少重复代码**
   - `create_config_toml` 在多个文件中重复
   - 建议提取到 `app_test_support`

2. **增强验证**
   - 当前主要验证基本属性
   - 建议增加对 git_info、cli_version 的验证

3. **使用参数化测试**
   - 多个测试使用相似的流程
   - 可以使用测试宏或辅助函数简化

### 与 Thread Resume 的关系

| 特性 | Thread Start | Thread Resume |
|-----|--------------|---------------|
| 目的 | 创建新线程 | 恢复已有线程 |
| 配置来源 | 配置层合并 | 持久化配置 + 覆盖 |
| Rollout 文件 | 延迟创建 | 必须存在 |
| MCP 初始化 | 必需 | 必需 |
| 通知 | thread/started | thread/resumed |

两个功能共享 MCP 初始化和配置加载逻辑，应确保一致性。
