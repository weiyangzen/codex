# sqlite_state.rs 研究文档

## 场景与职责

`sqlite_state.rs` 是 Codex Core 的集成测试套件，专注于验证 SQLite 状态持久化功能的正确性。该测试文件确保 Codex 能够将线程元数据、用户消息、动态工具配置以及内存模式状态可靠地存储到本地 SQLite 数据库中。

### 核心职责
1. **状态数据库生命周期验证**：验证新线程首次用户消息时正确创建状态记录
2. **历史数据回填**：验证启动时扫描现有 rollout 文件并回填到状态数据库
3. **用户消息持久化**：验证用户消息被正确记录到状态数据库
4. **内存模式污染检测**：验证 Web 搜索和 MCP 调用会标记线程内存模式为 "polluted"
5. **工具调用日志追踪**：验证工具调用日志包含线程 ID 上下文

## 功能点目的

### 1. 新线程状态记录 (`new_thread_is_recorded_in_state_db`)
- **目的**：确保新创建的线程在首次用户消息后正确记录到 SQLite 状态数据库
- **验证点**：
  - 状态数据库文件在配置目录下创建
  - 线程元数据（ID、rollout 路径）正确存储
  - rollout 文件在首次消息后物化

### 2. 历史数据回填 (`backfill_scans_existing_rollouts`)
- **目的**：验证 Codex 启动时能够扫描并导入已存在的 rollout 文件
- **验证点**：
  - 预创建的 rollout 文件被正确识别
  - 线程元数据从 rollout 解析并存储
  - 动态工具配置正确回填

### 3. 用户消息持久化 (`user_messages_persist_in_state_db`)
- **目的**：验证用户消息被持久化到状态数据库
- **验证点**：
  - 多条用户消息被记录
  - `first_user_message` 字段正确设置

### 4. 内存模式污染检测 (`web_search_marks_thread_memory_mode_polluted_when_configured` / `mcp_call_marks_thread_memory_mode_polluted_when_configured`)
- **目的**：验证当配置 `no_memories_if_mcp_or_web_search = true` 时，Web 搜索或 MCP 调用会标记线程内存模式为 "polluted"
- **验证点**：
  - Web 搜索调用后 `memory_mode` 变为 "polluted"
  - MCP 工具调用后 `memory_mode` 变为 "polluted"

### 5. 工具调用日志追踪 (`tool_call_logs_include_thread_id`)
- **目的**：验证工具调用日志包含线程 ID，便于审计和调试
- **验证点**：
  - 日志数据库中包含 `thread_id` 字段
  - 工具调用消息正确记录

## 具体技术实现

### 关键流程

#### 测试初始化流程
```rust
let server = start_mock_server().await;
let mut builder = test_codex().with_config(|config| {
    config.features.enable(Feature::Sqlite).expect(...);
});
let test = builder.build(&server).await?;
```

#### 状态数据库访问
```rust
let db_path = codex_state::state_db_path(test.config.sqlite_home.as_path());
// 等待数据库创建
for _ in 0..100 {
    if tokio::fs::try_exists(&db_path).await.unwrap_or(false) {
        break;
    }
    tokio::time::sleep(Duration::from_millis(25)).await;
}
let db = test.codex.state_db().expect("state db enabled");
```

#### 预构建 Hook（用于回填测试）
```rust
.with_pre_build_hook(move |codex_home| {
    // 创建 rollout 目录结构
    fs::create_dir_all(parent).expect(...);
    // 写入 SessionMetaLine 和 RolloutLine
    let jsonl = lines.iter().map(...).collect::<Vec<_>>().join("\n");
    fs::write(&rollout_path, format!("{jsonl}\n")).expect(...);
})
```

### 数据结构

#### SessionMetaLine
```rust
SessionMetaLine {
    meta: SessionMeta {
        id: thread_id,
        forked_from_id: None,
        timestamp: "2026-01-27T12:00:00Z".to_string(),
        cwd: codex_home.to_path_buf(),
        originator: "test".to_string(),
        cli_version: "test".to_string(),
        source: SessionSource::default(),
        agent_nickname: None,
        agent_role: None,
        model_provider: None,
        base_instructions: None,
        dynamic_tools: Some(dynamic_tools_for_hook),
        memory_mode: None,
    },
    git: None,
}
```

#### DynamicToolSpec
```rust
DynamicToolSpec {
    name: "geo_lookup".to_string(),
    description: "lookup a city".to_string(),
    input_schema: json!({
        "type": "object",
        "required": ["city"],
        "properties": { "city": { "type": "string" } }
    }),
    defer_loading: true,
}
```

### 协议与交互

#### SSE Mock 响应
```rust
mount_sse_sequence(&server, vec![
    responses::sse(vec![ev_response_created("resp-1"), ev_completed("resp-1")]),
    responses::sse(vec![ev_response_created("resp-2"), ev_completed("resp-2")]),
]).await;
```

#### MCP 服务器配置
```rust
McpServerConfig {
    transport: McpServerTransportConfig::Stdio {
        command: rmcp_test_server_bin,
        args: Vec::new(),
        env: Some(HashMap::from([...])),
        env_vars: Vec::new(),
        cwd: None,
    },
    enabled: true,
    required: false,
    ...
}
```

## 关键代码路径与文件引用

### 被测代码路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/features.rs` | Feature 标志定义，`Feature::Sqlite` 控制状态持久化 |
| `codex-rs/state/src/lib.rs` | 状态数据库核心实现 |
| `codex-rs/state/src/log_db.rs` | 日志数据库实现 |
| `codex-rs/core/src/codex.rs` | `state_db()` 方法暴露状态数据库访问 |

### 测试依赖路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/common/lib.rs` | 测试公共库，包含 `skip_if_no_network!` 宏 |
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodex` 和 `TestCodexBuilder` 实现 |
| `codex-rs/core/tests/common/responses.rs` | SSE Mock 响应构造器 |

### 关键方法引用
```rust
// codex_state 库
codex_state::state_db_path(sqlite_home: &Path) -> PathBuf

// CodexThread
test.codex.state_db() -> Option<Arc<StateDb>>

// StateDb
db.get_thread(thread_id: ThreadId) -> Result<Option<ThreadMetadata>>
db.get_dynamic_tools(thread_id: ThreadId) -> Result<Option<Vec<DynamicToolSpec>>>
db.get_thread_memory_mode(thread_id: ThreadId) -> Result<Option<String>>
db.query_logs(&query) -> Result<Vec<LogRow>>
```

## 依赖与外部交互

### 外部依赖
1. **wiremock**: HTTP Mock 服务器，用于模拟 OpenAI API
2. **tokio**: 异步运行时
3. **serde_json**: JSON 序列化/反序列化
4. **uuid**: UUID v7 生成
5. **tracing_subscriber**: 日志追踪

### 内部依赖
1. **codex_core**: 核心库，提供 `Feature`、`Config` 等
2. **codex_protocol**: 协议定义，提供 `ThreadId`、`EventMsg` 等
3. **codex_state**: 状态持久化库
4. **core_test_support**: 测试支持库

### 环境要求
- 网络访问（通过 `skip_if_no_network!` 宏在沙箱中跳过）
- `test_stdio_server` 二进制文件（用于 MCP 测试）

## 风险、边界与改进建议

### 已知风险
1. **竞态条件**：测试使用轮询等待数据库创建，可能因系统负载导致超时
2. **路径依赖**：测试硬编码了 rollout 路径格式 `sessions/2026/01/27/rollout-...`
3. **MCP 测试依赖外部二进制**：`stdio_server_bin()` 需要 `test_stdio_server` 可执行文件

### 边界情况
1. **数据库尚未创建**：测试通过 100 次重试（每次 25ms）等待数据库创建
2. **元数据尚未写入**：同样使用轮询等待状态回填完成
3. **网络禁用环境**：通过 `skip_if_no_network!` 宏优雅跳过

### 改进建议
1. **使用事件驱动替代轮询**：考虑使用文件系统通知或数据库触发器替代固定间隔轮询
2. **提取魔法数字**：将重试次数和间隔提取为常量或配置参数
3. **增强错误上下文**：在 `expect()` 消息中添加更多调试信息
4. **并发测试优化**：当前测试使用 `worker_threads = 2`，但状态数据库访问可能是串行的
5. **添加清理验证**：测试结束后验证临时目录被正确清理

### 测试覆盖率缺口
1. 未测试状态数据库损坏恢复场景
2. 未测试大量线程并发创建的性能
3. 未测试状态数据库迁移（schema 变更）场景
