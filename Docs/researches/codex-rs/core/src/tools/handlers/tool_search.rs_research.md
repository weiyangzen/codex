# tool_search.rs 研究文档

## 场景与职责

`tool_search.rs` 实现了 `tool_search` 工具处理器，提供基于 BM25 算法的 MCP (Model Context Protocol) 工具搜索功能。该工具允许模型在大量可用工具中快速定位相关工具，支持语义化的工具发现，是 Codex 插件/连接器生态系统的关键组件。

## 功能点目的

### 1. 工具发现与检索
提供高效的工具搜索能力，帮助模型在数百个 MCP 工具中快速找到相关工具。使用 BM25 算法实现基于关键词的相关性排序。

### 2. 命名空间聚合
将搜索结果按命名空间分组（如 `mcp__codex_apps__calendar`），提供结构化的工具组织视图，便于模型理解和选择。

### 3. 连接器元数据展示
在搜索结果中包含连接器描述、插件来源等元数据，帮助模型理解工具的用途和来源。

## 具体技术实现

### 核心数据结构

```rust
pub struct ToolSearchHandler {
    tools: HashMap<String, ToolInfo>,  // 工具名称 -> 工具信息
}

pub(crate) const TOOL_SEARCH_TOOL_NAME: &str = "tool_search";
pub(crate) const DEFAULT_LIMIT: usize = 8;  // 默认返回结果数
```

### BM25 搜索实现

```rust
async fn handle(&self, invocation: ToolInvocation) -> Result<ToolSearchOutput, FunctionCallError> {
    // 1. 参数解析和验证
    let args = match payload {
        ToolPayload::ToolSearch { arguments } => arguments,
        _ => { /* 错误处理 */ }
    };

    let query = args.query.trim();
    if query.is_empty() {
        return Err(FunctionCallError::RespondToModel("query must not be empty".to_string()));
    }
    let limit = args.limit.unwrap_or(DEFAULT_LIMIT);

    // 2. 准备文档集合
    let mut entries: Vec<(String, ToolInfo)> = self.tools.clone().into_iter().collect();
    entries.sort_by(|a, b| a.0.cmp(&b.0));

    if entries.is_empty() {
        return Ok(ToolSearchOutput { tools: Vec::new() });
    }

    // 3. 构建 BM25 文档
    let documents: Vec<Document<usize>> = entries
        .iter()
        .enumerate()
        .map(|(idx, (name, info))| Document::new(idx, build_search_text(name, info)))
        .collect();

    // 4. 执行搜索
    let search_engine = SearchEngineBuilder::<usize>::with_documents(Language::English, documents).build();
    let results = search_engine.search(query, limit);

    // 5. 映射结果并序列化输出
    let matched_entries = results
        .into_iter()
        .filter_map(|result| entries.get(result.document.id))
        .collect::<Vec<_>>();
    let tools = serialize_tool_search_output_tools(&matched_entries)?;

    Ok(ToolSearchOutput { tools })
}
```

### 搜索文本构建

```rust
fn build_search_text(name: &str, info: &ToolInfo) -> String {
    let mut parts = vec![
        name.to_string(),
        info.tool_name.clone(),
        info.server_name.clone(),
    ];

    // 添加标题
    if let Some(title) = info.tool.title.as_deref()
        && !title.trim().is_empty()
    {
        parts.push(title.to_string());
    }

    // 添加描述
    if let Some(description) = info.tool.description.as_deref()
        && !description.trim().is_empty()
    {
        parts.push(description.to_string());
    }

    // 添加连接器信息
    if let Some(connector_name) = info.connector_name.as_deref()
        && !connector_name.trim().is_empty()
    {
        parts.push(connector_name.to_string());
    }

    // 添加参数名作为搜索关键词
    parts.extend(
        info.tool
            .input_schema
            .get("properties")
            .and_then(serde_json::Value::as_object)
            .map(|map| map.keys().cloned().collect::<Vec<_>>())
            .unwrap_or_default(),
    );

    parts.join(" ")
}
```

### 结果序列化

```rust
fn serialize_tool_search_output_tools(
    matched_entries: &[&(String, ToolInfo)],
) -> Result<Vec<ToolSearchOutputTool>, serde_json::Error> {
    // 按命名空间分组
    let grouped: BTreeMap<String, Vec<ToolInfo>> = matched_entries
        .iter()
        .fold(BTreeMap::new(), |mut acc, (_name, tool)| {
            acc.entry(tool.tool_namespace.clone())
                .or_default()
                .push(tool.clone());
            acc
        });

    let mut results = Vec::with_capacity(grouped.len());
    for (namespace, tools) in grouped {
        // 提取命名空间描述
        let description = first_tool.connector_description.clone()
            .or_else(|| {
                first_tool.connector_name.as_deref()
                    .map(|name| format!("Tools for working with {name}."))
            });

        // 转换工具为 OpenAI 格式
        let tools = tools
            .iter()
            .map(|tool| {
                mcp_tool_to_deferred_openai_tool(tool.tool_name.clone(), tool.tool.clone())
                    .map(ResponsesApiNamespaceTool::Function)
            })
            .collect::<Result<Vec<_>, _>>()?;

        results.push(ToolSearchOutputTool::Namespace(ResponsesApiNamespace {
            name: namespace,
            description: description.unwrap_or_default(),
            tools,
        }));
    }

    Ok(results)
}
```

## 关键代码路径与文件引用

### 模块结构
```
tool_search.rs
├── ToolSearchHandler
│   ├── new(tools: HashMap<String, ToolInfo>) -> Self
│   └── ToolHandler trait 实现
├── build_search_text() - 构建搜索文档
├── serialize_tool_search_output_tools() - 序列化结果
└── tests (tool_search_tests.rs)
```

### 依赖关系
```rust
// 核心依赖
use crate::client_common::tools::{ResponsesApiNamespace, ResponsesApiNamespaceTool, ToolSearchOutputTool};
use crate::function_tool::FunctionCallError;
use crate::mcp_connection_manager::ToolInfo;  // 工具元数据
use crate::tools::context::{ToolInvocation, ToolPayload, ToolSearchOutput};
use crate::tools::registry::{ToolHandler, ToolKind};
use crate::tools::spec::mcp_tool_to_deferred_openai_tool;

// BM25 库
use bm25::{Document, Language, SearchEngineBuilder};
```

### 相关文件
- `codex-rs/core/src/tools/handlers/tool_search_tests.rs` - 单元测试
- `codex-rs/core/src/mcp_connection_manager.rs` - ToolInfo 定义
- `codex-rs/core/src/tools/spec.rs` - 工具格式转换
- `codex-rs/core/src/tools/context.rs` - ToolSearchOutput 定义

## 依赖与外部交互

### 数据流
```
模型查询 "calendar events"
    │
    ▼
ToolSearchHandler::handle()
    │
    ├──> build_search_text() 为每个工具构建文档
    │       "calendar_create_event _create_event codex_apps Calendar Create event..."
    │
    ├──> BM25 SearchEngine::search()
    │       计算相关性分数
    │
    └──> serialize_tool_search_output_tools()
            按命名空间分组
                │
                ▼
    {
        "name": "mcp__codex_apps__calendar",
        "description": "Plan events",
        "tools": [...]
    }
```

### ToolInfo 结构
```rust
pub(crate) struct ToolInfo {
    pub(crate) server_name: String,        // MCP 服务器名
    pub(crate) tool_name: String,          // 工具名
    pub(crate) tool_namespace: String,     // 命名空间
    pub(crate) tool: Tool,                 // rmcp Tool 定义
    pub(crate) connector_id: Option<String>,
    pub(crate) connector_name: Option<String>,
    pub(crate) plugin_display_names: Vec<String>,
    pub(crate) connector_description: Option<String>,
}
```

## 风险、边界与改进建议

### 潜在风险

1. **BM25 算法局限**
   - 基于词频的相关性计算，不理解语义
   - 短查询（如单个词）可能返回不相关结果
   - 同义词处理依赖训练数据

2. **性能问题**
   ```rust
   // 每次搜索都克隆整个 tools HashMap
   let mut entries: Vec<(String, ToolInfo)> = self.tools.clone().into_iter().collect();
   ```
   - 工具数量增加时内存开销大
   - 每次搜索重建 BM25 索引效率低

3. **英文偏见**
   ```rust
   let search_engine = SearchEngineBuilder::<usize>::with_documents(Language::English, documents).build();
   ```
   - 固定使用 English 语言模型
   - 非英文工具描述搜索效果可能不佳

### 边界情况

1. **空查询处理**
   ```rust
   if query.is_empty() {
       return Err(FunctionCallError::RespondToModel("query must not be empty".to_string()));
   }
   ```

2. **零限制值**
   ```rust
   if limit == 0 {
       return Err(FunctionCallError::RespondToModel("limit must be greater than zero".to_string()));
   }
   ```

3. **空工具集合**
   ```rust
   if entries.is_empty() {
       return Ok(ToolSearchOutput { tools: Vec::new() });
   }
   ```

4. **缺失元数据**
   - connector_description 为 None 时回退到 connector_name
   - 两者都缺失时返回空描述

### 改进建议

1. **性能优化**
   ```rust
   // 建议：预构建和缓存 BM25 索引
   pub struct ToolSearchHandler {
       tools: HashMap<String, ToolInfo>,
       search_engine: ArcSwap<SearchEngine<usize>>,  // 使用 ArcSwap 实现无锁更新
   }
   ```

2. **多语言支持**
   ```rust
   // 根据工具描述语言动态选择
   fn detect_language(texts: &[String]) -> Language {
       // 实现语言检测逻辑
   }
   ```

3. **语义搜索增强**
   ```rust
   // 集成向量嵌入搜索作为补充
   pub struct HybridSearchHandler {
       bm25_engine: SearchEngine<usize>,
       vector_index: VectorIndex,  // 向量索引
   }
   ```

4. **搜索建议**
   ```rust
   // 添加 did_you_mean 功能
   pub struct ToolSearchOutput {
       tools: Vec<ToolSearchOutputTool>,
       suggestions: Vec<String>,  // 查询建议
   }
   ```

5. **相关性阈值**
   ```rust
   // 过滤低相关性结果
   let results: Vec<_> = search_engine.search(query, limit)
       .into_iter()
       .filter(|r| r.score > MIN_RELEVANCE_THRESHOLD)
       .collect();
   ```

6. **搜索历史优化**
   ```rust
   // 基于用户选择历史优化排序
   fn rerank_by_history(results: Vec<SearchResult>, user_history: &History) -> Vec<SearchResult> {
       // 实现个性化排序
   }
   ```

### 测试覆盖

当前测试在 `tool_search_tests.rs` 中覆盖：
- 按命名空间分组
- 描述回退逻辑
- 序列化格式

建议添加：
- 大规模工具集性能测试
- 多语言搜索测试
- 相关性评分验证
