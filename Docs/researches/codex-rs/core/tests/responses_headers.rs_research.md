# responses_headers.rs 研究文档

## 场景与职责

`responses_headers.rs` 是 `codex-rs/core/tests/` 目录下的集成测试文件，专注于验证 **HTTP 请求头的正确性**。该文件测试 Codex 在与模型提供商 API（特别是 OpenAI Responses API）通信时，是否正确设置各种协议头（Headers）。

核心职责：
1. **验证子代理头（x-openai-subagent）**：确保子代理场景下正确标识代理类型
2. **验证回合元数据头（x-codex-turn-metadata）**：确保回合级别的元数据正确传递
3. **验证模型配置覆盖**：确保配置中的模型参数正确传递到 API 请求
4. **Git 工作区集成测试**：验证 Git 仓库元数据在请求头中的正确性

## 功能点目的

### 1. 子代理头测试 (`x-openai-subagent`)

测试 Codex 在不同子代理场景下是否正确设置 `x-openai-subagent` 请求头：

| 测试函数 | 场景 | 期望头值 |
|---------|------|---------|
| `responses_stream_includes_subagent_header_on_review` | 代码审查子代理 | `review` |
| `responses_stream_includes_subagent_header_on_other` | 自定义任务子代理 | `my-task` |

**技术背景**：
- `SessionSource::SubAgent(SubAgentSource::Review)` → 头值 `"review"`
- `SessionSource::SubAgent(SubAgentSource::Other(label))` → 头值 `label`

### 2. 模型配置覆盖测试

验证 `config.model_supports_reasoning_summaries` 和 `config.model_reasoning_summary` 是否正确传递到 API 请求体：

```rust
config.model_supports_reasoning_summaries = Some(true);
config.model_reasoning_summary = Some(ReasoningSummary::Detailed);
```

期望请求体包含：
```json
{
  "reasoning": {
    "summary": "detailed"
  }
}
```

### 3. Git 工作区元数据测试

验证 `x-codex-turn-metadata` 头在 Git 仓库环境下的正确性：

- **回合 ID（turn_id）**：唯一标识一个用户回合
- **沙盒类型（sandbox）**：如 `"none"`
- **工作区元数据**：
  - `latest_git_commit_hash`：最新 Git 提交哈希
  - `associated_remote_urls`：关联的远程仓库 URL
  - `has_changes`：是否有未提交更改

## 具体技术实现

### 关键数据结构

#### SessionSource 枚举

```rust
pub enum SessionSource {
    Cli,
    VSCode,
    Exec,
    Mcp,
    SubAgent(SubAgentSource),
    Unknown,
}

pub enum SubAgentSource {
    Review,
    Compact,
    ThreadSpawn { parent_thread_id, depth, agent_nickname, agent_role },
    MemoryConsolidation,
    Other(String),
}
```

#### TurnMetadata 结构

```rust
#[derive(Clone, Debug, Serialize, Default)]
pub(crate) struct TurnMetadataBag {
    turn_id: Option<String>,
    workspaces: BTreeMap<String, TurnMetadataWorkspace>,
    sandbox: Option<String>,
}

#[derive(Clone, Debug, Serialize, Default)]
struct TurnMetadataWorkspace {
    associated_remote_urls: Option<BTreeMap<String, String>>,
    latest_git_commit_hash: Option<String>,
    has_changes: Option<bool>,
}
```

### 关键流程

#### 子代理头构建流程

```rust
// codex-rs/core/src/client.rs
fn build_subagent_headers(&self) -> ApiHeaderMap {
    let mut extra_headers = ApiHeaderMap::new();
    if let SessionSource::SubAgent(sub) = &self.state.session_source {
        let subagent = match sub {
            SubAgentSource::Review => "review".to_string(),
            SubAgentSource::Compact => "compact".to_string(),
            SubAgentSource::MemoryConsolidation => "memory_consolidation".to_string(),
            SubAgentSource::ThreadSpawn { .. } => "collab_spawn".to_string(),
            SubAgentSource::Other(label) => label.clone(),
        };
        if let Ok(val) = HeaderValue::from_str(&subagent) {
            extra_headers.insert("x-openai-subagent", val);
        }
    }
    extra_headers
}
```

#### TurnMetadata 构建流程

```rust
// codex-rs/core/src/turn_metadata.rs
pub async fn build_turn_metadata_header(cwd: &Path, sandbox: Option<&str>) -> Option<String> {
    let repo_root = get_git_repo_root(cwd).map(|root| root.to_string_lossy().into_owned());

    let (latest_git_commit_hash, associated_remote_urls, has_changes) = tokio::join!(
        get_head_commit_hash(cwd),
        get_git_remote_urls_assume_git_repo(cwd),
        get_has_changes(cwd),
    );
    
    build_turn_metadata_bag(
        /*turn_id*/ None,
        sandbox.map(ToString::to_string),
        repo_root,
        Some(WorkspaceGitMetadata { ... }),
    ).to_header_value()
}
```

### 测试用例详解

#### 1. `responses_stream_includes_subagent_header_on_review`

```rust
#[tokio::test]
async fn responses_stream_includes_subagent_header_on_review() {
    core_test_support::skip_if_no_network!();

    // 1. 启动 Mock 服务器
    let server = responses::start_mock_server().await;
    
    // 2. 设置 SSE 响应
    let response_body = responses::sse(vec![...]);
    
    // 3. 挂载 Mock，期望包含 x-openai-subagent: review 头
    let request_recorder = responses::mount_sse_once_match(
        &server,
        header("x-openai-subagent", "review"),
        response_body,
    ).await;

    // 4. 创建 ModelClient，设置 SessionSource 为 Review
    let session_source = SessionSource::SubAgent(SubAgentSource::Review);
    let client = ModelClient::new(..., session_source, ...);
    
    // 5. 执行流式请求
    let mut stream = client_session.stream(...).await?;
    while let Some(event) = stream.next().await { ... }
    
    // 6. 验证请求头
    let request = request_recorder.single_request();
    assert_eq!(
        request.header("x-openai-subagent").as_deref(),
        Some("review")
    );
}
```

#### 2. `responses_respects_model_info_overrides_from_config`

```rust
#[tokio::test]
async fn responses_respects_model_info_overrides_from_config() {
    // 1. 配置模型覆盖参数
    config.model_supports_reasoning_summaries = Some(true);
    config.model_reasoning_summary = Some(ReasoningSummary::Detailed);
    
    // 2. 执行请求
    let mut stream = client_session.stream(...).await?;
    
    // 3. 验证请求体包含 reasoning 配置
    let request = request_recorder.single_request();
    let body = request.body_json();
    let reasoning = body.get("reasoning").and_then(|v| v.as_object()).cloned();
    
    assert_eq!(
        reasoning.as_ref().and_then(|v| v.get("summary")).and_then(|v| v.as_str()),
        Some("detailed")
    );
}
```

#### 3. `responses_stream_includes_turn_metadata_header_for_git_workspace_e2e`

这是最复杂的测试，验证 Git 工作区元数据：

```rust
#[tokio::test]
async fn responses_stream_includes_turn_metadata_header_for_git_workspace_e2e() {
    // 1. 初始化 Git 仓库
    run_git(&["init"]);
    run_git(&["config", "user.name", "Test User"]);
    run_git(&["config", "user.email", "test@example.com"]);
    run_git(&["add", "."]);
    run_git(&["commit", "-m", "initial commit"]);
    run_git(&["remote", "add", "origin", "https://github.com/openai/codex.git"]);
    
    // 2. 获取期望的 Git 元数据
    let expected_head = ...; // HEAD commit hash
    let expected_origin = ...; // remote URL
    
    // 3. 执行两轮请求
    test.submit_turn("hello").await?;
    test.submit_turn("hello").await?;
    
    // 4. 验证 x-codex-turn-metadata 头
    let requests = request_log.requests();
    let metadata: serde_json::Value = serde_json::from_str(
        &requests[0].header("x-codex-turn-metadata").expect(...)
    )?;
    
    // 验证回合 ID
    assert!(!metadata.get("turn_id").and_then(|v| v.as_str()).unwrap().is_empty());
    
    // 验证沙盒类型
    assert_eq!(metadata.get("sandbox").and_then(|v| v.as_str()), Some("none"));
    
    // 验证 Git 元数据
    let workspace = metadata.get("workspaces").and_then(|v| v.values().next()).cloned()?;
    assert_eq!(workspace.get("latest_git_commit_hash").and_then(|v| v.as_str()), Some(expected_head.as_str()));
    assert_eq!(workspace.get("associated_remote_urls").and_then(|v| v.get("origin")).and_then(|v| v.as_str()), Some(expected_origin.as_str()));
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `core_test_support` | 测试基础设施 |
| `responses` (test common) | Mock 服务器和 SSE 响应构建 |
| `test_codex` (test common) | TestCodex 测试辅助结构 |
| `ModelClient` | 模型客户端 |
| `SessionTelemetry` | 会话遥测 |
| `TurnMetadataState` | 回合元数据管理 |

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `wiremock` | HTTP Mock 服务器 |
| `tokio` | 异步运行时 |
| `serde_json` | JSON 序列化/反序列化 |
| `tempfile` | 临时目录创建 |
| `pretty_assertions` | 测试断言美化 |

### 关键文件引用

```
codex-rs/core/tests/responses_headers.rs
├── 依赖 -> codex-rs/core/tests/common/responses.rs
│   ├── ResponseMock - 请求记录和验证
│   ├── mount_sse_once_match - 条件 Mock 挂载
│   ├── mount_sse_once - 简单 Mock 挂载
│   ├── mount_response_sequence - 序列响应
│   └── ev_xxx 辅助函数 - SSE 事件构建
├── 依赖 -> codex-rs/core/tests/common/test_codex.rs
│   └── test_codex() - TestCodexBuilder 创建
├── 依赖 -> codex-rs/core/src/client.rs
│   ├── ModelClient - 模型客户端
│   ├── build_subagent_headers - 子代理头构建
│   └── X_CODEX_TURN_METADATA_HEADER - 头常量
├── 依赖 -> codex-rs/core/src/turn_metadata.rs
│   ├── TurnMetadataState - 回合元数据状态
│   ├── build_turn_metadata_header - 头值构建
│   └── WorkspaceGitMetadata - Git 元数据
└── 依赖 -> codex-rs/protocol/src/protocol.rs
    ├── SessionSource - 会话来源枚举
    └── SubAgentSource - 子代理来源枚举
```

## 风险、边界与改进建议

### 风险点

1. **网络依赖**：测试使用 `core_test_support::skip_if_no_network!()` 宏，在无网络环境下跳过。这可能导致 CI 环境中测试覆盖率下降。

2. **Git 环境依赖**：`responses_stream_includes_turn_metadata_header_for_git_workspace_e2e` 测试依赖本地 Git 命令，如果环境未安装 Git 或配置不当会失败。

3. **Mock 服务器状态**：测试依赖 wiremock 的精确匹配，如果请求头格式发生微小变化，测试会失败。

4. **时序问题**：`turn_id` 的生成和验证依赖时间戳，在极端情况下可能出现冲突。

### 边界条件

1. **非 Git 工作区**：测试主要覆盖 Git 仓库场景，非 Git 工作区的元数据行为需要额外验证。

2. **多远程仓库**：当前测试仅验证单个远程（origin），多远程场景未覆盖。

3. **子代理类型**：仅测试了 `Review` 和 `Other` 类型，其他类型（`Compact`, `MemoryConsolidation`, `ThreadSpawn`）未直接测试。

4. **并发回合**：测试按顺序执行，未验证并发回合的 `turn_id` 隔离性。

### 改进建议

1. **增加测试覆盖**：
   ```rust
   // 建议添加的测试
   async fn responses_stream_includes_subagent_header_on_compact();
   async fn responses_stream_includes_subagent_header_on_memory_consolidation();
   async fn responses_stream_includes_subagent_header_on_thread_spawn();
   async fn responses_turn_metadata_without_git_repo();
   async fn responses_turn_metadata_with_multiple_remotes();
   ```

2. **解耦 Git 依赖**：
   - 使用内存中的 Git 仓库（如 `git2` 库的内存模式）
   - 或者 Mock Git 命令的输出

3. **增强断言**：
   - 验证 `turn_id` 的格式（UUID 或其他规范）
   - 验证回合 ID 在不同回合间的变化
   - 验证请求头的编码（UTF-8、Base64 等）

4. **性能优化**：
   - 考虑使用 `tokio::test(flavor = "multi_thread")` 加速测试
   - 共享 Mock 服务器实例减少启动开销

5. **文档化**：
   - 添加每个测试的详细注释，说明测试目的和关键断言
   - 记录测试数据（如固件响应）的生成方法

---

**相关文件**：
- `codex-rs/core/src/client.rs` - ModelClient 实现
- `codex-rs/core/src/turn_metadata.rs` - TurnMetadata 实现
- `codex-rs/core/tests/common/responses.rs` - Mock 服务器工具
- `codex-rs/protocol/src/protocol.rs` - 协议定义
- `codex-rs/codex-api/src/requests/headers.rs` - 请求头构建
