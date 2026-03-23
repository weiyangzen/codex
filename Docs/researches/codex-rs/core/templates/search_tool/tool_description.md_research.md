# tool_description.md 研究文档

## 场景与职责

`tool_description.md` 是 Codex 核心工具系统中 **tool_search** 功能的描述模板文件。它定义了 `tool_search` 工具向 AI 模型暴露的行为规范和功能说明。

### 核心场景

1. **Apps/Connectors 工具发现**：当用户需要访问 Codex Apps（连接器）提供的工具时，AI 模型可以通过 `tool_search` 工具搜索可用的工具
2. **动态工具加载**：允许模型在运行时按需发现和加载特定 App/Connector 的工具，而非一次性暴露所有工具
3. **工具命名空间管理**：通过搜索机制管理大量 MCP（Model Context Protocol）工具的组织和发现

### 职责定位

该模板文件作为 `tool_search` 工具的系统提示（system prompt）组成部分，向 AI 模型说明：
- 工具搜索的目的和能力
- 可用的 Apps/Connectors 列表
- 与 `list_mcp_resources` 或 `list_mcp_resource_templates` 的区别

---

## 功能点目的

### 1. BM25 搜索能力说明

```markdown
Searches over apps/connectors tool metadata with BM25 and exposes matching tools for the next model call.
```

**目的**：告知模型 tool_search 使用 BM25 算法（一种经典的文本检索算法）来匹配工具元数据，帮助模型理解搜索的匹配机制。

### 2. 可用 Apps 列表注入

```markdown
You have access to all the tools of the following apps/connectors:
{{app_descriptions}}
```

**目的**：
- 通过模板变量 `{{app_descriptions}}` 动态注入当前可用的连接器列表
- 每个 App 以 `- {connector_name}: {connector_description}` 格式呈现
- 让模型了解当前环境中可用的工具来源

### 3. 使用指南

```markdown
Some of the tools may not have been provided to you upfront, and you should use this tool (`tool_search`) to search for the required tools and load them for the apps mentioned above.
```

**目的**：
- 明确告知模型某些工具可能未预先提供
- 指导模型在需要时使用 `tool_search` 进行搜索
- 强调对于上述列出的 Apps，应优先使用 `tool_search` 而非其他发现机制

### 4. 工具发现优先级

```markdown
For the apps mentioned above, always use `tool_search` instead of `list_mcp_resources` or `list_mcp_resource_templates` for tool discovery.
```

**目的**：
- 建立工具发现的优先级规则
- 防止模型混淆不同工具发现机制的使用场景
- 确保 Apps/Connectors 工具通过专用搜索机制被发现

---

## 具体技术实现

### 模板编译与使用流程

```
┌─────────────────────────────────────────────────────────────────┐
│  1. 模板定义 (tool_description.md)                               │
│     - 静态描述文本                                               │
│     - {{app_descriptions}} 占位符                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. 模板编译 (spec.rs)                                          │
│     const TOOL_SEARCH_DESCRIPTION_TEMPLATE: &str =              │
│         include_str!("../../templates/search_tool/tool_description.md");
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. 动态渲染 (create_tool_search_tool 函数)                      │
│     - 收集所有 codex_apps 的连接器信息                           │
│     - 构建 app_descriptions 字符串                              │
│     - 执行模板替换: template.replace("{{app_descriptions}}", ...)│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. 工具注册 (build_specs_with_discoverable_tools)               │
│     - 创建 ToolSpec::ToolSearch 变体                            │
│     - 注册 ToolSearchHandler                                   │
│     - 将工具定义发送到 OpenAI Responses API                     │
└─────────────────────────────────────────────────────────────────┘
```

### 关键数据结构

#### ToolSpec::ToolSearch 定义

```rust
// client_common.rs
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(tag = "type")]
pub(crate) enum ToolSpec {
    #[serde(rename = "tool_search")]
    ToolSearch {
        execution: String,
        description: String,  // ← 渲染后的 tool_description.md
        parameters: JsonSchema,
    },
    // ...
}
```

#### 模板渲染代码

```rust
// spec.rs:1677-1755
fn create_tool_search_tool(app_tools: &HashMap<String, ToolInfo>) -> ToolSpec {
    // 1. 构建参数 schema
    let properties = BTreeMap::from([
        ("query".to_string(), JsonSchema::String { ... }),
        ("limit".to_string(), JsonSchema::Number { ... }),
    ]);

    // 2. 收集 App 描述
    let mut app_descriptions = BTreeMap::new();
    for tool in app_tools.values() {
        if tool.server_name != CODEX_APPS_MCP_SERVER_NAME {
            continue;
        }
        // 提取 connector_name 和 connector_description
        // ...
        app_descriptions.entry(connector_name.to_string())
            .and_modify(|existing: &mut Option<String>| { ... })
            .or_insert(connector_description);
    }

    // 3. 格式化描述列表
    let app_descriptions = if app_descriptions.is_empty() {
        "None currently enabled.".to_string()
    } else {
        app_descriptions.into_iter()
            .map(|(name, desc)| format!("- {name}: {desc}"))
            .collect::<Vec<_>>()
            .join("\n")
    };

    // 4. 模板替换
    let description = TOOL_SEARCH_DESCRIPTION_TEMPLATE
        .replace("{{app_descriptions}}", app_descriptions.as_str());

    ToolSpec::ToolSearch {
        execution: "client".to_string(),
        description,
        parameters: JsonSchema::Object { ... },
    }
}
```

### 工具执行流程

```rust
// handlers/tool_search.rs
pub struct ToolSearchHandler {
    tools: HashMap<String, ToolInfo>,
}

#[async_trait]
impl ToolHandler for ToolSearchHandler {
    type Output = ToolSearchOutput;

    async fn handle(&self, invocation: ToolInvocation) -> Result<ToolSearchOutput, FunctionCallError> {
        // 1. 解析参数
        let args = match payload {
            ToolPayload::ToolSearch { arguments } => arguments,
            _ => { /* error */ }
        };
        let query = args.query.trim();
        let limit = args.limit.unwrap_or(DEFAULT_LIMIT); // 默认 8

        // 2. 构建 BM25 搜索文档
        let documents: Vec<Document<usize>> = entries
            .iter()
            .enumerate()
            .map(|(idx, (name, info))| {
                Document::new(idx, build_search_text(name, info))
            })
            .collect();

        // 3. 执行 BM25 搜索
        let search_engine = SearchEngineBuilder::<usize>::with_documents(
            Language::English, 
            documents
        ).build();
        let results = search_engine.search(query, limit);

        // 4. 序列化输出
        let tools = serialize_tool_search_output_tools(&matched_entries)?;
        Ok(ToolSearchOutput { tools })
    }
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

    // 包含标题、描述、连接器名称、连接器描述
    if let Some(title) = info.tool.title.as_deref() { parts.push(title.to_string()); }
    if let Some(description) = info.tool.description.as_deref() { parts.push(description.to_string()); }
    if let Some(connector_name) = info.connector_name.as_deref() { parts.push(connector_name.to_string()); }
    if let Some(connector_description) = info.connector_description.as_deref() { 
        parts.push(connector_description.to_string()); 
    }

    // 包含输入 schema 的属性名
    parts.extend(
        info.tool.input_schema
            .get("properties")
            .and_then(serde_json::Value::as_object)
            .map(|map| map.keys().cloned().collect::<Vec<_>>())
            .unwrap_or_default(),
    );

    parts.join(" ")
}
```

---

## 关键代码路径与文件引用

### 模板定义
| 文件 | 作用 |
|------|------|
| `codex-rs/core/templates/search_tool/tool_description.md` | 模板源文件，包含 `{{app_descriptions}}` 占位符 |

### 模板编译与渲染
| 文件 | 函数/代码 | 作用 |
|------|----------|------|
| `codex-rs/core/src/tools/spec.rs` | `const TOOL_SEARCH_DESCRIPTION_TEMPLATE` | 编译时包含模板文件 |
| `codex-rs/core/src/tools/spec.rs` | `create_tool_search_tool()` | 渲染模板，替换 `{{app_descriptions}}` |
| `codex-rs/core/src/tools/spec.rs` | `build_specs_with_discoverable_tools()` | 条件注册 tool_search 工具 |

### 工具执行
| 文件 | 函数/结构 | 作用 |
|------|----------|------|
| `codex-rs/core/src/tools/handlers/tool_search.rs` | `ToolSearchHandler` | 处理 tool_search 调用 |
| `codex-rs/core/src/tools/handlers/tool_search.rs` | `build_search_text()` | 构建 BM25 搜索文本 |
| `codex-rs/core/src/tools/handlers/tool_search.rs` | `serialize_tool_search_output_tools()` | 序列化搜索结果 |

### 数据类型定义
| 文件 | 类型 | 作用 |
|------|------|------|
| `codex-rs/core/src/client_common.rs` | `ToolSpec::ToolSearch` | 工具规范枚举变体 |
| `codex-rs/core/src/client_common.rs` | `ToolSearchOutputTool` | 搜索输出工具类型 |
| `codex-rs/core/src/client_common.rs` | `ResponsesApiNamespace` | 命名空间输出结构 |
| `codex-rs/core/src/tools/context.rs` | `ToolSearchOutput` | 工具搜索输出结构 |
| `codex-rs/core/src/tools/context.rs` | `ToolPayload::ToolSearch` | 工具调用负载类型 |

### 配置与启用
| 文件 | 代码 | 作用 |
|------|------|------|
| `codex-rs/core/src/tools/spec.rs` | `ToolsConfig::search_tool` | 控制是否启用 tool_search |
| `codex-rs/core/src/tools/spec.rs` | `ToolsConfig::new()` | 根据 `model_info.supports_search_tool` 初始化 |

### 测试
| 文件 | 作用 |
|------|------|
| `codex-rs/core/tests/suite/search_tool.rs` | 集成测试，验证 tool_search 功能 |
| `codex-rs/core/src/tools/handlers/tool_search_tests.rs` | 单元测试 |

---

## 依赖与外部交互

### 内部依赖

```
tool_description.md
    │
    ├──► spec.rs (模板编译与渲染)
    │       │
    │       ├──► client_common.rs (ToolSpec 定义)
    │       ├──► tools/context.rs (ToolSearchOutput)
    │       └──► mcp_connection_manager/ToolInfo (工具信息)
    │
    └──► handlers/tool_search.rs (执行逻辑)
            │
            ├──► bm25 crate (搜索算法)
            ├──► connectors.rs (连接器信息)
            └──► codex_apps MCP server
```

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `bm25` crate | 提供 BM25 文本搜索算法实现 |
| `codex_apps` MCP Server | 提供 Apps/Connectors 工具元数据 |
| OpenAI Responses API | 接收 tool_search 工具定义 |

### 配置依赖

```rust
// 启用条件 (spec.rs:332)
let include_search_tool = model_info.supports_search_tool;

// 运行时检查 (spec.rs:2752)
if config.search_tool && let Some(app_tools) = app_tools {
    // 注册 tool_search
}
```

---

## 风险、边界与改进建议

### 当前风险

1. **模板与代码耦合**
   - 模板文件 `{{app_descriptions}}` 变量名硬编码在 Rust 代码中
   - 如果模板修改了变量名而代码未同步，会导致替换失败
   - **建议**：添加编译时模板变量验证或单元测试

2. **空状态处理**
   - 当没有可用 Apps 时，显示 "None currently enabled."
   - 这可能导致模型困惑为何 tool_search 可用但无工具可搜
   - **建议**：考虑在无 Apps 时禁用 tool_search 工具

3. **描述长度风险**
   - 如果连接器数量很多，渲染后的描述可能很长
   - 可能超出模型上下文限制或影响提示质量
   - **建议**：添加描述长度限制或分页机制

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 无 Apps 可用 | 显示 "None currently enabled." | 可接受，但可优化 |
| 连接器无描述 | 显示 "- {connector_name}" | 合理降级 |
| 重复连接器名 | 后出现的覆盖先出现的描述 | 需关注 |
| API Key 认证 | 隐藏 tool_search (见 search_tool.rs:173) | 安全考虑 |

### 改进建议

1. **模板验证**
   ```rust
   // 建议在编译时或测试时验证模板包含预期变量
   #[test]
   fn tool_description_template_has_required_placeholder() {
       assert!(TOOL_SEARCH_DESCRIPTION_TEMPLATE.contains("{{app_descriptions}}"));
   }
   ```

2. **动态描述截断**
   - 当 App 列表过长时，智能截断或分级显示
   - 优先显示最近使用或最相关的 Apps

3. **国际化支持**
   - 当前模板为英文硬编码
   - 考虑支持多语言模板

4. **元数据增强**
   - 在描述中增加每个 App 的工具数量统计
   - 帮助模型理解各 App 的工具丰富度

5. **搜索范围说明**
   - 当前模板未说明搜索的具体字段
   - 可考虑增加说明搜索覆盖工具名、描述、参数名等
