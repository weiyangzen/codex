# thread_fork.rs 研究文档

## 场景与职责

本文件是 Codex App Server v2 API 的集成测试套件的一部分，专门测试**线程分叉功能** (`thread/fork`)。分叉允许用户基于现有线程创建一个新的独立线程，复制历史对话但允许独立的后续发展。

测试场景覆盖：
1. **基本分叉流程** - 创建分叉线程并验证历史复制
2. **未实体化线程拒绝** - 验证只有已实体化的线程才能分叉
3. **云配置加载错误** - 验证分叉时云配置加载失败的错误处理
4. **临时分叉模式** - 验证临时（ephemeral）分叉的特殊行为

## 功能点目的

### 1. 线程分叉工作流
分叉是创建线程变体的重要机制：
- **复制历史**: 新线程包含原线程的所有历史回合
- **独立发展**: 分叉后的线程可以独立进行新的对话
- **保留上下文**: 基于已有上下文开始新的探索

### 2. 分叉模式
| 模式 | 特点 | 使用场景 |
|-----|------|---------|
| **普通分叉** | 创建持久化线程，可被列出和恢复 | 长期分支探索 |
| **临时分叉 (Ephemeral)** | 不持久化，无路径，不出现在列表中 | 临时实验、预览 |

### 3. 分叉数据结构
- **线程 ID**: 新生成的唯一 ID，与原线程不同
- **历史复制**: 包含原线程的所有回合和消息项
- **预览继承**: 继承原线程的预览文本
- **元数据继承**: 继承模型提供者、CWD 等配置

### 4. 云配置依赖
分叉需要加载云配置（cloud requirements）：
- 验证用户有权限创建新线程
- 加载组织的策略限制
- 失败时返回详细的错误信息

## 具体技术实现

### 关键流程

```
测试用例: thread_fork_creates_new_thread_and_emits_started
1. 创建临时 CODEX_HOME
2. 创建 mock 服务器
3. 创建假 rollout 文件（模拟已有对话）
4. 初始化 MCP 连接
5. 发送 thread/fork 请求
6. 验证响应
   - thread.id 与原线程不同
   - thread.preview 继承原值
   - thread.turns 包含历史
   - thread.name 为 null
7. 验证收到 thread/started 通知
8. 验证原 rollout 文件未被修改

测试用例: thread_fork_rejects_unmaterialized_thread
1-4. 同上
5. 启动新线程（未执行回合）
6. 尝试分叉，验证返回错误 "no rollout found for thread id"

测试用例: thread_fork_surfaces_cloud_requirements_load_errors
1. 创建 mock 云配置服务器（返回 401 错误）
2. 配置 ChatGPT 认证
3. 创建假 rollout
4. 初始化 MCP（带错误配置）
5. 发送 thread/fork 请求
6. 验证返回详细的错误信息
   - message: "failed to load configuration"
   - data: { reason: "cloudRequirements", errorCode: "Auth", action: "relogin", ... }

测试用例: thread_fork_ephemeral_remains_pathless_and_omits_listing
1-4. 同基本分叉测试
5. 发送 thread/fork 请求，设置 ephemeral: true
6. 验证响应
   - thread.ephemeral: true
   - thread.path: None
   - thread 不出现在 thread/list 结果中
7. 验证可以在临时线程上执行回合
```

### 核心数据结构

```rust
// 分叉请求
ThreadForkParams {
    thread_id: String,
    #[experimental("thread/fork.path")]
    path: Option<PathBuf>,  // 可选指定 rollout 路径
    ephemeral: bool,        // 是否为临时分叉
    approval_policy: Option<AskForApproval>,  // 可选覆盖审批策略
}

// 分叉响应
ThreadForkResponse {
    thread: Thread,
}

// 线程结构
Thread {
    id: String,
    name: Option<String>,      // 分叉线程 name 为 null
    preview: String,
    path: Option<PathBuf>,     // 临时分叉为 None
    ephemeral: bool,           // 临时标记
    status: ThreadStatus,
    turns: Vec<Turn>,          // 复制的历史
    model_provider: String,
    cwd: PathBuf,
    source: SessionSource,     // 通常为 VsCode
}
```

### 假 Rollout 创建

```rust
let conversation_id = create_fake_rollout(
    codex_home.path(),
    "2025-01-05T12-00-00",      // 时间戳
    "2025-01-05T12:00:00Z",     // ISO 时间
    preview,                     // 预览文本
    Some("mock_provider"),       // 模型提供者
    None,                        // 额外配置
)?;

// 验证文件创建
let original_path = codex_home
    .path()
    .join("sessions")
    .join("2025")
    .join("01")
    .join("05")
    .join(format!("rollout-2025-01-05T12-00-00-{conversation_id}.jsonl"));
assert!(original_path.exists());
```

### 云配置错误处理

```rust
// Mock 云配置服务器返回 401
Mock::given(method("GET"))
    .and(path("/backend-api/wham/config/requirements"))
    .respond_with(
        ResponseTemplate::new(401)
            .insert_header("content-type", "text/html")
            .set_body_string("<html>nope</html>"),
    )
    .mount(&server)
    .await;

// 验证错误响应结构
assert_eq!(fork_err.error.code, /* 错误码 */);
assert!(fork_err.error.message.contains("failed to load configuration"));
assert_eq!(fork_err.error.data, Some(json!({
    "reason": "cloudRequirements",
    "errorCode": "Auth",
    "action": "relogin",
    "statusCode": 401,
    "detail": "Your access token could not be refreshed...",
})));
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/thread_fork.rs` - 本测试文件

### 测试支持库
- `codex-rs/app-server/tests/common/mcp_process.rs`
  - `send_thread_fork_request()` (行327)
  - `send_thread_list_request()` (行408)
  - `send_thread_start_request()` (行309)
  - `send_turn_start_request()` (行530)

- `codex-rs/app-server/tests/common/rollout.rs`
  - `create_fake_rollout()` - 创建测试用 rollout

- `codex-rs/app-server/tests/common/auth_fixtures.rs`
  - `ChatGptAuthFixture` - ChatGPT 认证配置
  - `write_chatgpt_auth()` - 写入认证

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`
  - `ThreadFork => "thread/fork"` (行225)
  - `ThreadStarted => "thread/started"` (通知)

- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ThreadForkParams` (行2642)
  - `ThreadForkResponse`
  - `Thread` (包含 ephemeral 字段)
  - `SessionSource` (VsCode, Cli, etc.)

### 核心实现
- `codex-rs/core/src/fork.rs` - 分叉核心逻辑
- `codex-rs/core/src/storage/thread_storage.rs` - 线程存储
- `codex-rs/app-server/src/thread_manager.rs` - 线程管理

## 依赖与外部交互

### 直接依赖
| 依赖 | 用途 |
|-----|------|
| `tempfile::TempDir` | 隔离测试环境 |
| `wiremock` | 模拟云配置服务器 |
| `tokio::time::timeout` | 异步超时控制 |
| `serde_json::json` | JSON 构造 |
| `pretty_assertions::assert_eq` | 断言增强 |

### 环境变量
```rust
// 用于覆盖刷新令牌 URL
const REFRESH_TOKEN_URL_OVERRIDE_ENV_VAR: &str = "CODEX_REFRESH_TOKEN_URL_OVERRIDE";
```

### 认证配置
```rust
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
```

## 风险、边界与改进建议

### 当前风险

1. **云配置依赖**
   - 云配置加载错误测试依赖外部 Mock 服务器
   - 真实云配置变更可能影响错误格式
   - 建议: 定期同步错误格式文档

2. **文件系统依赖**
   - 分叉操作涉及文件复制
   - 大线程文件可能影响性能
   - 建议: 添加大文件分叉性能测试

3. **并发分叉**
   - 未测试多客户端同时分叉同一线程
   - 建议: 添加并发安全测试

### 边界情况

1. **分叉链**
   - 未测试分叉的分叉（多级分叉）
   - 建议: 添加分叉链测试

2. **分叉后原线程删除**
   - 未测试原线程删除对分叉的影响
   - 建议: 添加依赖测试

3. **临时分叉的持久化**
   - 临时分叉是否可以转为持久化
   - 建议: 添加转换测试

4. **分叉配置覆盖**
   - `approval_policy` 覆盖的完整测试
   - 建议: 扩展配置覆盖测试

### 改进建议

1. **扩展测试覆盖**
   ```rust
   // 建议添加:
   - async fn thread_fork_chain()  // 多级分叉
   - async fn thread_fork_after_original_deleted()  // 原线程删除后
   - async fn thread_fork_with_all_config_overrides()  // 完整配置覆盖
   - async fn thread_fork_concurrent_same_source()  // 并发分叉
   - async fn thread_fork_large_thread()  // 大线程分叉
   - async fn thread_ephemeral_to_persistent()  // 临时转持久
   ```

2. **性能测试**
   - 大历史线程的分叉时间
   - 分叉操作的内存使用

3. **安全测试**
   - 验证分叉权限检查
   - 测试跨用户分叉限制

4. **UI 集成测试**
   - 验证分叉在 UI 中的展示
   - 测试分叉历史可视化

### 相关测试文件
- `codex-rs/app-server/tests/suite/v2/thread_start.rs` - 线程启动
- `codex-rs/app-server/tests/suite/v2/thread_list.rs` - 线程列表
- `codex-rs/app-server/tests/suite/v2/thread_resume.rs` - 线程恢复
