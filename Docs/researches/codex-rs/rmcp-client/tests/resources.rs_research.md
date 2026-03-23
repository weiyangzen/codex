# resources.rs 研究文档

## 场景与职责

`resources.rs` 是 `codex-rmcp-client` crate 的集成测试文件，专注于验证 **MCP (Model Context Protocol) 客户端的资源管理功能**。该测试验证客户端通过 stdio 传输与 MCP 服务器交互时，能够正确列出、读取资源以及处理资源模板。

### 测试目标
- 验证 `RmcpClient` 的资源发现能力（`list_resources`）
- 验证资源模板枚举（`list_resource_templates`）
- 验证资源内容读取（`read_resource`）
- 验证 MCP 初始化握手流程（`initialize`）
- 验证 elicitation（交互式确认）流程的处理

## 功能点目的

### 1. 资源发现与访问
MCP 协议允许服务器暴露资源（如文件、内存数据、API 响应等），客户端需要能够：
- 发现可用资源列表
- 理解资源模板（URI 模板模式）
- 读取特定资源的内容

### 2. Elicitation 支持
Elicitation 是 MCP 协议中的交互式确认机制，用于：
- 请求用户确认敏感操作
- 收集额外的输入参数
- 实现人机交互流程

### 3. 测试服务器集成
测试使用 `test_stdio_server` 二进制作为 MCP 服务器，该服务器：
- 通过 stdio 传输与客户端通信
- 提供预定义的工具和资源
- 支持 elicitation 能力协商

## 具体技术实现

### 测试流程

```
测试启动
    │
    ▼
定位 test_stdio_server 二进制
    │
    ▼
创建 RmcpClient（stdio 传输）
    │
    ▼
初始化 MCP 连接
    ├─ 发送 InitializeRequest
    ├─ 协商协议版本 (V_2025_06_18)
    ├─ 声明客户端能力（包括 elicitation）
    └─ 提供 elicitation 回调处理
    │
    ▼
列出资源
    ├─ 调用 list_resources
    ├─ 验证返回资源列表
    └─ 验证特定资源（memo://codex/example-note）存在
    │
    ▼
列出资源模板
    ├─ 调用 list_resource_templates
    └─ 验证模板 URI 模式（memo://codex/{slug}）
    │
    ▼
读取资源
    ├─ 调用 read_resource
    └─ 验证返回内容匹配预期
    │
    ▼
测试完成
```

### 初始化参数配置

```rust
fn init_params() -> InitializeRequestParams {
    InitializeRequestParams {
        meta: None,
        capabilities: ClientCapabilities {
            experimental: None,
            extensions: None,
            roots: None,
            sampling: None,
            elicitation: Some(ElicitationCapability {
                form: Some(FormElicitationCapability {
                    schema_validation: None,
                }),
                url: None,
            }),
            tasks: None,
        },
        client_info: Implementation {
            name: "codex-test".into(),
            version: "0.0.0-test".into(),
            title: Some("Codex rmcp resource test".into()),
            description: None,
            icons: None,
            website_url: None,
        },
        protocol_version: ProtocolVersion::V_2025_06_18,
    }
}
```

### Elicitation 回调

```rust
Box::new(|_, _| {
    async {
        Ok(ElicitationResponse {
            action: ElicitationAction::Accept,
            content: Some(json!({})),
            meta: None,
        })
    }
    .boxed()
})
```

- 自动接受所有 elicitation 请求
- 返回空的 JSON 对象作为内容
- 使用 `futures::FutureExt::boxed()` 将异步块转换为 `BoxFuture`

### 资源验证

#### 资源列表验证
```rust
let list = client.list_resources(None, Some(Duration::from_secs(5))).await?;
let memo = list.resources.iter()
    .find(|resource| resource.uri == RESOURCE_URI)
    .expect("memo resource present");
assert_eq!(memo, &rmcp::model::RawResource {
    uri: RESOURCE_URI.to_string(),
    name: "example-note".to_string(),
    title: Some("Example Note".to_string()),
    description: Some("A sample MCP resource exposed for integration tests.".to_string()),
    mime_type: Some("text/plain".to_string()),
    size: None,
    icons: None,
    meta: None,
}.no_annotation());
```

#### 资源模板验证
```rust
let templates = client.list_resource_templates(None, Some(Duration::from_secs(5))).await?;
assert_eq!(templates, ListResourceTemplatesResult {
    meta: None,
    next_cursor: None,
    resource_templates: vec![
        rmcp::model::RawResourceTemplate {
            uri_template: "memo://codex/{slug}".to_string(),
            name: "codex-memo".to_string(),
            title: Some("Codex Memo".to_string()),
            description: Some("Template for memo://codex/{slug} resources used in tests.".to_string()),
            mime_type: Some("text/plain".to_string()),
            icons: None,
        }.no_annotation()
    ],
});
```

#### 资源内容验证
```rust
let read = client.read_resource(
    ReadResourceRequestParams {
        meta: None,
        uri: RESOURCE_URI.to_string(),
    },
    Some(Duration::from_secs(5)),
).await?;
let text = read.contents.first().expect("resource contents present");
assert_eq!(text, &ResourceContents::TextResourceContents {
    uri: RESOURCE_URI.to_string(),
    mime_type: Some("text/plain".to_string()),
    text: "This is a sample MCP resource served by the rmcp test server.".to_string(),
    meta: None,
});
```

## 关键代码路径与文件引用

### 被测试代码

| 文件 | 相关组件 | 说明 |
|------|----------|------|
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `RmcpClient::list_resources()` | 列出可用资源 |
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `RmcpClient::list_resource_templates()` | 列出资源模板 |
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `RmcpClient::read_resource()` | 读取资源内容 |
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `RmcpClient::initialize()` | MCP 初始化握手 |
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `run_service_operation()` | 通用服务操作执行 |

### 测试服务器

| 文件 | 说明 |
|------|------|
| `codex-rs/rmcp-client/src/bin/test_stdio_server.rs` | stdio 传输的测试 MCP 服务器 |

### 测试服务器资源实现

```rust
// test_stdio_server.rs 第 166-191 行
fn memo_resource() -> Resource {
    let raw = RawResource {
        uri: MEMO_URI.to_string(),  // "memo://codex/example-note"
        name: "example-note".to_string(),
        title: Some("Example Note".to_string()),
        description: Some("A sample MCP resource exposed for integration tests.".to_string()),
        mime_type: Some("text/plain".to_string()),
        size: None,
        icons: None,
        meta: None,
    };
    Resource::new(raw, None)
}

fn memo_template() -> ResourceTemplate {
    let raw = RawResourceTemplate {
        uri_template: "memo://codex/{slug}".to_string(),
        name: "codex-memo".to_string(),
        title: Some("Codex Memo".to_string()),
        description: Some("Template for memo://codex/{slug} resources used in tests.".to_string()),
        mime_type: Some("text/plain".to_string()),
        icons: None,
    };
    ResourceTemplate::new(raw, None)
}
```

### 资源读取实现

```rust
// test_stdio_server.rs 第 286-306 行
async fn read_resource(
    &self,
    ReadResourceRequestParams { uri, .. }: ReadResourceRequestParams,
    _context: rmcp::service::RequestContext<rmcp::service::RoleServer>,
) -> Result<ReadResourceResult, McpError> {
    if uri == MEMO_URI {
        Ok(ReadResourceResult {
            contents: vec![ResourceContents::TextResourceContents {
                uri,
                mime_type: Some("text/plain".to_string()),
                text: Self::memo_text().to_string(),
                meta: None,
            }],
        })
    } else {
        Err(McpError::resource_not_found(
            "resource_not_found",
            Some(json!({ "uri": uri })),
        ))
    }
}
```

## 依赖与外部交互

### 直接依赖

| 依赖 | 用途 |
|------|------|
| `tokio` | 异步运行时和测试框架 |
| `anyhow` | 错误处理 |
| `serde_json` | JSON 序列化/反序列化 |
| `futures` | 异步工具（`FutureExt::boxed()`） |
| `rmcp` | MCP 协议模型和运行时 |
| `codex_rmcp_client::RmcpClient` | 被测试的客户端 |
| `codex_utils_cargo_bin` | 定位测试二进制 |

### MCP 协议模型

| 类型 | 来源 | 用途 |
|------|------|------|
| `InitializeRequestParams` | `rmcp::model` | 初始化请求参数 |
| `ClientCapabilities` | `rmcp::model` | 客户端能力声明 |
| `ElicitationCapability` | `rmcp::model` | 交互式确认能力 |
| `ListResourceTemplatesResult` | `rmcp::model` | 资源模板列表结果 |
| `ReadResourceRequestParams` | `rmcp::model` | 读取资源请求参数 |
| `ResourceContents` | `rmcp::model` | 资源内容类型 |
| `ProtocolVersion::V_2025_06_18` | `rmcp::model` | 协议版本 |

### 测试基础设施

```rust
fn stdio_server_bin() -> Result<PathBuf, CargoBinError> {
    codex_utils_cargo_bin::cargo_bin("test_stdio_server")
}
```

- 使用 `codex_utils_cargo_bin` 定位测试二进制
- 支持 Cargo 和 Bazel 两种构建环境
- 通过 `CARGO_BIN_EXE_*` 环境变量或 runfiles 解析路径

## 风险、边界与改进建议

### 潜在风险

1. **测试服务器可用性**
   - 如果 `test_stdio_server` 二进制未构建，测试将失败
   - 缓解：`codex_utils_cargo_bin` 提供清晰的错误信息

2. **超时配置**
   - 硬编码 5 秒超时可能在慢速环境（如 CI）中不足
   - 建议：使用环境变量允许调整超时

3. **并发执行**
   - `worker_threads = 1` 限制了并发，但确保测试隔离
   - 多测试并行时可能产生资源竞争

### 边界情况

| 场景 | 当前处理 | 建议 |
|------|----------|------|
| 服务器启动失败 | 返回错误 | 添加重试机制 |
| 初始化超时 | 测试失败 | 可配置超时 |
| 资源不存在 | 未测试 | 添加错误处理测试 |
| 二进制版本不匹配 | 未检测 | 添加版本检查 |

### 改进建议

1. **参数化测试**
   ```rust
   // 建议：使用 rstest 参数化测试不同资源
   #[rstest]
   #[case("memo://codex/example-note", "text/plain")]
   #[case("memo://codex/other", "text/plain")]
   async fn test_read_resource(#[case] uri: &str, #[case] mime: &str) { ... }
   ```

2. **错误场景覆盖**
   - 添加测试：资源不存在时的错误处理
   - 添加测试：服务器返回无效数据时的行为
   - 添加测试：网络/传输错误恢复

3. **性能基准**
   - 测量资源列表和读取的延迟
   - 建立性能回归检测基线

4. **资源类型扩展**
   - 当前仅测试文本资源
   - 建议添加二进制资源测试
   - 建议添加多部分内容测试

5. **并发访问测试**
   ```rust
   // 建议：测试并发资源访问
   async fn concurrent_resource_access() {
       let client = create_client().await;
       let f1 = client.read_resource(...);
       let f2 = client.read_resource(...);
       let (r1, r2) = tokio::join!(f1, f2);
   }
   ```

6. **动态超时配置**
   ```rust
   // 建议：从环境变量读取超时
   fn test_timeout() -> Duration {
       std::env::var("TEST_TIMEOUT_SECS")
           .ok()
           .and_then(|s| s.parse().ok())
           .map(Duration::from_secs)
           .unwrap_or(Duration::from_secs(5))
   }
   ```

### 相关测试文件

- `codex-rs/rmcp-client/tests/process_group_cleanup.rs` - 进程清理测试
- `codex-rs/rmcp-client/tests/streamable_http_recovery.rs` - HTTP 传输恢复测试
- `codex-rs/core/tests/suite/rmcp_client.rs` - 核心 crate 的 MCP 客户端测试
