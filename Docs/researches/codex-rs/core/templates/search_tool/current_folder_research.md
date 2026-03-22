# search_tool 模板目录研究文档

## 1. 场景与职责

### 1.1 目录定位
`codex-rs/core/templates/search_tool/` 目录包含 **Apps/Connectors 工具发现功能** 的模板文件，是 Codex CLI 中用于支持 AI 模型动态发现和加载外部应用（Apps/Connectors）工具的关键组件。

### 1.2 核心场景
该目录服务于以下核心场景：

1. **工具懒加载（Lazy Loading）**：当用户需要使用 ChatGPT Apps/Connectors 提供的工具时，模型可以通过 `tool_search` 工具搜索并发现可用的工具，而不是一次性暴露所有工具。

2. **工具发现与建议**：
   - `tool_search`：基于 BM25 算法搜索已安装 Apps 的工具
   - `tool_suggest`：当搜索失败时，建议用户安装或启用可发现的 Connectors 或 Plugins

3. **减少上下文开销**：避免在每次对话开始时就将所有 App 工具暴露给模型，只在需要时通过搜索动态加载。

### 1.3 与 Apps/Connectors 的关系
- Apps（Connectors）通过 MCP（Model Context Protocol）服务器 `codex_apps` 提供工具
- `tool_search` 允许模型搜索这些工具，而不是直接列出所有工具
- 这与传统的 `list_mcp_resources` 不同，提供了更智能的工具发现机制

---

## 2. 功能点目的

### 2.1 模板文件说明

#### `tool_description.md`
**目的**：定义 `tool_search` 工具的描述，指导 AI 模型如何使用工具搜索功能。

**关键内容**：
```markdown
# Apps (Connectors) tool discovery

Searches over apps/connectors tool metadata with BM25 and exposes matching tools for the next model call.

You have access to all the tools of the following apps/connectors:
{{app_descriptions}}
Some of the tools may not have been provided to you upfront, and you should use this tool (`tool_search`) to search for the required tools and load them for the apps mentioned above.
```

**功能要点**：
- 使用 BM25 算法进行工具元数据搜索
- 动态注入可用 App 列表（`{{app_descriptions}}` 占位符）
- 明确指导模型在何时使用 `tool_search`
- 强调对于上述 Apps，始终使用 `tool_search` 而非 `list_mcp_resources`

#### `tool_suggest_description.md`
**目的**：定义 `tool_suggest` 工具的描述，指导 AI 模型在找不到合适工具时建议用户安装新工具。

**关键内容**：
```markdown
# Tool suggestion discovery

Suggests a discoverable connector or plugin when the user clearly wants a capability that is not currently available in the active `tools` list.

Use this ONLY when:
- There's no available tool to handle the user's request
- And tool_search fails to find a good match
- AND the user's request strongly matches one of the discoverable tools listed below.
```

**功能要点**：
- 仅在特定条件下使用（无可用工具、搜索失败、匹配可发现工具）
- 支持 Connector 和 Plugin 两种类型
- 支持 `install` 和 `enable` 两种操作
- 提供可发现工具列表（`{{discoverable_tools}}` 占位符）
- 定义完整的工作流程：匹配 → 建议 → 后续处理

### 2.2 功能对比

| 功能 | tool_search | tool_suggest |
|------|-------------|--------------|
| **目的** | 搜索已安装 Apps 的工具 | 建议安装/启用新工具 |
| **使用时机** | 知道有某个工具但不在当前上下文 | 完全找不到合适工具时 |
| **数据来源** | 已安装的 Apps/Connectors | 可发现的 Connectors/Plugins |
| **操作结果** | 返回匹配的工具列表 | 触发安装/启用流程 |
| **算法** | BM25 文本搜索 | 精确匹配 ID |

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 Tool Search 执行流程

```
1. 模型调用 tool_search
   ↓
2. ToolRouter::build_tool_call 解析 ToolSearchCall
   ↓
3. ToolSearchHandler::handle 执行搜索
   a. 解析参数 (query, limit)
   b. 使用 BM25 算法搜索工具元数据
   c. 按 namespace 分组结果
   d. 序列化为 ToolSearchOutputTool
   ↓
4. 返回 ToolSearchOutput 给模型
   ↓
5. 模型根据搜索结果调用具体工具
```

**代码路径**：
- 调用入口：`codex-rs/core/src/tools/router.rs:149-167`
- 处理实现：`codex-rs/core/src/tools/handlers/tool_search.rs:43-98`

#### 3.1.2 Tool Suggest 执行流程

```
1. 模型调用 tool_suggest
   ↓
2. ToolSuggestHandler::handle 处理
   a. 解析参数 (tool_type, action_type, tool_id, suggest_reason)
   b. 验证工具在可发现列表中
   c. 构建 MCP Server Elicitation 请求
   d. 发送给用户确认
   ↓
3. 用户确认后
   a. 刷新工具缓存
   b. 验证工具是否可用
   c. 返回 ToolSuggestResult
```

**代码路径**：
- 处理实现：`codex-rs/core/src/tools/handlers/tool_suggest.rs:75-191`

### 3.2 关键数据结构

#### 3.2.1 ToolSpec（工具规范）

```rust
// codex-rs/core/src/client_common.rs:173-206
pub(crate) enum ToolSpec {
    #[serde(rename = "function")]
    Function(ResponsesApiTool),
    #[serde(rename = "tool_search")]
    ToolSearch {
        execution: String,
        description: String,
        parameters: JsonSchema,
    },
    // ...
}
```

#### 3.2.2 ToolSearchOutput（搜索输出）

```rust
// codex-rs/core/src/tools/context.rs:118-156
pub struct ToolSearchOutput {
    pub tools: Vec<ToolSearchOutputTool>,
}

pub(crate) enum ToolSearchOutputTool {
    #[serde(rename = "function")]
    Function(ResponsesApiTool),
    #[serde(rename = "namespace")]
    Namespace(ResponsesApiNamespace),
}
```

#### 3.2.3 SearchToolCallParams（搜索参数）

```rust
// codex-rs/protocol/src/models.rs
pub struct SearchToolCallParams {
    pub query: String,
    pub limit: Option<usize>,
}
```

### 3.3 BM25 搜索算法实现

**实现文件**：`codex-rs/core/src/tools/handlers/tool_search.rs:72-96`

```rust
// 构建搜索文档
let documents: Vec<Document<usize>> = entries
    .iter()
    .enumerate()
    .map(|(idx, (name, info))| Document::new(idx, build_search_text(name, info)))
    .collect();

// 创建搜索引擎并执行搜索
let search_engine =
    SearchEngineBuilder::<usize>::with_documents(Language::English, documents).build();
let results = search_engine.search(query, limit);
```

**搜索文本构建**（`build_search_text` 函数）：
- 工具名称
- 服务器名称
- 工具标题
- 工具描述
- Connector 名称和描述
- 输入 Schema 的属性名

### 3.4 协议与 API

#### 3.4.1 Responses API 集成

`tool_search` 作为特殊工具类型通过 OpenAI Responses API 暴露：

```json
{
  "type": "tool_search",
  "execution": "client",
  "description": "...",
  "parameters": {
    "type": "object",
    "properties": {
      "query": {"type": "string", "description": "Search query for apps tools."},
      "limit": {"type": "number", "description": "Maximum number of tools to return (defaults to 8)."}
    },
    "required": ["query"],
    "additionalProperties": false
  }
}
```

#### 3.4.2 模型能力标志

```rust
// codex-rs/protocol/src/openai_models.rs:293
pub struct ModelInfo {
    // ...
    pub supports_search_tool: bool,
}
```

模型必须设置 `supports_search_tool: true` 才能启用此功能。

---

## 4. 关键代码路径与文件引用

### 4.1 模板文件

| 文件 | 用途 |
|------|------|
| `codex-rs/core/templates/search_tool/tool_description.md` | `tool_search` 工具描述模板 |
| `codex-rs/core/templates/search_tool/tool_suggest_description.md` | `tool_suggest` 工具描述模板 |

### 4.2 核心实现文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/tools/handlers/tool_search.rs` | ToolSearchHandler 实现，BM25 搜索逻辑 |
| `codex-rs/core/src/tools/handlers/tool_suggest.rs` | ToolSuggestHandler 实现，工具建议逻辑 |
| `codex-rs/core/src/tools/handlers/mod.rs` | Handler 模块导出 |
| `codex-rs/core/src/tools/spec.rs` | 工具规范定义，create_tool_search_tool/create_tool_suggest_tool 函数 |
| `codex-rs/core/src/tools/router.rs` | ToolRouter，处理工具调用路由 |
| `codex-rs/core/src/tools/context.rs` | ToolPayload、ToolSearchOutput 定义 |
| `codex-rs/core/src/tools/registry.rs` | ToolRegistry，工具注册与分发 |
| `codex-rs/core/src/tools/discoverable.rs` | DiscoverableTool 定义，可发现工具过滤 |

### 4.3 配置与特性

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/features.rs` | Feature::Apps、Feature::ToolSuggest 定义 |
| `codex-rs/core/src/tools/spec.rs:332` | 根据 model_info.supports_search_tool 决定是否启用 |
| `codex-rs/core/src/codex.rs:6419-6432` | 决定是否直接暴露 App 工具的逻辑 |

### 4.4 测试文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/tests/suite/search_tool.rs` | 集成测试，验证搜索工具完整流程 |
| `codex-rs/core/src/tools/handlers/tool_search_tests.rs` | 单元测试，验证搜索结果序列化 |
| `codex-rs/core/src/tools/spec_tests.rs` | 工具规范测试 |

### 4.5 关键代码片段

#### 4.5.1 模板加载
```rust
// codex-rs/core/src/tools/spec.rs:61-64
const TOOL_SEARCH_DESCRIPTION_TEMPLATE: &str =
    include_str!("../../templates/search_tool/tool_description.md");
const TOOL_SUGGEST_DESCRIPTION_TEMPLATE: &str =
    include_str!("../../templates/search_tool/tool_suggest_description.md");
```

#### 4.5.2 工具创建
```rust
// codex-rs/core/src/tools/spec.rs:1677-1755
fn create_tool_search_tool(app_tools: &HashMap<String, ToolInfo>) -> ToolSpec {
    // ... 构建参数和描述
    let description = TOOL_SEARCH_DESCRIPTION_TEMPLATE
        .replace("{{app_descriptions}}", app_descriptions.as_str());
    
    ToolSpec::ToolSearch {
        execution: "client".to_string(),
        description,
        parameters: /* ... */,
    }
}
```

#### 4.5.3 工具注册
```rust
// codex-rs/core/src/tools/spec.rs:2752-2770
if config.search_tool && let Some(app_tools) = app_tools {
    let search_tool_handler = Arc::new(ToolSearchHandler::new(app_tools.clone()));
    push_tool_spec(
        &mut builder,
        create_tool_search_tool(&app_tools),
        /*supports_parallel_tool_calls*/ true,
        config.code_mode_enabled,
    );
    builder.register_handler(TOOL_SEARCH_TOOL_NAME, search_tool_handler);
    // ... 注册 App 工具的 MCP handler
}
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 |
|------|------|
| `bm25` crate | BM25 文本搜索算法实现 |
| `serde` | 序列化/反序列化 |
| `async-trait` | 异步 trait 支持 |
| `codex_protocol` | 协议类型定义（SearchToolCallParams, ResponseInputItem 等） |
| `codex_app_server_protocol` | AppServer 协议（AppInfo, McpElicitation 等） |
| `rmcp` | MCP 协议实现 |

### 5.2 内部模块交互

```
┌─────────────────────────────────────────────────────────────────┐
│                         search_tool 模块关系                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │   templates  │────▶│  tools/spec  │────▶│    router    │    │
│  │  (描述模板)   │     │ (创建ToolSpec)│     │  (路由调用)   │    │
│  └──────────────┘     └──────────────┘     └──────────────┘    │
│                              │                       │          │
│                              ▼                       ▼          │
│                       ┌──────────────┐        ┌──────────────┐ │
│                       │   registry   │◄───────│   handlers   │ │
│                       │  (Handler注册) │        │ (tool_search)│ │
│                       └──────────────┘        └──────────────┘ │
│                              │                                  │
│                              ▼                                  │
│                       ┌──────────────┐                         │
│                       │    codex     │                         │
│                       │ (expose_app_ │                         │
│                       │  tools逻辑)   │                         │
│                       └──────────────┘                         │
│                                                                 │
│  其他交互：                                                       │
│  - mcp_connection_manager: 获取 App 工具列表                      │
│  - features: Feature::Apps, Feature::ToolSuggest 控制启用          │
│  - openai_models: ModelInfo.supports_search_tool 模型能力标志      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 与 MCP 的集成

- **工具来源**：`McpConnectionManager::list_all_tools()` 获取所有 MCP 工具
- **App 工具过滤**：通过 `CODEX_APPS_MCP_SERVER_NAME` 识别 App 工具
- **命名空间**：App 工具使用 `mcp__codex_apps__{connector_id}` 命名空间

### 5.4 与 AppServer 的集成

- **可发现工具**：通过 AppServer API 获取可安装的 Connectors 和 Plugins
- **Elicitation**：使用 MCP Elicitation 机制向用户展示安装建议
- **认证**：需要 `CodexAuth::is_chatgpt_auth` 才能启用 Apps 功能

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 认证限制
- **风险**：`tool_search` 仅在 ChatGPT 认证模式下可用，API Key 认证时会被隐藏
- **代码位置**：`codex-rs/core/tests/suite/search_tool.rs:172-208`
- **影响**：使用 API Key 的用户无法使用 Apps 功能

#### 6.1.2 工具暴露阈值
- **风险**：当 App 工具数量少于 `DIRECT_APP_TOOL_EXPOSURE_THRESHOLD` 时，会直接暴露所有工具而非使用搜索
- **代码位置**：`codex-rs/core/src/codex.rs:6421-6424`
- **影响**：少量工具时失去懒加载优势

#### 6.1.3 搜索质量依赖 BM25
- **风险**：BM25 是关键词匹配算法，可能无法准确理解语义相似的查询
- **代码位置**：`codex-rs/core/src/tools/handlers/tool_search.rs:84-86`
- **影响**：用户描述与工具描述用词不同时可能搜索失败

### 6.2 边界条件

| 边界条件 | 处理方式 |
|----------|----------|
| 空查询 | 返回错误 "query must not be empty" |
| limit = 0 | 返回错误 "limit must be greater than zero" |
| 无可用工具 | 返回空列表 |
| 无 App 安装 | `app_descriptions` 显示 "None currently enabled." |
| 工具名称冲突 | 使用 SHA1 hash 进行去重（`mcp_connection_manager.rs:183-186`） |

### 6.3 改进建议

#### 6.3.1 搜索算法优化
- **建议**：考虑引入向量语义搜索（Embedding-based search）作为 BM25 的补充
- **理由**：提高语义相似查询的召回率
- **优先级**：中

#### 6.3.2 搜索结果缓存
- **建议**：缓存频繁搜索的查询结果
- **理由**：减少重复计算，提高响应速度
- **优先级**：低（当前工具数量较少，性能影响有限）

#### 6.3.3 搜索评分可视化
- **建议**：向模型返回工具的匹配分数，帮助模型判断相关性
- **理由**：提高工具选择的准确性
- **优先级**：低

#### 6.3.4 模板国际化
- **建议**：支持多语言的工具描述模板
- **理由**：非英语用户可能获得更好的体验
- **优先级**：低（当前主要面向开发者，英语为主）

#### 6.3.5 搜索历史学习
- **建议**：记录搜索-点击关联，优化搜索结果排序
- **理由**：个性化搜索结果，提高常用工具的发现率
- **优先级**：中（需要用户隐私评估）

### 6.4 测试覆盖建议

当前测试已覆盖：
- ✅ 基本搜索流程（`search_tool.rs`）
- ✅ 搜索结果序列化（`tool_search_tests.rs`）
- ✅ API Key 认证下工具隐藏
- ✅ 显式 App 提及时直接暴露工具

建议补充：
- ⬜ 大规模工具集（>1000）的性能测试
- ⬜ 多语言查询的搜索质量测试
- ⬜ 并发搜索请求的压力测试

---

## 7. 附录

### 7.1 相关文档链接

- [AGENTS.md](../../../../../../AGENTS.md) - 项目级代理指南
- [codex-rs/core/src/mcp/mod.rs](../../src/mcp/mod.rs) - MCP 模块定义
- [codex-rs/protocol/src/models.rs](../../../protocol/src/models.rs) - 协议模型定义

### 7.2 术语表

| 术语 | 说明 |
|------|------|
| Apps/Connectors | ChatGPT 应用/连接器，通过 MCP 提供外部工具 |
| BM25 | Okapi BM25，一种基于概率的文本检索排序算法 |
| MCP | Model Context Protocol，模型上下文协议 |
| Tool Search | 工具搜索功能，允许模型动态发现可用工具 |
| Tool Suggest | 工具建议功能，建议用户安装新工具 |
| Elicitation | 引导式用户交互，用于获取用户确认或输入 |
| Lazy Loading | 懒加载，按需加载而非一次性加载所有资源 |
