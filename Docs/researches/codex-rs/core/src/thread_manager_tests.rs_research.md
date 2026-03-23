# thread_manager_tests.rs 研究文档

## 场景与职责

`thread_manager_tests.rs` 是 `thread_manager.rs` 的配套测试模块，负责验证线程管理器的核心功能：

1. **历史截断逻辑测试**：验证 `truncate_before_nth_user_message` 函数的正确性
2. **会话前缀消息处理**：确保系统注入的前缀消息不影响用户消息计数
3. **并发关闭测试**：验证 `shutdown_all_threads_bounded` 的并发行为
4. **模型提供者配置测试**：验证自定义 OpenAI 提供者配置生效

该测试模块使用 `#[path = "thread_manager_tests.rs"]` 属性内联在 `thread_manager.rs` 中。

## 功能点目的

### 1. 历史截断测试 (`drops_from_last_user_only`)

验证 fork 功能的核心逻辑：
- 给定混合用户/助手/工具调用的消息序列
- 截断应保留到第 N 个用户消息之前的所有内容
- 正确处理 `usize::MAX`（保留全部）和越界（返回空）情况

### 2. 会话前缀消息测试 (`ignores_session_prefix_messages_when_truncating`)

验证系统注入的上下文消息（如环境信息、技能说明）不计入用户消息索引：
- 前缀消息由 `make_session_and_context()` 生成
- 用户实际输入从特定位置开始计数

### 3. 并发关闭测试 (`shutdown_all_threads_bounded_submits_shutdown_to_every_thread`)

验证：
- 多个线程同时关闭不会 panic
- 所有线程最终完成关闭
- 关闭后线程列表为空

### 4. 模型提供者配置测试 (`new_uses_configured_openai_provider_for_model_refresh`)

验证：
- 自定义 `base_url` 配置被正确传递
- 模型刷新请求发送到配置的端点

## 具体技术实现

### 测试辅助函数

```rust
fn user_msg(text: &str) -> ResponseItem {
    ResponseItem::Message { role: "user".to_string(), content: vec![...], ... }
}

fn assistant_msg(text: &str) -> ResponseItem {
    ResponseItem::Message { role: "assistant".to_string(), content: vec![...], ... }
}
```

### 历史截断断言模式

```rust
let initial: Vec<RolloutItem> = items.iter().cloned().map(RolloutItem::ResponseItem).collect();
let truncated = truncate_before_nth_user_message(InitialHistory::Forked(initial), 1);
let got_items = truncated.get_rollout_items();

// 使用 JSON 序列化比较，忽略内部结构差异
assert_eq!(
    serde_json::to_value(&got_items).unwrap(),
    serde_json::to_value(&expected_items).unwrap()
);
```

### 并发测试设置

```rust
let manager = ThreadManager::with_models_provider_and_home_for_tests(
    CodexAuth::from_api_key("dummy"),
    config.model_provider.clone(),
    config.codex_home.clone(),
);

// 创建两个线程
let thread_1 = manager.start_thread(config.clone()).await?.thread_id;
let thread_2 = manager.start_thread(config).await?.thread_id;

// 并发关闭
let report = manager.shutdown_all_threads_bounded(Duration::from_secs(10)).await;
```

### Mock Server 使用

```rust
let server = MockServer::start().await;
let models_mock = mount_models_once(&server, ModelsResponse { models: vec![] }).await;

// 配置自定义 base_url
config.model_providers.get_mut("openai").unwrap().base_url = Some(server.uri());

// 验证请求到达 mock
assert_eq!(models_mock.requests().len(), 1);
```

## 关键代码路径与文件引用

### 被测代码

| 代码 | 路径 | 测试覆盖 |
|------|------|----------|
| `truncate_before_nth_user_message` | `thread_manager.rs:820` | `drops_from_last_user_only` |
| `shutdown_all_threads_bounded` | `thread_manager.rs:484` | `shutdown_all_threads_bounded_submits_shutdown_to_every_thread` |
| `ThreadManager::new` | `thread_manager.rs:165` | `new_uses_configured_openai_provider_for_model_refresh` |

### 测试依赖

| 模块 | 用途 |
|------|------|
| `make_session_and_context` | 创建带前缀消息的测试会话 |
| `test_config` | 生成默认测试配置 |
| `mount_models_once` | Mock OpenAI 模型列表端点 |
| `MockServer` (wiremock) | HTTP 模拟服务器 |
| `tempfile::tempdir` | 临时目录管理 |

## 依赖与外部交互

### 测试框架

- **Tokio**: 异步运行时 (`#[tokio::test]`)
- **wiremock**: HTTP Mock 服务器
- **tempfile**: 临时文件系统操作
- **pretty_assertions**: 友好的断言输出
- **assert_matches**: 模式匹配断言

### 协议类型

```rust
use codex_protocol::models::ContentItem;
use codex_protocol::models::ReasoningItemReasoningSummary;
use codex_protocol::models::ResponseItem;
use codex_protocol::openai_models::ModelsResponse;
```

## 风险、边界与改进建议

### 当前覆盖缺口

1. **Fork 线程**：无直接测试 `fork_thread` 方法
2. **错误处理**：未测试无效 rollout 路径、损坏的历史文件
3. **并发竞争**：未测试线程创建和关闭的竞态条件
4. **MCP 刷新**：`refresh_mcp_servers` 方法未测试

### 测试稳定性

1. **超时依赖**：`shutdown_all_threads_bounded` 测试依赖 10 秒超时，在慢速环境可能 flaky
2. **端口占用**：MockServer 使用随机端口，理论上安全但可能受防火墙影响

### 改进建议

1. **添加 Fork 测试**：
```rust
#[tokio::test]
async fn fork_thread_creates_new_thread_with_truncated_history() {
    // 创建线程 -> 添加消息 -> Fork -> 验证历史长度
}
```

2. **添加错误场景测试**：
```rust
#[tokio::test]
async fn resume_from_nonexistent_rollout_returns_error() {
    // 验证错误类型和消息
}
```

3. **使用 `cargo-nextest`**：测试模块已支持，建议 CI 中启用以并行执行

4. **Snapshot 测试**：历史截断结果可使用 `insta` 进行 snapshot 测试，提高可维护性

### 代码统计

- 测试行数：187 行
- 测试函数：4 个
- 辅助函数：2 个
