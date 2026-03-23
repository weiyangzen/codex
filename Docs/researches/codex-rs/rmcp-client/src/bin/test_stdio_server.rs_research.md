# test_stdio_server.rs 研究文档

## 场景与职责

`test_stdio_server.rs` 是 Codex 项目中功能最全面的 MCP (Model Context Protocol) STDIO 测试服务器。它作为 `codex-rmcp-client` crate 的二进制目标，主要用于：

1. **资源管理测试**：提供 MCP 资源（Resources）和资源模板（Resource Templates）的完整实现
2. **图片工具测试**：支持图片内容返回，用于测试 TUI 的图片渲染能力
3. **复杂场景测试**：提供多种图片场景（`image_scenario` 工具）用于边界情况测试
4. **工具命名边界测试**：包含带连字符的工具名（`echo-tool`）测试非 JS 合法标识符的处理

该服务器是 `codex-rs/rmcp-client/tests/resources.rs` 的主要测试依赖，也是 `codex-rs/core/tests/suite/rmcp_client.rs` 中图片相关测试的基础。

## 功能点目的

### 1. 多工具支持

| 工具名 | 用途 | 测试场景 |
|--------|------|----------|
| `echo` | 基础回显 | 标准工具调用测试 |
| `echo-tool` | 带连字符的工具名 | 测试非 JS 合法标识符处理 |
| `image` | 返回图片内容 | 图片渲染测试 |
| `image_scenario` | 多种图片场景 | TUI 图片处理边界测试 |

### 2. 资源系统

- **静态资源**：`memo://codex/example-note` - 文本资源
- **资源模板**：`memo://codex/{slug}` - 动态资源 URI 模板
- **用途**：测试 MCP 客户端的资源发现、读取能力

### 3. 图片场景测试（image_scenario）

专门用于测试 Codex TUI 对 MCP 图片输出的处理：

| 场景 | 描述 | TUI 预期行为 |
|------|------|--------------|
| `image_only` | 仅图片内容 | 显示图片输出单元格 |
| `text_then_image` | 文本后接图片 | 检测到图片后显示图片单元格 |
| `invalid_base64_then_image` | 无效 base64 + 有效图片 | 跳过无效，显示有效图片 |
| `invalid_image_bytes_then_image` | 无效图片字节 + 有效图片 | 跳过无效，显示有效图片 |
| `multiple_valid_images` | 多个有效图片 | 显示图片单元格 |
| `image_then_text` | 图片后接文本 | 显示图片单元格 |
| `text_only` | 仅文本 | 不显示图片单元格 |

### 4. 环境变量支持

- `MCP_TEST_VALUE`：通用测试值传播
- `MCP_TEST_IMAGE_DATA_URL`：图片工具的数据 URL 输入

## 具体技术实现

### 关键数据结构

```rust
#[derive(Clone)]
struct TestToolServer {
    tools: Arc<Vec<Tool>>,
    resources: Arc<Vec<Resource>>,
    resource_templates: Arc<Vec<ResourceTemplate>>,
}

// 图片场景枚举
#[derive(Deserialize, Debug)]
#[serde(rename_all = "snake_case")]
enum ImageScenario {
    ImageOnly,
    TextThenImage,
    InvalidBase64ThenImage,
    InvalidImageBytesThenImage,
    MultipleValidImages,
    ImageThenText,
    TextOnly,
}

#[derive(Deserialize, Debug)]
struct ImageScenarioArgs {
    scenario: ImageScenario,
    caption: Option<String>,
    data_url: Option<String>,
}
```

### 内置测试数据

```rust
const MEMO_URI: &str = "memo://codex/example-note";
const MEMO_CONTENT: &str = "This is a sample MCP resource served by the rmcp test server.";

// 1x1 像素的透明 PNG（base64 编码）
const SMALL_PNG_BASE64: &str = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==";
```

### ServerHandler 实现

实现了完整的 `ServerHandler` trait：

1. **`get_info`**：声明能力
   - 工具支持
   - 工具列表变更通知
   - 资源支持

2. **`list_tools`**：返回 4 个工具的定义

3. **`list_resources`**：返回静态资源列表

4. **`list_resource_templates`**：返回资源模板列表

5. **`read_resource`**：读取 `memo://codex/example-note` 资源内容

6. **`call_tool`**：处理工具调用，分发到具体实现

### 图片场景实现

```rust
fn image_scenario_result(args: ImageScenarioArgs) -> Result<CallToolResult, McpError> {
    let (mime_type, valid_data_b64) = // 解析 data_url 或使用默认 PNG
    
    let mut content = Vec::new();
    match args.scenario {
        ImageScenario::TextThenImage => {
            content.push(rmcp::model::Content::text(caption));
            content.push(rmcp::model::Content::image(valid_data_b64, mime_type));
        }
        ImageScenario::InvalidBase64ThenImage => {
            content.push(rmcp::model::Content::image("not-base64".to_string(), ...));
            content.push(rmcp::model::Content::image(valid_data_b64, mime_type));
        }
        // ... 其他场景
    }
    Ok(CallToolResult::success(content))
}
```

### 辅助函数

```rust
// 解析 data URL: data:image/png;base64,AAAA...
fn parse_data_url(url: &str) -> Option<(String, String)> {
    let rest = url.strip_prefix("data:")?;
    let (mime_and_opts, data) = rest.split_once(',')?;
    let (mime, _opts) = mime_and_opts.split_once(';').unwrap_or((mime_and_opts, ""));
    Some((mime.to_string(), data.to_string()))
}

// 通用参数解析
fn parse_call_args<T: for<'de> Deserialize<'de>>(
    request: &CallToolRequestParams,
    tool_name: &'static str,
) -> Result<T, McpError> { ... }
```

## 关键代码路径与文件引用

### 当前文件
- **路径**：`codex-rs/rmcp-client/src/bin/test_stdio_server.rs`
- **行数**：470 行

### 调用方（测试代码）

1. **资源测试**
   - 文件：`codex-rs/rmcp-client/tests/resources.rs`
   - 功能：测试资源列表、模板列表、资源读取
   - 使用方式：`codex_utils_cargo_bin::cargo_bin("test_stdio_server")`

2. **核心集成测试（图片相关）**
   - 文件：`codex-rs/core/tests/suite/rmcp_client.rs`
   - 测试函数：
     - `stdio_image_responses_round_trip` (行 196-374)
     - `stdio_image_responses_are_sanitized_for_text_only_model` (行 376-540)

3. **TUI 图片渲染测试**
   - 文件：`codex-rs/tui/src/history_cell.rs` 和 `codex-rs/tui_app_server/src/history_cell.rs`
   - 注释中引用了 `image_scenario` 工具的使用方法

### 工具注册示例（来自注释）

```bash
# 构建
cargo build -p codex-rmcp-client --bin test_stdio_server

# 注册到 Codex
codex mcp add mcpimg -- /abs/path/to/test_stdio_server

# 测试各种场景
codex mcpimg.image_scenario({"scenario":"image_only"})
codex mcpimg.image_scenario({"scenario":"text_then_image","caption":"Here is the image:"})
codex mcpimg.image_scenario({"scenario":"invalid_base64_then_image"})
```

## 依赖与外部交互

### 编译依赖

```toml
[dependencies]
rmcp = { workspace = true, features = ["server", "transport-child-process", ...] }
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
tokio = { workspace = true, features = ["io-std", "time", ...] }
```

### 运行时环境变量

| 变量名 | 用途 | 示例值 |
|--------|------|--------|
| `MCP_TEST_VALUE` | echo 工具回显 | `"ECHOING: xxx"` |
| `MCP_TEST_IMAGE_DATA_URL` | image 工具输入 | `data:image/png;base64,AAA...` |

### 输入输出

- **输入**：STDIN 接收 MCP JSON-RPC 消息
- **输出**：STDOUT 发送 MCP JSON-RPC 响应
- **日志**：STDERR 输出 `"starting rmcp test server"`

## 风险、边界与改进建议

### 当前风险

1. **硬编码图片数据**：`SMALL_PNG_BASE64` 是固定的 1x1 透明 PNG，无法测试不同格式的图片
2. **资源硬编码**：仅支持单个静态资源和模板
3. **错误场景有限**：图片场景仅覆盖部分边界情况

### 边界情况

1. **参数验证**：
   - `image_scenario` 的 scenario 字段使用枚举验证
   - 无效 scenario 返回反序列化错误
   - `data_url` 可选，省略时使用内置 PNG

2. **资源读取**：
   - 仅 `memo://codex/example-note` 返回成功
   - 其他 URI 返回 `resource_not_found` 错误

3. **图片数据处理**：
   - `parse_data_url` 仅支持简单 data URL 格式
   - 不支持复杂 MIME 类型参数

### 改进建议

1. **功能扩展**：
   - 支持从文件系统动态加载图片用于测试
   - 添加更多资源类型（二进制资源、大文本资源）
   - 支持动态资源模板匹配

2. **配置化**：
   - 通过环境变量或配置文件控制可用工具
   - 支持运行时注册/注销工具（测试工具列表变更通知）

3. **测试覆盖**：
   - 添加更多图片场景（如超大图片、损坏图片）
   - 添加并发工具调用测试
   - 添加长时间运行的工具测试（超时处理）

4. **文档**：
   - 添加 README.md 说明手动测试方法
   - 记录每个工具的预期输入输出格式

5. **代码质量**：
   - 考虑将 `parse_data_url` 提取为公共工具函数
   - 图片场景逻辑可提取到独立模块

### 相关测试覆盖

| 测试文件 | 测试函数 | 覆盖功能 |
|----------|----------|----------|
| `resources.rs` | `rmcp_client_can_list_and_read_resources` | 资源列表、模板、读取 |
| `rmcp_client.rs` | `stdio_image_responses_round_trip` | 图片工具调用 |
| `rmcp_client.rs` | `stdio_image_responses_are_sanitized_for_text_only_model` | 图片清理 |

### 维护建议

该文件是 MCP 测试基础设施的核心组件，修改时需注意：

1. 保持向后兼容（工具 schema 变更需同步更新测试）
2. 新增工具需在注释中说明手动测试方法
3. 图片场景变更需同步更新 TUI 测试预期
