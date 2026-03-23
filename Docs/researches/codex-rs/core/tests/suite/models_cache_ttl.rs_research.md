# models_cache_ttl.rs 研究文档

## 场景与职责

`models_cache_ttl.rs` 是 Codex Core 集成测试套件中专注于**模型缓存 TTL（Time To Live）管理**的测试文件。该文件验证 `ModelsManager` 的缓存策略，确保：

1. **ETag 匹配时的 TTL 刷新**：当服务器返回的 `X-Models-Etag` 与缓存匹配时，刷新缓存的 `fetched_at` 时间戳，延长缓存有效期
2. **客户端版本匹配的缓存使用**：验证缓存中的 `client_version` 与当前客户端版本匹配时，直接使用缓存而不发起网络请求
3. **版本缺失时的刷新**：当缓存缺少 `client_version` 字段时，强制刷新缓存
4. **版本不匹配时的刷新**：当缓存的 `client_version` 与当前版本不一致时，强制刷新缓存

这些测试确保了 Codex 在离线/弱网环境下的可用性，同时保证模型元数据的及时更新。

## 功能点目的

### 测试用例矩阵

| 测试函数 | 目的 | 关键验证点 |
|----------|------|------------|
| `renews_cache_ttl_on_matching_models_etag` | ETag 匹配时刷新 TTL | 缓存 `fetched_at` 时间戳更新，`/models` 不再请求 |
| `uses_cache_when_version_matches` | 版本匹配时使用缓存 | 不发起 `/models` 请求，返回缓存模型 |
| `refreshes_when_cache_version_missing` | 版本缺失时刷新 | 发起 `/models` 请求，忽略过期缓存 |
| `refreshes_when_cache_version_differs` | 版本不匹配时刷新 | 发起 `/models` 请求，使用新数据 |

## 具体技术实现

### 关键数据结构

```rust
// 测试文件内定义的缓存结构 (models_cache_ttl.rs 行 306-314)
#[derive(Debug, Clone, Serialize, Deserialize)]
struct ModelsCache {
    fetched_at: DateTime<Utc>,      // 缓存获取时间，用于 TTL 计算
    #[serde(default)]
    etag: Option<String>,           // ETag，用于缓存验证
    #[serde(default)]
    client_version: Option<String>, // 客户端版本，用于兼容性检查
    models: Vec<ModelInfo>,         // 缓存的模型列表
}

// ModelsManager 中的刷新策略 (core/src/models_manager/manager.rs 行 138-147)
pub enum RefreshStrategy {
    Online,           // 始终从网络获取
    Offline,          // 仅使用缓存
    OnlineIfUncached, // 缓存存在且有效时使用缓存，否则网络获取
}
```

### 缓存 TTL 机制

```rust
// core/src/models_manager/manager.rs 行 42-44
const MODEL_CACHE_FILE: &str = "models_cache.json";
const DEFAULT_MODEL_CACHE_TTL: Duration = Duration::from_secs(300); // 5 分钟
```

缓存失效判断逻辑：
1. 检查 `fetched_at` + `TTL` 是否超过当前时间
2. 检查 `client_version` 是否与当前版本匹配
3. 检查是否需要强制刷新（`RefreshStrategy::Online`）

### ETag 刷新机制

当服务器在响应头中返回 `X-Models-Etag` 时：

1. **初始加载**：Codex 启动时从 `/models` 获取模型列表，保存 ETag
2. **后续响应**：`/responses` 等端点可能在响应头中返回 `X-Models-Etag`
3. **ETag 比较**：若响应 ETag 与缓存 ETag 匹配，刷新 `fetched_at` 为当前时间
4. **TTL 延长**：缓存有效期从新的 `fetched_at` 开始重新计算

```rust
// 测试流程 (models_cache_ttl.rs 行 44-135)
let stale_time = Utc.timestamp_opt(0, 0).single().expect("valid epoch");
rewrite_cache_timestamp(&cache_path, stale_time).await?;  // 将缓存设为过期

// 触发响应，服务器返回匹配的 ETag
let response_body = sse(vec![...]);
responses::mount_response_once(
    &server,
    sse_response(response_body).insert_header("X-Models-Etag", ETAG),
).await;

// 验证：缓存时间戳已更新
let refreshed_cache = read_cache(&cache_path).await?;
assert!(refreshed_cache.fetched_at > stale_time, "cache TTL should be renewed");
```

### 客户端版本检查

```rust
// core/src/models_manager/manager.rs
pub fn client_version_to_whole() -> String {
    // 将版本三元组转换为字符串，如 "0.62.0"
}
```

版本检查策略：
- 缓存无 `client_version`：视为不兼容，强制刷新
- 缓存 `client_version` ≠ 当前版本：视为不兼容，强制刷新
- 缓存 `client_version` = 当前版本：视为兼容，可使用缓存

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 功能描述 |
|------|----------|
| `codex-rs/core/src/models_manager/manager.rs` | `ModelsManager` 实现，缓存策略和刷新逻辑 |
| `codex-rs/core/src/models_manager/cache.rs` | 缓存文件读写和 TTL 管理 |
| `codex-rs/codex-api/src/sse/responses.rs` | 从 SSE 响应头中提取 `X-Models-Etag` |

### 测试支持文件

| 文件 | 用途 |
|------|------|
| `codex-rs/core/tests/common/responses.rs` | Mock 辅助函数（`mount_models_once_with_etag`, `mount_response_once`） |
| `codex-rs/core/tests/common/test_codex.rs` | `test_codex()` 构建器和测试环境设置 |

### 关键辅助函数

```rust
// models_cache_ttl.rs 行 281-304
async fn rewrite_cache_timestamp(path: &Path, fetched_at: DateTime<Utc>) -> Result<()> {
    let mut cache = read_cache(path).await?;
    cache.fetched_at = fetched_at;
    write_cache(path, &cache).await?;
    Ok(())
}

async fn read_cache(path: &Path) -> Result<ModelsCache> {
    let contents = tokio::fs::read(path).await?;
    let cache = serde_json::from_slice(&contents)?;
    Ok(cache)
}

async fn write_cache(path: &Path, cache: &ModelsCache) -> Result<()> {
    let contents = serde_json::to_vec_pretty(cache)?;
    tokio::fs::write(path, contents).await?;
    Ok(())
}
```

## 依赖与外部交互

### 外部依赖

- **chrono**: 日期时间处理，`DateTime<Utc>` 和 `TimeZone` trait
- **serde** / **serde_json**: 缓存结构的序列化/反序列化
- **wiremock**: HTTP Mock 服务器，模拟 `/models` 和 `/responses` 端点

### 协议常量

```rust
// models_cache_ttl.rs
const ETAG: &str = "\"models-etag-ttl\"";
const CACHE_FILE: &str = "models_cache.json";
const REMOTE_MODEL: &str = "codex-test-ttl";
```

### 测试模型构建

```rust
// models_cache_ttl.rs 行 316-357
fn test_remote_model(slug: &str, priority: i32) -> ModelInfo {
    ModelInfo {
        slug: slug.to_string(),
        display_name: "Remote Test".to_string(),
        description: Some("remote model".to_string()),
        supported_reasoning_levels: vec![...],
        shell_type: ConfigShellToolType::ShellCommand,
        visibility: ModelVisibility::List,
        supported_in_api: true,
        priority,
        // ... 其他字段使用默认值
    }
}
```

## 风险、边界与改进建议

### 当前风险

1. **时间敏感测试**：`renews_cache_ttl_on_matching_models_etag` 测试依赖时间比较，在极慢的系统上可能不稳定
2. **版本格式耦合**：测试假设 `client_version_to_whole()` 返回特定格式的字符串，若格式变更，测试可能失效
3. **并发修改风险**：测试直接操作文件系统缓存，若与其他测试并行运行可能产生冲突

### 边界情况

1. **ETag 格式**：测试使用 `"models-etag-ttl"`（带引号的 HTTP ETag 格式），验证服务器返回的原始格式处理
2. **空模型列表**：未测试缓存空模型列表的场景
3. **磁盘满/权限错误**：未测试缓存文件写入失败时的错误处理

### 改进建议

1. **添加并发测试**：验证多线程同时访问 `ModelsManager` 的缓存一致性
2. **测试缓存损坏恢复**：模拟缓存文件损坏（无效 JSON）时的行为
3. **参数化 TTL**：当前 TTL 是编译时常量，可考虑运行时配置，并添加相应测试
4. **添加性能测试**：验证大模型列表（1000+ 模型）下的缓存读写性能
5. **文档化缓存策略**：在 `models_manager/manager.rs` 中添加缓存策略的详细文档

### 相关测试文件

- `models_etag_responses.rs`: 测试 ETag 不匹配时的缓存刷新行为
- `remote_models.rs`: 测试远程模型列表获取的基础功能
- `client.rs` / `client_websockets.rs`: 测试不同传输方式下的模型管理

### 调试命令

```bash
# 运行本文件的所有测试
cargo test -p codex-core --test suite models_cache_ttl

# 查看缓存文件内容（测试后）
cat /tmp/codex-core-tests*/models_cache.json | jq .

# 带日志运行测试
RUST_LOG=codex_core::models_manager=debug cargo test -p codex-core --test suite models_cache_ttl
```
