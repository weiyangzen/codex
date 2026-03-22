# compaction.rs 研究文档

## 场景与职责

`compaction.rs` 是 Codex App Server v2 API 的集成测试文件，专注于测试**上下文压缩(Context Compaction)**功能。上下文压缩是 Codex 管理长对话历史的关键机制：

1. **自动压缩触发** - 当 token 使用量超过阈值时自动触发
2. **本地压缩** - 使用本地模型生成对话摘要
3. **远程压缩** - 使用 OpenAI API 的 `/v1/responses/compact` 端点
4. **手动压缩** - 通过 `thread/compact/start` RPC 手动触发
5. **压缩生命周期** - 验证 `item/started` 和 `item/completed` 通知

## 功能点目的

### 1. 自动压缩机制

当对话历史累积的 token 数超过 `model_auto_compact_token_limit` 配置时：

```
用户输入 ──▶ 模型响应 ──▶ 检查 token 使用量
                                │
                                ▼
                    超过阈值? ──▶ 触发自动压缩
                                │
                                ▼
                    发送 item/started 通知
                                │
                                ▼
                    生成摘要（本地或远程）
                                │
                                ▼
                    发送 item/completed 通知
```

### 2. 压缩模式对比

| 模式 | 实现 | 适用场景 | 隐私性 |
|-----|------|---------|--------|
| **本地压缩** | 使用本地模型生成摘要 | 敏感数据，离线环境 | 高 |
| **远程压缩** | 调用 OpenAI `/responses/compact` | 高质量摘要，Pro 用户 | 数据发送给 OpenAI |

### 3. 压缩流程

1. **触发条件**：token 使用量 > `auto_compact_limit`
2. **通知阶段**：
   - `item/started` - 压缩开始
   - `item/completed` - 压缩完成
3. **历史替换**：原始消息被摘要消息替换
4. **继续对话**：基于压缩后的历史继续

## 具体技术实现

### 关键数据结构

```rust
// 手动压缩请求参数
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadCompactStartParams {
    pub thread_id: String,
}

// 手动压缩响应
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadCompactStartResponse {}

// 线程项类型（包含压缩项）
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
pub enum ThreadItem {
    // ... 其他变体
    ContextCompaction {
        id: String,  // 压缩项唯一标识
    },
    // ...
}

// 项开始通知
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ItemStartedNotification {
    pub thread_id: String,
    pub item: ThreadItem,
}

// 项完成通知
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ItemCompletedNotification {
    pub thread_id: String,
    pub item: ThreadItem,
}

// Turn 完成通知（用于测试同步）
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnCompletedNotification {
    pub thread_id: String,
    pub turn: Turn,
}
```

### 测试配置

```rust
const AUTO_COMPACT_LIMIT: i64 = 1_000;           // 自动压缩阈值
const COMPACT_PROMPT: &str = "Summarize the conversation.";  // 压缩提示词
const INVALID_REQUEST_ERROR_CODE: i64 = -32600;  // JSON-RPC 无效请求错误码
```

### 测试用例详解

| 测试用例 | 目的 | 关键技术点 |
|---------|------|-----------|
| `auto_compaction_local_emits_started_and_completed_items` | 本地自动压缩 | 验证通知序列，token 阈值触发 |
| `auto_compaction_remote_emits_started_and_completed_items` | 远程自动压缩 | 验证 `/responses/compact` 调用，Pro 用户 |
| `thread_compact_start_triggers_compaction_and_returns_empty_response` | 手动压缩 | `thread/compact/start` RPC |
| `thread_compact_start_rejects_invalid_thread_id` | 输入验证 | 无效 UUID 格式拒绝 |
| `thread_compact_start_rejects_unknown_thread_id` | 存在性验证 | 不存在的线程 ID 拒绝 |

### 本地自动压缩测试流程

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn auto_compaction_local_emits_started_and_completed_items() -> Result<()> {
    skip_if_no_network!(Ok(()));  // 需要网络

    // 1. 启动 Mock 服务器
    let server = responses::start_mock_server().await;
    
    // 2. 配置 SSE 响应序列
    // sse1: 第一次对话 (70k tokens)
    // sse2: 第二次对话 (330k tokens) - 触发压缩
    // sse3: 压缩摘要生成
    // sse4: 压缩后对话
    responses::mount_sse_sequence(&server, vec![sse1, sse2, sse3, sse4]).await;

    // 3. 写入配置（本地压缩）
    write_mock_responses_config_toml(
        codex_home.path(),
        &server.uri(),
        &BTreeMap::default(),
        AUTO_COMPACT_LIMIT,  // 1k token 阈值
        None,                // 本地压缩
        "mock_provider",
        COMPACT_PROMPT,
    )?;

    // 4. 初始化 MCP
    let mut mcp = McpProcess::new(codex_home.path()).await?;
    timeout(DEFAULT_READ_TIMEOUT, mcp.initialize()).await??;

    // 5. 创建线程
    let thread_id = start_thread(&mut mcp).await?;

    // 6. 发送三次对话，触发压缩
    for message in ["first", "second", "third"] {
        send_turn_and_wait(&mut mcp, &thread_id, message).await?;
    }

    // 7. 验证压缩通知
    let started = wait_for_context_compaction_started(&mut mcp).await?;
    let completed = wait_for_context_compaction_completed(&mut mcp).await?;

    // 8. 验证通知内容
    assert_eq!(started.thread_id, thread_id);
    assert_eq!(completed.thread_id, thread_id);
    assert_eq!(started_id, completed_id);  // 相同压缩项 ID

    Ok(())
}
```

### 远程自动压缩测试流程

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn auto_compaction_remote_emits_started_and_completed_items() -> Result<()> {
    const REMOTE_AUTO_COMPACT_LIMIT: i64 = 200_000;

    // 1. 启动 Mock 服务器
    let server = responses::start_mock_server().await;
    
    // 2. 配置 SSE 响应
    responses::mount_sse_sequence(&server, vec![sse1, sse2, sse3]).await;

    // 3. 配置远程压缩端点
    let compacted_history = vec![
        ResponseItem::Message { ... },
        ResponseItem::Compaction { encrypted_content: "..." },
    ];
    let compact_mock = responses::mount_compact_json_once(
        &server,
        serde_json::json!({ "output": compacted_history }),
    ).await;

    // 4. 写入配置（远程压缩）
    write_mock_responses_config_toml(
        codex_home.path(),
        &server.uri(),
        &BTreeMap::default(),
        REMOTE_AUTO_COMPACT_LIMIT,
        Some(true),  // 启用远程压缩
        "mock_provider",
        COMPACT_PROMPT,
    )?;

    // 5. 设置 ChatGPT 认证（Pro 用户）
    write_chatgpt_auth(..., ChatGptAuthFixture::new(...).plan_type("pro"), ...)?;

    // 6. 移除 OPENAI_API_KEY 以强制使用 ChatGPT 认证
    let mut mcp = McpProcess::new_with_env(codex_home.path(), &[("OPENAI_API_KEY", None)]).await?;

    // 7-8. 创建线程，发送对话，验证通知...

    // 9. 验证远程压缩端点被调用
    let compact_requests = compact_mock.requests();
    assert_eq!(compact_requests.len(), 1);
    assert_eq!(compact_requests[0].path(), "/v1/responses/compact");

    Ok(())
}
```

### 测试辅助函数

```rust
// 创建线程
async fn start_thread(mcp: &mut McpProcess) -> Result<String> {
    let thread_id = mcp
        .send_thread_start_request(ThreadStartParams {
            model: Some("mock-model".to_string()),
            ..Default::default()
        })
        .await?;
    // ... 读取响应，返回 thread.id
}

// 发送对话并等待完成
async fn send_turn_and_wait(mcp: &mut McpProcess, thread_id: &str, text: &str) -> Result<String> {
    let turn_id = mcp
        .send_turn_start_request(TurnStartParams {
            thread_id: thread_id.to_string(),
            input: vec![V2UserInput::Text { text: text.to_string(), ... }],
            ..Default::default()
        })
        .await?;
    // ... 等待 turn/completed 通知
}

// 等待 Turn 完成
async fn wait_for_turn_completed(mcp: &mut McpProcess, turn_id: &str) -> Result<()> {
    loop {
        let notification = mcp.read_stream_until_notification_message("turn/completed").await?;
        let completed: TurnCompletedNotification = ...;
        if completed.turn.id == turn_id {
            return Ok(());
        }
    }
}

// 等待压缩开始通知
async fn wait_for_context_compaction_started(mcp: &mut McpProcess) -> Result<ItemStartedNotification> {
    loop {
        let notification = mcp.read_stream_until_notification_message("item/started").await?;
        let started: ItemStartedNotification = ...;
        if let ThreadItem::ContextCompaction { .. } = started.item {
            return Ok(started);
        }
    }
}

// 等待压缩完成通知
async fn wait_for_context_compaction_completed(mcp: &mut McpProcess) -> Result<ItemCompletedNotification> {
    loop {
        let notification = mcp.read_stream_until_notification_message("item/completed").await?;
        let completed: ItemCompletedNotification = ...;
        if let ThreadItem::ContextCompaction { .. } = completed.item {
            return Ok(completed);
        }
    }
}
```

## 关键代码路径与文件引用

### 测试文件
- `/codex-rs/app-server/tests/suite/v2/compaction.rs` - 本测试文件

### 协议定义
- `/codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `ThreadCompactStartParams` (行 2864-2869)
  - `ThreadCompactStartResponse` (行 2871-2874)
  - `ThreadItem::ContextCompaction` - 线程项类型
  - `ItemStartedNotification` - 项开始通知
  - `ItemCompletedNotification` - 项完成通知
  - `TurnCompletedNotification` - Turn 完成通知

### 测试支持
- `/codex-rs/app-server/tests/common/config.rs`:
  - `write_mock_responses_config_toml` - 配置生成
- `/codex-rs/app-server/tests/common/auth_fixtures.rs`:
  - `ChatGptAuthFixture` - 认证 fixture
- `/codex-rs/core/tests/common/responses.rs`:
  - `start_mock_server` - Mock 服务器
  - `mount_sse_sequence` - SSE 序列挂载
  - `mount_compact_json_once` - 压缩端点挂载
  - `ev_assistant_message`, `ev_completed_with_tokens` - SSE 事件

### 核心测试支持
- `/codex-rs/core/src/test_support/mod.rs`:
  - `skip_if_no_network` - 网络检查宏

## 依赖与外部交互

### 外部服务依赖
1. **Mock OpenAI 服务器** - 提供 SSE 响应和压缩端点
2. **网络连接** - 测试标记为 `skip_if_no_network`
3. **Codex App Server** - 被测服务

### 协议依赖
- **JSON-RPC 2.0** - RPC 通信
- **SSE (Server-Sent Events)** - 模型响应流
- **HTTP POST** - 压缩端点调用

### 配置依赖
```toml
# config.toml 关键配置
model = "mock-model"
compact_prompt = "Summarize the conversation."
model_auto_compact_token_limit = 1000  # 本地
# 或
model_auto_compact_token_limit = 200000  # 远程
use_remote_compaction = true  # 启用远程压缩
```

## 风险、边界与改进建议

### 已知风险

1. **网络依赖**
   - 所有测试都需要网络连接
   - 使用 `skip_if_no_network!` 宏跳过离线环境
   - 建议：添加纯本地 Mock 测试

2. **时序敏感**
   - 压缩触发依赖于 token 计数
   - Mock 服务器的 token 返回必须精确
   - 建议：使用确定性 token 值

3. **多线程复杂性**
   - 测试使用 `flavor = "multi_thread"`
   - 可能引入竞态条件
   - 建议：添加单线程变体测试

### 边界情况

1. **压缩阈值边界**
   - 正好等于阈值时的行为
   - 连续多次压缩的场景
   - 压缩后仍然超过阈值（级联压缩）

2. **远程压缩失败**
   - 网络超时处理
   - 认证失败回退
   - 服务器错误处理

3. **并发压缩**
   - 手动压缩与自动压缩同时触发
   - 多线程环境下的压缩状态管理

### 改进建议

1. **测试覆盖增强**
   ```rust
   // 建议添加：级联压缩
   #[tokio::test]
   async fn auto_compaction_handles_cascade() { ... }

   // 建议添加：远程压缩失败回退
   #[tokio::test]
   async fn remote_compaction_falls_back_to_local() { ... }

   // 建议添加：压缩中断
   #[tokio::test]
   async fn compaction_can_be_interrupted() { ... }

   // 建议添加：空历史压缩
   #[tokio::test]
   async fn compaction_handles_empty_history() { ... }
   ```

2. **性能测试**
   - 大历史（100k+ tokens）的压缩性能
   - 压缩对响应延迟的影响
   - 内存使用峰值测量

3. **可靠性测试**
   - 模拟网络分区
   - 模拟服务器重启
   - 验证压缩状态持久化

4. **配置验证**
   - 无效压缩提示词处理
   - 阈值范围验证（负数、超大值）
   - 远程/本地模式切换

### 架构考虑

1. **压缩策略选择**
   - 本地：隐私优先，无需网络
   - 远程：质量优先，需要 Pro 订阅
   - 混合：根据内容敏感度自动选择

2. **通知设计**
   - `item/started` 允许 UI 显示进度
   - `item/completed` 允许 UI 更新历史
   - 异步设计不阻塞用户输入

3. **历史替换**
   - 压缩项替换原始消息
   - 保留加密内容用于审计
   - 支持历史分叉和回滚

### 相关测试模式

该测试与其他线程测试共享模式：
- `thread_start.rs` - 线程创建
- `turn_start.rs` - 对话轮次
- `thread_rollback.rs` - 历史回滚

共享的测试基础设施：
- `start_thread` - 统一线程创建
- `send_turn_and_wait` - 统一对话发送
- `wait_for_turn_completed` - 统一完成等待
