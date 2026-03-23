# request_compression.rs 研究文档

## 场景与职责

`request_compression.rs` 是 Codex 核心测试套件中的集成测试文件，专门测试**HTTP 请求体压缩功能**。该文件验证当启用 `EnableRequestCompression` 特性时，Codex 客户端是否正确地使用 zstd 压缩算法压缩请求体，并在 HTTP 头中标识压缩格式。

测试场景覆盖：
- ChatGPT 认证模式下启用压缩时请求体被 zstd 压缩
- API Key 认证模式下即使启用压缩也不压缩请求体
- 压缩后请求体可正确解码并包含预期的 API 请求结构

## 功能点目的

### 1. 请求体压缩（zstd）
当 `Feature::EnableRequestCompression` 启用且使用 ChatGPT 认证时，Codex 应该：
- 使用 zstd 算法压缩请求体
- 添加 `Content-Encoding: zstd` HTTP 头
- 减少网络传输数据量，提高性能

### 2. 认证模式差异化处理
压缩行为应根据认证类型有所不同：
- **ChatGPT 认证**：启用压缩（后端支持）
- **API Key 认证**：禁用压缩（兼容性考虑）

### 3. 压缩数据完整性
验证压缩后的请求体：
- 可以被正确解码
- 解码后包含有效的 JSON 结构
- 包含预期的 API 请求字段（如 `input`）

## 具体技术实现

### 关键测试结构

```rust
#![cfg(not(target_os = "windows"))]

use codex_core::features::Feature;
use core_test_support::responses::{ev_completed, ev_response_created, mount_sse_once, sse, start_mock_server};
use core_test_support::{skip_if_no_network, test_codex::test_codex, wait_for_event};
```

### 测试用例 1：ChatGPT 认证启用压缩

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn request_body_is_zstd_compressed_for_codex_backend_when_enabled() -> anyhow::Result<()> {
    skip_if_no_network!(Ok(()));

    // 1. 启动 MockServer
    let server = start_mock_server().await;
    
    // 2. 挂载 SSE 响应（模拟后端响应）
    let request_log = mount_sse_once(
        &server,
        sse(vec![ev_response_created("resp-1"), ev_completed("resp-1")]),
    ).await;

    // 3. 配置 ChatGPT 认证和启用压缩
    let base_url = format!("{}/backend-api/codex/v1", server.uri());
    let mut builder = test_codex()
        .with_auth(CodexAuth::create_dummy_chatgpt_auth_for_testing())
        .with_config(move |config| {
            // 启用请求压缩特性
            config.features.enable(Feature::EnableRequestCompression)
                .expect("test config should allow feature update");
            config.model_provider.base_url = Some(base_url);
        });
    let codex = builder.build(&server).await?.codex;

    // 4. 提交用户输入
    codex.submit(Op::UserInput {
        items: vec![UserInput::Text { text: "compress me".into(), text_elements: Vec::new() }],
        final_output_json_schema: None,
    }).await?;

    // 5. 等待 TurnComplete 事件
    wait_for_event(&codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;

    // 6. 验证请求头包含 content-encoding: zstd
    let request = request_log.single_request();
    assert_eq!(request.header("content-encoding").as_deref(), Some("zstd"));

    // 7. 验证请求体可被 zstd 解码并包含有效 JSON
    let decompressed = zstd::stream::decode_all(std::io::Cursor::new(request.body_bytes()))?;
    let json: serde_json::Value = serde_json::from_slice(&decompressed)?;
    assert!(json.get("input").is_some(), "expected request body to decode as Responses API JSON");

    Ok(())
}
```

### 测试用例 2：API Key 认证禁用压缩

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn request_body_is_not_compressed_for_api_key_auth_even_when_enabled() -> anyhow::Result<()> {
    skip_if_no_network!(Ok(()));

    let server = start_mock_server().await;
    let request_log = mount_sse_once(
        &server,
        sse(vec![ev_response_created("resp-1"), ev_completed("resp-1")]),
    ).await;

    let base_url = format!("{}/backend-api/codex/v1", server.uri());
    let mut builder = test_codex()
        // 注意：未调用 .with_auth()，使用默认 API Key 认证
        .with_config(move |config| {
            config.features.enable(Feature::EnableRequestCompression)
                .expect("test config should allow feature update");
            config.model_provider.base_url = Some(base_url);
        });
    let codex = builder.build(&server).await?.codex;

    codex.submit(Op::UserInput {
        items: vec![UserInput::Text { text: "do not compress".into(), text_elements: Vec::new() }],
        final_output_json_schema: None,
    }).await?;

    wait_for_event(&codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;

    // 验证：API Key 认证下不压缩
    let request = request_log.single_request();
    assert!(request.header("content-encoding").is_none(), 
        "did not expect request compression for API-key auth");

    // 验证：请求体是明文 JSON
    let json: serde_json::Value = serde_json::from_slice(&request.body_bytes())?;
    assert!(json.get("input").is_some(), "expected request body to be plain Responses API JSON");

    Ok(())
}
```

### 核心特性配置

```rust
// codex-rs/core/src/features.rs
pub enum Feature {
    // ... 其他特性
    /// Compress request bodies (zstd) when sending streaming requests to codex-backend.
    EnableRequestCompression,
    // ...
}

pub const FEATURES: &[FeatureSpec] = &[
    // ...
    FeatureSpec {
        id: Feature::EnableRequestCompression,
        key: "enable_request_compression",
        stage: Stage::Stable,
        default_enabled: true,  // 默认启用
    },
    // ...
];
```

### 压缩实现路径

```rust
// codex-rs/core/src/codex.rs (约第 1820 行)
let client = StreamingClient::new(
    session_configuration.provider.clone(),
    session_configuration.session_source.clone(),
    config.model_verbosity,
    config.features.enabled(Feature::EnableRequestCompression), // 压缩开关
    config.features.enabled(Feature::RuntimeMetrics),
    Self::build_model_client_beta_features_header(config.as_ref()),
);
```

## 关键代码路径与文件引用

### 被测试的核心代码

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/codex.rs` | `Codex` 主结构，创建 `StreamingClient` 时传递压缩配置 |
| `codex-rs/core/src/streaming_client.rs` | 流式客户端，根据配置启用压缩 |
| `codex-rs/api/src/transport.rs` | HTTP 传输层，实际执行压缩和添加请求头 |

### 压缩检测逻辑（测试辅助）

```rust
// codex-rs/core/tests/common/responses.rs
fn is_zstd_encoding(value: &str) -> bool {
    value.split(',').any(|entry| entry.trim().eq_ignore_ascii_case("zstd"))
}

fn decode_body_bytes(body: &[u8], content_encoding: Option<&str>) -> Vec<u8> {
    if content_encoding.is_some_and(is_zstd_encoding) {
        zstd::stream::decode_all(std::io::Cursor::new(body)).unwrap_or_else(|err| {
            panic!("failed to decode zstd request body: {err}");
        })
    } else {
        body.to_vec()
    }
}
```

### 测试基础设施

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/common/responses.rs` | `ResponsesRequest::body_json()` 自动处理 zstd 解码 |
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodexBuilder` 测试构建器 |

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `zstd` crate | zstd 压缩/解压缩 |
| `wiremock::MockServer` | HTTP 模拟服务器 |
| `tokio` | 异步运行时 |

### 内部依赖模块

| 模块 | 用途 |
|-----|------|
| `codex_core::features::{Feature, Features}` | 特性开关管理 |
| `codex_core::CodexAuth` | 认证类型（ChatGPT vs API Key） |
| `codex_protocol::protocol::{Op, EventMsg}` | 操作和事件类型 |

### 认证类型检测

```rust
// codex-rs/core/src/auth.rs
impl CodexAuth {
    pub fn is_chatgpt_auth(&self) -> bool {
        matches!(self, CodexAuth::Chatgpt(_))
    }
    
    pub fn create_dummy_chatgpt_auth_for_testing() -> Self {
        // 创建测试用的 ChatGPT 认证
    }
}
```

## 风险、边界与改进建议

### 已知风险

1. **Windows 平台限制**
   - 文件顶部有 `#![cfg(not(target_os = "windows"))]`
   - 原因：UnifiedExec 和某些测试基础设施在 Windows 上不支持
   - 风险：Windows 平台的请求压缩功能缺乏测试覆盖

2. **硬编码后端路径**
   - 测试使用 `/backend-api/codex/v1` 路径
   - 如果后端 API 路径变更，测试需要同步更新

3. **认证类型耦合**
   - 压缩行为与认证类型紧密耦合
   - 新增认证类型时需要明确是否启用压缩

### 边界情况

1. **空请求体**
   - 当前测试未覆盖空请求体场景
   - zstd 对空数据的处理需要验证

2. **大请求体**
   - 未测试大请求体的压缩性能和内存使用
   - 可能需要流式压缩而非一次性压缩

3. **压缩失败回退**
   - 未测试 zstd 压缩失败时的回退行为
   - 应该回退到未压缩还是报错？

### 改进建议

1. **增加 Windows 测试**
   - 分离平台无关的压缩逻辑测试
   - 使用条件编译而非整个文件排除

2. **增加边界测试**
   ```rust
   // 建议添加：
   - test_empty_body_compression
   - test_large_body_compression
   - test_compression_failure_fallback
   - test_mixed_content_encoding (zstd + other)
   ```

3. **性能基准测试**
   - 添加压缩率基准测试
   - 添加压缩/解压性能基准测试

4. **配置灵活性**
   - 考虑允许按端点配置压缩（某些端点可能不需要压缩）
   - 允许配置压缩级别（速度 vs 压缩率权衡）

5. **监控和可观测性**
   - 添加压缩率指标（原始大小 vs 压缩后大小）
   - 在日志中记录压缩决策（为什么压缩/不压缩）

6. **文档完善**
   - 在配置文档中说明压缩与认证类型的关系
   - 说明压缩对性能的影响（CPU vs 网络）
