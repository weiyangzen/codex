# tool_search_tests.rs 研究文档

## 场景与职责

`tool_search_tests.rs` 是 `tool_search.rs` 的配套测试模块，负责验证工具搜索功能的正确性。测试覆盖工具搜索结果的序列化、命名空间分组、描述回退逻辑等核心功能，确保 MCP 工具搜索输出符合预期的 API 格式。

## 功能点目的

### 1. 命名空间分组验证
验证搜索结果能够正确地按命名空间（如 `mcp__codex_apps__calendar`）进行分组，确保同一连接器下的工具被组织在一起。

### 2. 描述回退逻辑测试
测试当 `connector_description` 缺失时，系统能够正确回退到使用 `connector_name` 生成描述。

### 3. 输出格式验证
验证序列化后的工具输出符合 `ToolSearchOutputTool::Namespace` 结构，包含正确的工具元数据。

## 具体技术实现

### 测试数据结构

测试使用模拟的 `ToolInfo` 结构：

```rust
ToolInfo {
    server_name: CODEX_APPS_MCP_SERVER_NAME.to_string(),
    tool_name: "_create_event".to_string(),
    tool_namespace: "mcp__codex_apps__calendar".to_string(),
    tool: Tool {
        name: "calendar-create-event".to_string().into(),
        title: None,
        description: Some("Create a calendar event.".into()),
        input_schema: Arc::new(JsonObject::from_iter([(
            "type".to_string(),
            json!("object"),
        )])),
        output_schema: None,
        annotations: None,
        execution: None,
        icons: None,
        meta: None,
    },
    connector_id: Some("calendar".to_string()),
    connector_name: Some("Calendar".to_string()),
    plugin_display_names: Vec::new(),
    connector_description: Some("Plan events".to_string()),
}
```

### 核心测试用例

#### `serialize_tool_search_output_tools_groups_results_by_namespace`

验证按命名空间分组的正确性：

```rust
#[test]
fn serialize_tool_search_output_tools_groups_results_by_namespace() {
    // 准备测试数据：3 个工具，分布在 2 个命名空间
    let entries = [
        ("mcp__codex_apps__calendar_create_event", calendar_tool_info),
        ("mcp__codex_apps__gmail_read_email", gmail_tool_info),
        ("mcp__codex_apps__calendar_list_events", calendar_list_tool_info),
    ];

    // 执行序列化
    let tools = serialize_tool_search_output_tools(&[&entries[0], &entries[1], &entries[2]])
        .expect("serialize tool search output");

    // 验证结果
    assert_eq!(tools, vec![
        // calendar 命名空间（字母顺序在前）
        ToolSearchOutputTool::Namespace(ResponsesApiNamespace {
            name: "mcp__codex_apps__calendar".to_string(),
            description: "Plan events".to_string(),
            tools: vec![
                ResponsesApiNamespaceTool::Function(ResponsesApiTool {
                    name: "_create_event".to_string(),
                    description: "Create a calendar event.".to_string(),
                    strict: false,
                    defer_loading: Some(true),  // 关键：延迟加载标记
                    parameters: JsonSchema::Object { ... },
                    output_schema: None,
                }),
                // ... list_events 工具
            ],
        }),
        // gmail 命名空间
        ToolSearchOutputTool::Namespace(ResponsesApiNamespace {
            name: "mcp__codex_apps__gmail".to_string(),
            description: "Read mail".to_string(),
            tools: vec![...],
        })
    ]);
}
```

**关键验证点**：
1. 命名空间按字母顺序排序（`calendar` 在 `gmail` 之前）
2. 同一命名空间下的工具被分组在一起
3. `defer_loading: Some(true)` 标记正确设置
4. 描述从 `connector_description` 提取

#### `serialize_tool_search_output_tools_falls_back_to_connector_name_description`

验证描述回退逻辑：

```rust
#[test]
fn serialize_tool_search_output_tools_falls_back_to_connector_name_description() {
    // 准备数据：connector_description 为 None
    let entries = [(
        "mcp__codex_apps__gmail_batch_read_email".to_string(),
        ToolInfo {
            connector_description: None,  // 关键：描述缺失
            connector_name: Some("Gmail".to_string()),
            // ...
        },
    )];

    let tools = serialize_tool_search_output_tools(&[&entries[0]]).expect("serialize");

    // 验证回退描述
    assert_eq!(
        tools,
        vec![ToolSearchOutputTool::Namespace(ResponsesApiNamespace {
            name: "mcp__codex_apps__gmail".to_string(),
            description: "Tools for working with Gmail.".to_string(),  // 自动生成的描述
            tools: vec![...],
        })]
    );
}
```

**回退逻辑**：
```rust
let description = first_tool.connector_description.clone().or_else(|| {
    first_tool.connector_name.as_deref()
        .map(str::trim)
        .filter(|connector_name| !connector_name.is_empty())
        .map(|connector_name| format!("Tools for working with {connector_name}."))
});
```

## 关键代码路径与文件引用

### 被测试代码
- `codex-rs/core/src/tools/handlers/tool_search.rs`
  - `serialize_tool_search_output_tools()` 函数
  - `build_search_text()` 函数（间接）

### 依赖类型
```rust
use super::*;  // 导入 tool_search.rs 的所有内容
use crate::mcp::CODEX_APPS_MCP_SERVER_NAME;  // MCP 服务器常量
use rmcp::model::{JsonObject, Tool};  // RMCP 模型类型
use serde_json::json;
use std::sync::Arc;
```

### 输出类型结构
```rust
// ToolSearchOutputTool 枚举
tool_search.rs::ToolSearchOutputTool::Namespace(ResponsesApiNamespace {
    name: String,           // 命名空间名称
    description: String,    // 命名空间描述
    tools: Vec<ResponsesApiNamespaceTool>,  // 工具列表
})

// 工具定义
ResponsesApiNamespaceTool::Function(ResponsesApiTool {
    name: String,
    description: String,
    strict: bool,
    defer_loading: Option<bool>,  // 延迟加载标记
    parameters: JsonSchema,
    output_schema: Option<JsonSchema>,
})
```

## 依赖与外部交互

### 测试数据构造
```
测试用例
    │
    ├──> ToolInfo (模拟 MCP 工具元数据)
    │       ├── server_name: "codex-apps-mcp-server"
    │       ├── tool_namespace: "mcp__codex_apps__calendar"
    │       ├── connector_name: "Calendar"
    │       ├── connector_description: "Plan events"
    │       └── tool: rmcp::Tool { ... }
    │
    └──> serialize_tool_search_output_tools()
            │
            ├──> mcp_tool_to_deferred_openai_tool()  // 格式转换
            └──> 按 namespace 分组 (BTreeMap)
```

### RMCP 集成
测试使用 `rmcp` crate 的类型：
- `rmcp::model::Tool` - MCP 工具定义
- `rmcp::model::JsonObject` - JSON Schema 对象

## 风险、边界与改进建议

### 潜在风险

1. **测试数据与实际数据不一致**
   - 测试使用简化的 `input_schema`
   - 实际工具可能有更复杂的参数定义
   - `defer_loading` 行为未在测试中验证实际效果

2. **排序依赖**
   ```rust
   // 测试依赖 BTreeMap 的字典序
   let grouped: BTreeMap<String, Vec<ToolInfo>> = ...
   ```
   - 如果排序逻辑改变，测试会失败
   - 但测试未明确验证排序意图

3. **硬编码常量**
   ```rust
   CODEX_APPS_MCP_SERVER_NAME  // 外部常量依赖
   ```
   - 常量值变更可能导致测试数据失效

### 边界情况

1. **空工具列表**
   - 测试未覆盖空输入场景
   - `serialize_tool_search_output_tools(&[])` 行为未定义

2. **重复命名空间**
   - 测试数据中的命名空间唯一
   - 未测试同一命名空间多次出现的情况

3. **空描述处理**
   ```rust
   // connector_name 为空字符串时
   connector_name: Some("".to_string())
   // 过滤条件：.filter(|connector_name| !connector_name.is_empty())
   ```
   - 未测试空字符串过滤逻辑

4. **工具字段缺失**
   - `title: None` 在测试中使用
   - 未测试 title 存在时的行为

### 改进建议

1. **增强测试覆盖**
   ```rust
   // 建议添加：
   #[test]
   fn serialize_empty_tools_returns_empty() {
       let tools = serialize_tool_search_output_tools(&[]).unwrap();
       assert!(tools.is_empty());
   }

   #[test]
   fn serialize_handles_duplicate_namespaces() {
       // 测试同一命名空间多次出现
   }

   #[test]
   fn serialize_handles_empty_connector_name() {
       // 测试空连接器名称
   }
   ```

2. **验证延迟加载标记**
   ```rust
   // 明确验证 defer_loading 值
   assert_eq!(tool.defer_loading, Some(true));
   ```

3. **参数化测试**
   ```rust
   // 使用 rstest 或类似库
   #[rstest]
   #[case("Calendar", Some("Plan events"), "Plan events")]
   #[case("Gmail", None, "Tools for working with Gmail.")]
   #[case("Gmail", Some(""), "Tools for working with Gmail.")]
   fn test_description_fallback(...)
   ```

4. **集成测试建议**
   ```rust
   // 建议添加集成测试：
   // - 与真实 MCP 服务器交互
   // - 验证 BM25 搜索结果序列化
   // - 测试大规模工具集性能
   ```

5. **文档测试**
   ```rust
   /// ```
   /// let tools = vec![tool1, tool2];
   /// let output = serialize_tool_search_output_tools(&tools).unwrap();
   /// assert!(!output.is_empty());
   /// ```
   fn serialize_tool_search_output_tools(...) { ... }
   ```

### 维护注意事项

1. 当 `ResponsesApiNamespace` 或 `ResponsesApiTool` 结构变更时，需要同步更新测试
2. `mcp_tool_to_deferred_openai_tool` 行为变更会影响测试结果
3. 添加新的输出字段时，应在测试中验证
4. 考虑使用快照测试（insta）简化大型结构体验证
