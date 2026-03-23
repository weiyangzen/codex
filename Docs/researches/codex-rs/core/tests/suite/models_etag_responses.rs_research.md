# models_etag_responses.rs 研究文档

## 场景与职责

`models_etag_responses.rs` 是 Codex Core 集成测试套件中专注于**响应头 ETag 缓存同步**的测试文件。该文件验证 Codex 如何根据 HTTP 响应头中的 `X-Models-Etag` 来同步和刷新模型缓存，确保：

1. **ETag 不匹配时的缓存刷新**：当 `/responses` 端点返回的 `X-Models-Etag` 与本地缓存不匹配时，自动刷新 `/models` 缓存
2. **避免重复刷新**：在已刷新缓存后，后续相同 ETag 的响应不应触发额外的 `/models` 请求
3. **客户端版本传递**：验证刷新 `/models` 时正确传递 `client_version` 查询参数

这些测试确保了 Codex 能够及时感知服务端模型列表的变更，同时避免不必要的网络请求。

## 功能点目的

### 测试用例

| 测试函数 | 目的 | 关键验证点 |
|----------|------|------------|
| `refresh_models_on_models_etag_mismatch_and_avoid_duplicate_models_fetch` | ETag 不匹配刷新 + 去重 | 1) ETag 变化触发 `/models` 刷新 2) 相同 ETag 不重复刷新 3) 请求包含 `client_version` 参数 |

### 测试场景详解

测试模拟了以下交互序列：

1. **初始状态**：Codex 启动，首次获取 `/models`，获取 ETag `"models-etag-1"`
2. **用户回合**：提交用户输入，`/responses` 返回工具调用 + 新 ETag `"models-etag-2"`
3. **缓存刷新**：Codex 检测到 ETag 变化，自动刷新 `/models`
4. **工具输出**：提交工具输出，`/responses` 返回相同 ETag `"models-etag-2"`
5. **去重验证**：未触发额外的 `/models` 请求

## 具体技术实现

### 测试流程代码

```rust
// models_etag_responses.rs 行 27-139
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn refresh_models_on_models_etag_mismatch_and_avoid_duplicate_models_fetch() -> Result<()> {
    skip_if_no_network!(Ok(()));

    const ETAG_1: &str = "\"models-etag-1\"";
    const ETAG_2: &str = "\"models-etag-2\"";
    const CALL_ID: &str = "local-shell-call-1";

    let server = MockServer::start().await;

    // 1) 初始 /models 请求，返回 ETAG_1
    let spawn_models_mock = responses::mount_models_once_with_etag(
        &server,
        ModelsResponse { models: Vec::new() },
        ETAG_1,
    ).await;

    let test = builder.build(&server).await?;
    assert_eq!(spawn_models_mock.requests().len(), 1);

    // 2) 准备 ETag 不匹配的场景，/responses 返回 ETAG_2
    let refresh_models_mock = responses::mount_models_once_with_etag(
        &server,
        ModelsResponse { models: Vec::new() },
        ETAG_2,
    ).await;

    // 第一个 /responses 返回工具调用 + 新 ETag
    let first_response_body = sse(vec![
        ev_response_created("resp-1"),
        ev_local_shell_call(CALL_ID, "completed", vec!["/bin/echo", "etag ok"]),
        ev_completed("resp-1"),
    ]);
    responses::mount_response_once(
        &server,
        sse_response(first_response_body).insert_header("X-Models-Etag", ETAG_2),
    ).await;

    // 3) 提交用户输入，触发 ETag 刷新
    codex.submit(Op::UserTurn { ... }).await?;
    wait_for_event(&codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;

    // 验证：/models 被刷新一次
    assert_eq!(refresh_models_mock.requests().len(), 1);
    
    // 验证：请求包含 client_version 参数
    let refresh_req = refresh_models_mock.requests().into_iter().next().expect("one request");
    assert!(
        refresh_req.url.query_pairs().any(|(k, _)| k == "client_version"),
        "expected /models refresh to include client_version query param"
    );

    // 4) 第二个 /responses 返回相同 ETag，验证不重复刷新
    let completion_response_body = sse(vec![...]);
    let tool_output_mock = responses::mount_response_once(
        &server,
        sse_response(completion_response_body).insert_header("X-Models-Etag", ETAG_2),
    ).await;

    // 验证：未触发额外的 /models 请求
    assert_eq!(refresh_models_mock.requests().len(), 1);

    Ok(())
}
```

### ETag 处理机制

```rust
// codex-api/src/sse/responses.rs 行 64-68
let models_etag = stream_response
    .headers
    .get("X-Models-Etag")
    .and_then(|v| v.to_str().ok())
    .map(ToString::to_string);
```

ETag 通过 SSE 事件流传递给上层：

```rust
// codex-api/src/sse/responses.rs 行 94-96
if let Some(etag) = models_etag {
    let _ = tx_event.send(Ok(ResponseEvent::ModelsEtag(etag))).await;
}
```

### Mock 辅助函数

```rust
// tests/common/responses.rs
pub async fn mount_models_once_with_etag(
    server: &MockServer,
    response: ModelsResponse,
    etag: &str,
) -> ModelsMock {
    let (mock, models_mock) = models_mock();
    mock.respond_with(
        ResponseTemplate::new(200)
            .insert_header("content-type", "application/json")
            .insert_header("ETag", etag)  // 设置 ETag 响应头
            .set_body_json(response)
    )
    .up_to_n_times(1)
    .mount(server)
    .await;
    models_mock
}
```

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 功能描述 |
|------|----------|
| `codex-rs/codex-api/src/sse/responses.rs` | 从 SSE 响应头提取 `X-Models-Etag` 并作为事件发送 |
| `codex-rs/core/src/models_manager/manager.rs` | 处理 `ModelsEtag` 事件，决定是否刷新缓存 |
| `codex-rs/core/src/models_manager/cache.rs` | 缓存 ETag 的存储和比较逻辑 |

### 事件流处理

```
SSE Response Headers
    ↓
codex-api/src/sse/responses.rs (extract X-Models-Etag)
    ↓
ResponseEvent::ModelsEtag(etag)
    ↓
codex-core event handler
    ↓
ModelsManager::maybe_refresh_on_etag(etag)
    ↓
Compare with cached ETag
    ↓
Refresh if different
```

### 测试支持文件

| 文件 | 用途 |
|------|------|
| `codex-rs/core/tests/common/responses.rs` | `mount_models_once_with_etag`, `mount_response_once` |
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodexBuilder` 和测试环境设置 |
| `codex-rs/core/tests/common/lib.rs` | `skip_if_no_network!` 宏 |

## 依赖与外部交互

### 平台限制

```rust
#![cfg(not(target_os = "windows"))]
```

该测试文件被配置为不在 Windows 平台运行，可能是因为：
1. 使用了 Unix 特定的工具调用（`/bin/echo`）
2. 依赖某些 Unix 特定的测试基础设施

### 外部依赖

- **wiremock**: HTTP Mock 服务器，支持响应头设置
- **tokio**: 异步运行时
- **anyhow**: 错误处理

### 协议常量

```rust
const ETAG_1: &str = "\"models-etag-1\"";
const ETAG_2: &str = "\"models-etag-2\"";
const CALL_ID: &str = "local-shell-call-1";
```

注意：ETag 值使用 HTTP 标准的带引号格式（`"value"`）。

### 网络跳过宏

```rust
skip_if_no_network!(Ok(()));
```

该宏检查 `CODEX_SANDBOX_NETWORK_DISABLED` 环境变量，若设置则跳过测试。

## 风险、边界与改进建议

### 当前风险

1. **单测试文件**：整个文件仅包含一个测试函数，覆盖密度较低
2. **平台限制**：`#![cfg(not(target_os = "windows"))]` 限制了测试覆盖范围
3. **网络依赖**：使用 `skip_if_no_network!`，在无网络环境下完全跳过

### 边界情况

1. **ETag 缺失**：未测试服务器不返回 `X-Models-Etag` 头的情况
2. **ETag 格式异常**：未测试非标准 ETag 格式（如无引号、弱验证标记 `W/`）
3. **并发 ETag 变更**：未测试多回合并发执行时的 ETag 处理
4. **缓存刷新失败**：未测试 `/models` 刷新请求失败时的回退策略

### 改进建议

1. **增加测试覆盖**：
   - ETag 从缺失到出现的变化
   - ETag 从存在到缺失的变化
   - 相同 ETag 但模型内容实际变化的场景（理论上不应发生，但应验证处理）

2. **移除平台限制**：
   - 将 `/bin/echo` 替换为跨平台命令或使用 Mock 工具调用
   - 或添加 Windows 特定的等效测试

3. **添加离线测试变体**：
   - 使用纯 Mock 测试验证 ETag 比较逻辑，减少对真实网络的依赖

4. **测试刷新失败场景**：
   - 模拟 `/models` 返回 5xx 错误时的行为
   - 验证是否保留旧缓存并继续运行

5. **性能测试**：
   - 验证高频 ETag 变更场景下的请求去重效果
   - 测量 ETag 比较和缓存刷新的开销

### 相关测试文件

- `models_cache_ttl.rs`: 测试缓存 TTL 刷新机制（与 ETag 刷新互补）
- `client.rs`: 测试客户端基础功能，包括模型列表获取
- `remote_models.rs`: 测试远程模型元数据的处理

### 调试命令

```bash
# 运行本测试
cargo test -p codex-core --test suite models_etag_responses

# 带详细日志运行
RUST_LOG=codex_core::models_manager=debug,codex_api=debug \
    cargo test -p codex-core --test suite models_etag_responses

# 检查测试是否被跳过
cargo test -p codex-core --test suite models_etag_responses -- --nocapture
```

### 架构关系图

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   /responses    │────▶│  SSE Processor   │────▶│  ModelsManager  │
│  X-Models-Etag  │     │  Extract Header  │     │  Compare ETag   │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
                                                          │
                              ┌───────────────────────────┘
                              ▼
                    ┌─────────────────┐
                    │  Cache Refresh  │
                    │  (if different) │
                    └─────────────────┘
```
