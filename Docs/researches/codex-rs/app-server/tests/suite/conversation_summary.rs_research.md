# conversation_summary.rs 研究文档

## 场景与职责

`conversation_summary.rs` 是 Codex App Server 的集成测试模块，专注于验证**会话摘要查询**功能的端到端行为。该测试文件位于 `codex-rs/app-server/tests/suite/conversation_summary.rs`，通过 MCP 进程与 App Server 交互，测试通过 Thread ID 或 Rollout 路径获取会话摘要的能力。

### 核心职责
1. **会话摘要查询测试**: 验证 `getConversationSummary` RPC 方法的两种查询方式
2. **Rollout 文件解析测试**: 验证从 rollout JSONL 文件解析会话元数据
3. **路径解析测试**: 验证相对路径和绝对路径的解析逻辑
4. **会话元数据验证**: 验证返回的摘要包含正确的会话信息

---

## 功能点目的

### 1. 测试数据准备

| 常量 | 值 | 说明 |
|------|-----|------|
| `FILENAME_TS` | `"2025-01-02T12-00-00"` | 文件名时间戳格式 |
| `META_RFC3339` | `"2025-01-02T12:00:00Z"` | JSON 中的 RFC3339 时间戳 |
| `PREVIEW` | `"Summarize this conversation"` | 用户消息预览文本 |
| `MODEL_PROVIDER` | `"openai"` | 模型提供商名称 |

### 2. 测试用例

| 测试函数 | 测试目的 |
|----------|----------|
| `get_conversation_summary_by_thread_id_reads_rollout` | 通过 Thread ID 查询会话摘要 |
| `get_conversation_summary_by_relative_rollout_path_resolves_from_codex_home` | 通过相对 rollout 路径查询摘要 |

---

## 具体技术实现

### 关键流程

#### 1. 创建测试 Rollout 文件

```rust
let conversation_id = create_fake_rollout(
    codex_home.path(),    // CODEX_HOME 目录
    FILENAME_TS,          // "2025-01-02T12-00-00"
    META_RFC3339,         // "2025-01-02T12:00:00Z"
    PREVIEW,              // "Summarize this conversation"
    Some(MODEL_PROVIDER), // Some("openai")
    None,                 // git_info
)?;
```

生成的 rollout 文件路径：
```
{CODEX_HOME}/sessions/2025/01/02/rollout-2025-01-02T12-00-00-{uuid}.jsonl
```

#### 2. 构建期望的摘要对象

```rust
fn expected_summary(conversation_id: ThreadId, path: PathBuf) -> ConversationSummary {
    ConversationSummary {
        conversation_id,
        path,
        preview: PREVIEW.to_string(),
        timestamp: Some(META_RFC3339.to_string()),
        updated_at: Some(META_RFC3339.to_string()),
        model_provider: MODEL_PROVIDER.to_string(),
        cwd: PathBuf::from("/"),
        cli_version: "0.0.0".to_string(),
        source: SessionSource::Cli,
        git_info: None,
    }
}
```

#### 3. 通过 Thread ID 查询

```rust
let request_id = mcp
    .send_get_conversation_summary_request(
        GetConversationSummaryParams::ThreadId {
            conversation_id: thread_id,
        }
    )
    .await?;

let response: JSONRPCResponse = timeout(
    DEFAULT_READ_TIMEOUT,
    mcp.read_stream_until_response_message(RequestId::Integer(request_id)),
).await??;

let received: GetConversationSummaryResponse = to_response(response)?;
assert_eq!(received.summary, expected);
```

#### 4. 通过相对路径查询

```rust
let rollout_path = rollout_path(codex_home.path(), FILENAME_TS, &conversation_id);
let relative_path = rollout_path.strip_prefix(codex_home.path())?.to_path_buf();

let request_id = mcp
    .send_get_conversation_summary_request(
        GetConversationSummaryParams::RolloutPath {
            rollout_path: relative_path,  // "sessions/2025/01/02/rollout-..."
        }
    )
    .await?;
```

### 数据结构

#### GetConversationSummaryParams (请求参数)
```rust
#[serde(untagged)]
pub enum GetConversationSummaryParams {
    RolloutPath {
        #[serde(rename = "rolloutPath")]
        rollout_path: PathBuf,
    },
    ThreadId {
        #[serde(rename = "conversationId")]
        conversation_id: ThreadId,
    },
}
```

使用 `#[serde(untagged)]` 实现自动反序列化，根据字段名自动匹配变体。

#### GetConversationSummaryResponse (响应结构)
```rust
pub struct GetConversationSummaryResponse {
    pub summary: ConversationSummary,
}
```

#### ConversationSummary (会话摘要)
```rust
pub struct ConversationSummary {
    pub conversation_id: ThreadId,
    pub path: PathBuf,              // rollout 文件的绝对路径
    pub preview: String,            // 用户消息预览
    pub timestamp: Option<String>,  // 创建时间
    pub updated_at: Option<String>, // 更新时间
    pub model_provider: String,     // 模型提供商
    pub cwd: PathBuf,               // 工作目录
    pub cli_version: String,        // CLI 版本
    pub source: SessionSource,      // 会话来源 (Cli/Api/SubAgent)
    pub git_info: Option<ConversationGitInfo>, // Git 信息
}
```

### Rollout 文件结构

```jsonl
// Line 1: session_meta
{"timestamp":"2025-01-02T12:00:00Z","type":"session_meta","payload":{"meta":{...},"git":null}}

// Line 2: response_item (user message)
{"timestamp":"2025-01-02T12:00:00Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Summarize this conversation"}]}}

// Line 3: event_msg
{"timestamp":"2025-01-02T12:00:00Z","type":"event_msg","payload":{"type":"user_message","message":"Summarize this conversation","kind":"plain"}}
```

---

## 关键代码路径与文件引用

### 测试文件
| 文件 | 路径 | 说明 |
|------|------|------|
| conversation_summary.rs | `codex-rs/app-server/tests/suite/conversation_summary.rs` | 本测试文件 |
| mod.rs | `codex-rs/app-server/tests/suite/mod.rs` | 测试套件模块声明 |
| all.rs | `codex-rs/app-server/tests/all.rs` | 集成测试入口 |

### 测试支持库
| 文件 | 路径 | 说明 |
|------|------|------|
| mcp_process.rs | `codex-rs/app-server/tests/common/mcp_process.rs` | MCP 进程管理 |
| lib.rs | `codex-rs/app-server/tests/common/lib.rs` | 测试公共库 |
| rollout.rs | `codex-rs/app-server/tests/common/rollout.rs` | Rollout 文件创建工具 |

### 协议定义
| 文件 | 路径 | 说明 |
|------|------|------|
| v1.rs | `codex-rs/app-server-protocol/src/protocol/v1.rs` | GetConversationSummaryParams/Response 定义 |
| lib.rs | `codex-rs/app-server-protocol/src/lib.rs` | 协议库导出 |

### Rollout 工具函数

#### rollout_path
```rust
pub fn rollout_path(codex_home: &Path, filename_ts: &str, thread_id: &str) -> PathBuf {
    let year = &filename_ts[0..4];
    let month = &filename_ts[5..7];
    let day = &filename_ts[8..10];
    codex_home
        .join("sessions")
        .join(year)
        .join(month)
        .join(day)
        .join(format!("rollout-{filename_ts}-{thread_id}.jsonl"))
}
```

#### create_fake_rollout
```rust
pub fn create_fake_rollout(
    codex_home: &Path,
    filename_ts: &str,      // 文件名时间戳
    meta_rfc3339: &str,     // JSON 时间戳
    preview: &str,          // 预览文本
    model_provider: Option<&str>,
    git_info: Option<GitInfo>,
) -> Result<String>        // 返回 conversation_id (UUID)
```

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `app_test_support` | 测试支持库（McpProcess, create_fake_rollout, rollout_path, to_response） |
| `codex_app_server_protocol` | 协议类型定义 |
| `codex_protocol::ThreadId` | Thread ID 类型 |
| `codex_protocol::protocol::SessionSource` | 会话来源枚举 |
| `pretty_assertions` | 测试断言美化 |
| `tempfile::TempDir` | 临时目录创建 |
| `tokio::time::timeout` | 异步超时处理 |

### 进程间交互

```
测试进程 (conversation_summary.rs)
    │
    ├─► 创建临时 CODEX_HOME 目录
    │   └─► 创建 rollout 文件: sessions/2025/01/02/rollout-{ts}-{id}.jsonl
    │
    ├─► 启动 codex-app-server 子进程
    │       CODEX_HOME={临时目录}
    │
    ├─► 发送 JSON-RPC 请求
    │       method: "getConversationSummary"
    │       params: { conversationId } 或 { rolloutPath }
    │
    └─◄ 读取 JSON-RPC 响应
            GetConversationSummaryResponse { summary: ConversationSummary }
```

### 文件系统交互

```
{TempDir} (CODEX_HOME)
└── sessions/
    └── 2025/
        └── 01/
            └── 02/
                └── rollout-2025-01-02T12-00-00-{uuid}.jsonl
```

---

## 风险、边界与改进建议

### 已知风险

1. **时间戳硬编码**: 使用固定时间戳 `2025-01-02`，可能在特定时区/时间出现问题
2. **路径分隔符**: 未显式测试 Windows 路径分隔符处理
3. **并发冲突**: 多个测试同时创建 rollout 文件可能产生冲突
4. **文件系统权限**: 未处理只读文件系统的边界情况

### 边界条件

| 边界场景 | 测试覆盖 | 建议 |
|----------|----------|------|
| Thread ID 不存在 | ❌ 未覆盖 | 添加错误处理测试 |
| Rollout 路径不存在 | ❌ 未覆盖 | 添加 404 测试 |
| Rollout 文件损坏 | ❌ 未覆盖 | 添加 JSON 解析错误测试 |
| 相对路径越界 | ❌ 未覆盖 | 添加路径遍历防护测试 |
| 绝对路径查询 | ❌ 未覆盖 | 添加绝对路径测试用例 |
| Git 信息存在 | ❌ 未覆盖 | 测试 git_info 非空场景 |

### 改进建议

1. **增加错误场景测试**:
   ```rust
   #[tokio::test]
   async fn get_conversation_summary_not_found() -> Result<()> {
       // 测试不存在的 conversation_id 返回正确错误码
   }
   ```

2. **增加 Git 信息测试**:
   ```rust
   let git_info = Some(GitInfo {
       sha: Some("abc123".to_string()),
       branch: Some("main".to_string()),
       origin_url: Some("https://github.com/openai/codex".to_string()),
   });
   create_fake_rollout_with_git_info(..., git_info)?;
   ```

3. **并发安全改进**:
   - 使用唯一的 UUID 避免文件名冲突
   - 或使用临时目录隔离每个测试

4. **时间戳动态生成**:
   ```rust
   let now = chrono::Utc::now();
   let filename_ts = now.format("%Y-%m-%dT%H-%M-%S").to_string();
   let meta_rfc3339 = now.to_rfc3339();
   ```

5. **路径测试增强**:
   - 测试 `../` 路径遍历防护
   - 测试符号链接处理
   - 测试 Windows UNC 路径

### 相关协议方法

| 方法 | 方向 | 说明 |
|------|------|------|
| `getConversationSummary` | Client → Server | 查询会话摘要 |

### 会话来源类型

```rust
pub enum SessionSource {
    Cli,       // 命令行启动
    Api,       // API 调用
    SubAgent,  // 子代理
}
```

测试当前仅覆盖 `SessionSource::Cli`，建议扩展测试其他来源。
