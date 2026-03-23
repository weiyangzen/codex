# search_tool.rs 研究文档

## 场景与职责

`search_tool.rs` 是 Codex Core 的测试文件，专注于验证 **Apps/Connectors 工具搜索功能**。在 Codex 架构中，当启用 Apps 功能时，系统会暴露大量 MCP 工具（如日历、邮件等）。为避免向模型一次性暴露过多工具，引入了 `tool_search` 机制：

- **延迟加载**：默认隐藏 Apps 工具，仅暴露 `tool_search` 工具
- **动态发现**：模型可通过 `tool_search` 查询需要的工具
- **按需注入**：根据搜索结果，动态将工具添加到对话上下文

本测试验证这一完整流程的正确性。

## 功能点目的

### 1. 搜索工具标志添加 (`search_tool_flag_adds_tool_search`)
验证当模型支持搜索工具时，`tool_search` 被正确添加到工具列表：
- 启用 Apps 功能（`Feature::Apps`）
- 配置模型支持搜索（`supports_search_tool: true`）
- 验证请求体中包含 `tool_search` 工具
- 验证工具定义包含正确的参数（`query`, `limit`）

### 2. API Key 认证隐藏 (`search_tool_is_hidden_for_api_key_auth`)
验证使用 API Key 认证时，不暴露 `tool_search`：
- Apps 功能需要 ChatGPT 认证
- API Key 认证应禁用 Apps 相关功能

### 3. 搜索工具描述 (`search_tool_adds_discovery_instructions_to_tool_description`)
验证 `tool_search` 的描述包含正确的使用说明：
- 包含 "You have access to all the tools of the following apps/connectors"
- 列出可用连接器（如 Calendar）
- 不包含已弃用的客户端持久化说明

### 4. 默认隐藏 Apps 工具 (`search_tool_hides_apps_tools_without_search`)
验证默认情况下 Apps 工具被隐藏：
- `tool_search` 存在
- `calendar_create_event` 和 `calendar_list_events` 不存在

### 5. 显式提及暴露工具 (`explicit_app_mentions_expose_apps_tools_without_search`)
验证当用户消息显式提及 App（如 `[$calendar](app://calendar)`）时，直接暴露相关工具：
- 无需调用 `tool_search`
- 相关 Calendar 工具直接出现在工具列表

### 6. 延迟工具返回 (`tool_search_returns_deferred_tools_without_follow_up_tool_injection`)
验证完整的工具搜索和执行流程：
- 第一轮：模型调用 `tool_search`，返回延迟加载的 Calendar 工具
- 第二轮：模型使用返回的工具调用 `calendar_create_event`
- 验证后续请求不重复注入已发现的工具

## 具体技术实现

### 关键数据结构

```rust
// 工具搜索输出（来自 codex_core::tools::handlers::tool_search）
pub struct ToolSearchOutput {
    pub tools: Vec<ToolSearchOutputTool>,
}

pub enum ToolSearchOutputTool {
    Namespace(ResponsesApiNamespace),  // 按命名空间分组
}

pub struct ResponsesApiNamespace {
    pub name: String,                   // 如 "mcp__codex_apps__calendar"
    pub description: String,
    pub tools: Vec<ResponsesApiNamespaceTool>,
}
```

### 工具搜索流程

```
用户输入: "Find the calendar create tool"
  └─ 模型决定调用 tool_search
       ├─ 参数: {"query": "create calendar event", "limit": 1}
       ├─ 后端执行 BM25 搜索
       │    ├─ 构建搜索文档（工具名、描述、连接器名等）
       │    └─ 返回匹配工具
       └─ 返回 ToolSearchOutput
            └─ 包含延迟加载的工具定义

模型看到搜索结果
  └─ 决定调用 calendar_create_event
       ├─ 工具已存在于对话历史的 tool_search_output 中
       └─ 无需额外工具注入
```

### BM25 搜索实现

```rust
// codex_core::tools::handlers::tool_search
fn build_search_text(name: &str, info: &ToolInfo) -> String {
    let mut parts = vec![
        name.to_string(),
        info.tool_name.clone(),
        info.server_name.clone(),
    ];
    // 添加标题、描述、连接器名、参数名等
    parts.join(" ")
}

// 使用 bm25 crate
let documents: Vec<Document<usize>> = entries
    .iter()
    .enumerate()
    .map(|(idx, (name, info))| Document::new(idx, build_search_text(name, info)))
    .collect();
let search_engine = SearchEngineBuilder::<usize>::with_documents(Language::English, documents).build();
let results = search_engine.search(query, limit);
```

### 测试配置

```rust
fn configure_apps(config: &mut Config, apps_base_url: &str) {
    config.features.enable(Feature::Apps).unwrap();
    config.chatgpt_base_url = apps_base_url.to_string();
    config.model = Some("gpt-5-codex".to_string());
    
    // 修改模型目录以支持搜索工具
    let mut model_catalog: ModelsResponse = ...;
    model.supports_search_tool = true;
    config.model_catalog = Some(model_catalog);
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_core::tools::handlers::tool_search` | 工具搜索实现 |
| `codex_core::features::Feature` | 功能开关 |
| `codex_core::mcp_connection_manager` | MCP 工具列表获取 |
| `codex_protocol::openai_models::ModelsResponse` | 模型目录 |

### 外部依赖

| 组件 | 用途 |
|------|------|
| `bm25` crate | BM25 文本搜索算法 |
| `AppsTestServer` | 模拟 Apps 后端服务 |

### 测试辅助

```rust
// Apps 测试服务器
let apps_server = AppsTestServer::mount_searchable(&server).await?;

// 工具名称提取
fn tool_names(body: &Value) -> Vec<String> { ... }

// 搜索工具描述提取
fn tool_search_description(body: &Value) -> Option<String> { ... }
```

## 风险、边界与改进建议

### 当前风险

1. **搜索质量**：BM25 基于词频，可能返回不相关结果
2. **性能问题**：工具数量增加时，搜索和序列化开销增大
3. **缓存缺失**：每次请求都重新构建搜索索引

### 边界情况

1. **空查询**：空字符串查询的处理
2. **零限制**：`limit: 0` 的处理
3. **大量工具**：>1000 个工具时的性能和准确性
4. **多语言**：非英语工具描述和查询的处理

### 改进建议

1. **搜索算法优化**：
   - 添加语义搜索（向量相似度）
   - 支持同义词扩展
   - 添加工具使用频率作为排序因子

2. **性能优化**：
   - 预构建并缓存搜索索引
   - 使用增量更新而非全量重建
   - 异步加载工具定义

3. **用户体验**：
   - 添加搜索建议/自动完成
   - 显示工具使用示例
   - 支持自然语言描述（"帮我安排会议" → calendar 工具）

4. **测试扩展**：
   - 测试搜索结果排序准确性
   - 测试并发搜索请求
   - 测试工具定义序列化性能

5. **可观测性**：
   - 记录搜索查询和点击率
   - 监控搜索延迟
   - 分析零结果查询

### 相关文件引用

- `codex-rs/core/src/tools/handlers/tool_search.rs` - 工具搜索实现
- `codex-rs/core/src/tools/handlers/tool_search_tests.rs` - 单元测试
- `codex-rs/core/src/mcp/mod.rs` - MCP 工具管理
- `codex-rs/core/src/connectors.rs` - 连接器管理
- `codex-rs/core/tests/common/apps_test_server.rs` - 测试用的 Apps 服务器
