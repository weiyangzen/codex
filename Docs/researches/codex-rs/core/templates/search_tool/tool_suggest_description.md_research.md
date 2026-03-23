# tool_suggest_description.md 研究文档

## 场景与职责

`tool_suggest_description.md` 是 Codex 核心工具系统中 **tool_suggest** 功能的描述模板文件。它定义了当用户请求的能力不在当前可用工具列表中时，AI 模型如何建议用户安装或启用新的连接器(Connector)或插件(Plugin)。

### 核心场景

1. **工具缺失时的智能建议**：当用户请求当前未安装/启用的 Connector 或 Plugin 提供的功能时，模型可以通过 `tool_suggest` 建议用户获取该工具
2. **发现性工具推广**：向用户展示系统中存在但尚未启用的可选工具
3. **安装/启用工作流引导**：引导用户完成工具的安装或启用流程

### 职责定位

该模板文件作为 `tool_suggest` 工具的系统提示组成部分，向 AI 模型说明：
- 何时应该使用 tool_suggest（严格的条件判断）
- 可发现工具的列表和详细信息
- 建议工作流的执行步骤
- 建议完成后的后续处理

---

## 功能点目的

### 1. 使用条件约束

```markdown
Use this ONLY when:
- There's no available tool to handle the user's request
- And tool_search fails to find a good match
- AND the user's request strongly matches one of the discoverable tools listed below.
```

**目的**：
- 建立严格的优先级：先尝试现有工具 → 再尝试 tool_search → 最后才用 tool_suggest
- 防止模型过度推荐，避免打扰用户
- 确保建议的工具确实能解决用户问题

### 2. 可发现工具白名单

```markdown
Tool suggestions should only use the discoverable tools listed here. DO NOT explore or recommend tools that are not on this list.

Discoverable tools:
{{discoverable_tools}}
```

**目的**：
- 通过 `{{discoverable_tools}}` 动态注入当前可发现的工具列表
- 严格限制模型只能建议列表中的工具（白名单机制）
- 防止模型幻觉或推荐不存在/不支持的工具

### 3. 工作流指导

```markdown
Workflow:

1. Match the user's request against the discoverable tools list above.
2. If one clearly fits, call `tool_suggest` with:
   - `tool_type`: `connector` or `plugin`
   - `action_type`: `install` or `enable`
   - `tool_id`: exact id from the discoverable tools list above
   - `suggest_reason`: concise one-line user-facing reason this tool can help with the current request
```

**目的**：
- 提供清晰的工作流步骤
- 明确参数取值范围和约束（如 `tool_id` 必须来自列表）
- 指导模型编写用户友好的建议理由

### 4. 后续处理指导

```markdown
3. After the suggestion flow completes:
   - if the user finished the install or enable flow, continue by searching again or using the newly available tool
   - if the user did not finish, continue without that tool, and don't suggest that tool again unless the user explicitly asks you to.
```

**目的**：
- 指导模型根据用户响应采取不同后续行动
- 避免重复建议（如果用户拒绝）
- 确保建议完成后能正确继续任务

---

## 具体技术实现

### 模板编译与使用流程

```
┌─────────────────────────────────────────────────────────────────┐
│  1. 模板定义 (tool_suggest_description.md)                       │
│     - 静态使用条件和约束说明                                     │
│     - {{discoverable_tools}} 占位符                             │
│     - Workflow 执行步骤                                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. 模板编译 (spec.rs)                                          │
│     const TOOL_SUGGEST_DESCRIPTION_TEMPLATE: &str =             │
│         include_str!("../../templates/search_tool/tool_suggest_description.md");
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. 动态渲染 (create_tool_suggest_tool 函数)                     │
│     - 收集可发现工具列表（Connectors + Plugins）                 │
│     - 格式化工具信息为可读列表                                   │
│     - 执行模板替换: template.replace("{{discoverable_tools}}", ...)
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. 工具注册 (build_specs_with_discoverable_tools)               │
│     - 条件：config.tool_suggest && discoverable_tools 非空       │
│     - 创建 ToolSpec::Function (普通函数工具)                     │
│     - 注册 ToolSuggestHandler                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 关键数据结构

#### ToolSuggestArgs (参数定义)

```rust
// handlers/tool_suggest.rs:36-42
#[derive(Debug, Deserialize)]
struct ToolSuggestArgs {
    tool_type: DiscoverableToolType,      // "connector" | "plugin"
    action_type: DiscoverableToolAction,  // "install" | "enable"
    tool_id: String,                      // 必须匹配可发现列表中的 ID
    suggest_reason: String,               // 向用户展示的建议理由
}
```

#### DiscoverableTool 枚举

```rust
// tools/discoverable.rs:40-44
pub(crate) enum DiscoverableTool {
    Connector(Box<AppInfo>),
    Plugin(Box<DiscoverablePluginInfo>),
}

impl DiscoverableTool {
    pub(crate) fn tool_type(&self) -> DiscoverableToolType { ... }
    pub(crate) fn id(&self) -> &str { ... }
    pub(crate) fn name(&self) -> &str { ... }
    pub(crate) fn description(&self) -> Option<&str> { ... }
    pub(crate) fn install_url(&self) -> Option<&str> { ... }
}
```

#### 模板渲染代码

```rust
// spec.rs:1757-1821
fn create_tool_suggest_tool(discoverable_tools: &[DiscoverableTool]) -> ToolSpec {
    // 1. 提取所有可发现工具的 ID（用于参数描述）
    let discoverable_tool_ids = discoverable_tools
        .iter()
        .map(DiscoverableTool::id)
        .collect::<Vec<_>>()
        .join(", ");

    // 2. 构建参数 schema
    let properties = BTreeMap::from([
        ("tool_type", JsonSchema::String { ... }),
        ("action_type", JsonSchema::String { ... }),
        ("tool_id", JsonSchema::String { 
            description: format!("Must be one of: {discoverable_tool_ids}.")
        }),
        ("suggest_reason", JsonSchema::String { ... }),
    ]);

    // 3. 格式化可发现工具列表
    let description = TOOL_SUGGEST_DESCRIPTION_TEMPLATE.replace(
        "{{discoverable_tools}}",
        format_discoverable_tools(discoverable_tools).as_str(),
    );

    ToolSpec::Function(ResponsesApiTool {
        name: TOOL_SUGGEST_TOOL_NAME.to_string(),  // "tool_suggest"
        description,
        strict: false,
        defer_loading: None,
        parameters: JsonSchema::Object { ... },
        output_schema: None,
    })
}
```

### 可发现工具格式化

```rust
// spec.rs:1823-1857
fn format_discoverable_tools(discoverable_tools: &[DiscoverableTool]) -> String {
    // 按名称和 ID 排序，确保输出稳定
    let mut discoverable_tools = discoverable_tools.to_vec();
    discoverable_tools.sort_by(|left, right| {
        left.name().cmp(right.name())
            .then_with(|| left.id().cmp(right.id()))
    });

    discoverable_tools.into_iter()
        .map(|tool| {
            let description = tool.description()
                .filter(|d| !d.trim().is_empty())
                .map(ToString::to_string)
                .unwrap_or_else(|| match &tool {
                    DiscoverableTool::Connector(_) => "No description provided.".to_string(),
                    DiscoverableTool::Plugin(plugin) => format_plugin_summary(plugin),
                });
            
            let default_action = match tool.tool_type() {
                DiscoverableToolType::Connector => DiscoverableToolAction::Install,
                DiscoverableToolType::Plugin => DiscoverableToolAction::Install,
            };
            
            format!(
                "- {} (id: `{}`, type: {}, action: {}): {}",
                tool.name(),
                tool.id(),
                tool.tool_type().as_str(),
                default_action.as_str(),
                description
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}
```

### 工具执行流程

```rust
// handlers/tool_suggest.rs
pub struct ToolSuggestHandler;

#[async_trait]
impl ToolHandler for ToolSuggestHandler {
    type Output = FunctionToolOutput;

    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        // 1. 解析参数
        let args: ToolSuggestArgs = parse_arguments(&arguments)?;
        
        // 2. 验证 suggest_reason 非空
        let suggest_reason = args.suggest_reason.trim();
        if suggest_reason.is_empty() { /* error */ }
        
        // 3. 验证 action_type（当前仅支持 install）
        if args.action_type != DiscoverableToolAction::Install { /* error */ }
        
        // 4. 客户端限制（TUI 暂不支持 plugin 建议）
        if args.tool_type == DiscoverableToolType::Plugin 
            && turn.app_server_client_name.as_deref() == Some("codex-tui") {
            return Err(..."plugin tool suggestions are not available in codex-tui yet"...);
        }

        // 5. 获取可发现工具列表
        let discoverable_tools = connectors::list_tool_suggest_discoverable_tools_with_auth(...)
            .await
            .map(|tools| filter_tool_suggest_discoverable_tools_for_client(tools, client_name))?;

        // 6. 验证 tool_id 在列表中
        let tool = discoverable_tools.into_iter()
            .find(|t| t.tool_type() == args.tool_type && t.id() == args.tool_id)
            .ok_or_else(|| /* error: tool_id not found */)?;

        // 7. 构建并发送 MCP Server Elicitation 请求
        let request_id = RequestId::String(format!("tool_suggestion_{call_id}").into());
        let params = build_tool_suggestion_elicitation_request(...);
        let response = session.request_mcp_server_elicitation(turn.as_ref(), request_id, params).await;
        
        // 8. 判断用户是否接受
        let user_confirmed = response.as_ref().is_some_and(|r| r.action == ElicitationAction::Accept);
        
        // 9. 验证建议是否完成（工具是否实际可用）
        let completed = if user_confirmed {
            verify_tool_suggestion_completed(&session, &turn, &tool, auth.as_ref()).await
        } else { false };

        // 10. 如果完成且是 Connector，合并到会话选择
        if completed && let DiscoverableTool::Connector(connector) = &tool {
            session.merge_connector_selection(HashSet::from([connector.id.clone()])).await;
        }

        // 11. 返回结果
        let content = serde_json::to_string(&ToolSuggestResult { ... })?;
        Ok(FunctionToolOutput::from_text(content, Some(true)))
    }
}
```

### 完成验证逻辑

```rust
// handlers/tool_suggest.rs:248-292
async fn verify_tool_suggestion_completed(
    session: &Session,
    turn: &TurnContext,
    tool: &DiscoverableTool,
    auth: Option<&CodexAuth>,
) -> bool {
    match tool {
        DiscoverableTool::Connector(connector) => {
            // 刷新 MCP tools 缓存
            let manager = session.services.mcp_connection_manager.read().await;
            match manager.hard_refresh_codex_apps_tools_cache().await {
                Ok(mcp_tools) => {
                    // 检查连接器现在是否可访问
                    let accessible_connectors = connectors::accessible_connectors_from_mcp_tools(&mcp_tools);
                    verified_connector_suggestion_completed(connector.id.as_str(), &accessible_connectors)
                }
                Err(err) => { /* log warning, return false */ }
            }
        }
        DiscoverableTool::Plugin(plugin) => {
            // 重新加载用户配置
            session.reload_user_config_layer().await;
            let config = session.get_config().await;
            // 检查插件是否已安装
            verified_plugin_suggestion_completed(plugin.id.as_str(), config.as_ref(), session.services.plugins_manager.as_ref())
        }
    }
}
```

---

## 关键代码路径与文件引用

### 模板定义
| 文件 | 作用 |
|------|------|
| `codex-rs/core/templates/search_tool/tool_suggest_description.md` | 模板源文件，包含 `{{discoverable_tools}}` 占位符 |

### 模板编译与渲染
| 文件 | 函数/代码 | 作用 |
|------|----------|------|
| `codex-rs/core/src/tools/spec.rs` | `const TOOL_SUGGEST_DESCRIPTION_TEMPLATE` | 编译时包含模板文件 |
| `codex-rs/core/src/tools/spec.rs` | `create_tool_suggest_tool()` | 渲染模板，替换 `{{discoverable_tools}}` |
| `codex-rs/core/src/tools/spec.rs` | `format_discoverable_tools()` | 格式化可发现工具列表 |
| `codex-rs/core/src/tools/spec.rs` | `format_plugin_summary()` | 格式化插件摘要信息 |
| `codex-rs/core/src/tools/spec.rs` | `build_specs_with_discoverable_tools()` | 条件注册 tool_suggest 工具 |

### 工具执行
| 文件 | 函数/结构 | 作用 |
|------|----------|------|
| `codex-rs/core/src/tools/handlers/tool_suggest.rs` | `ToolSuggestHandler` | 处理 tool_suggest 调用 |
| `codex-rs/core/src/tools/handlers/tool_suggest.rs` | `ToolSuggestArgs` | 参数结构定义 |
| `codex-rs/core/src/tools/handlers/tool_suggest.rs` | `ToolSuggestResult` | 结果结构定义 |
| `codex-rs/core/src/tools/handlers/tool_suggest.rs` | `build_tool_suggestion_elicitation_request()` | 构建elicitation请求 |
| `codex-rs/core/src/tools/handlers/tool_suggest.rs` | `verify_tool_suggestion_completed()` | 验证建议是否完成 |

### 可发现工具管理
| 文件 | 函数/结构 | 作用 |
|------|----------|------|
| `codex-rs/core/src/tools/discoverable.rs` | `DiscoverableTool` | 可发现工具枚举 |
| `codex-rs/core/src/tools/discoverable.rs` | `DiscoverableToolType` | 工具类型（Connector/Plugin） |
| `codex-rs/core/src/tools/discoverable.rs` | `DiscoverableToolAction` | 操作类型（Install/Enable） |
| `codex-rs/core/src/tools/discoverable.rs` | `DiscoverablePluginInfo` | 插件信息结构 |
| `codex-rs/core/src/tools/discoverable.rs` | `filter_tool_suggest_discoverable_tools_for_client()` | 客户端过滤 |
| `codex-rs/core/src/connectors.rs` | `list_tool_suggest_discoverable_tools_with_auth()` | 获取可发现工具列表 |

### 配置与启用
| 文件 | 代码 | 作用 |
|------|------|------|
| `codex-rs/core/src/tools/spec.rs` | `ToolsConfig::tool_suggest` | 控制是否启用 tool_suggest |
| `codex-rs/core/src/tools/spec.rs` | `ToolsConfig::new()` | 根据 feature 和 search_tool 初始化 |
| `codex-rs/core/src/features.rs` | `Feature::ToolSuggest` | 功能开关定义 |

### 测试
| 文件 | 作用 |
|------|------|
| `codex-rs/core/src/tools/handlers/tool_suggest_tests.rs` | 单元测试 |

---

## 依赖与外部交互

### 内部依赖

```
tool_suggest_description.md
    │
    ├──► spec.rs (模板编译与渲染)
    │       │
    │       ├──► tools/discoverable.rs (DiscoverableTool 定义)
    │       ├──► connectors.rs (获取可发现 Connectors)
    │       └──► plugins/ (获取可发现 Plugins)
    │
    └──► handlers/tool_suggest.rs (执行逻辑)
            │
            ├──► codex_app_server_protocol (Elicitation 请求)
            ├──► codex_rmcp_client (ElicitationAction)
            └──► session (MCP server elicitation)
```

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `codex_app_server_protocol` | 提供 `McpServerElicitationRequest` 等协议类型 |
| `codex_rmcp_client` | 提供 `ElicitationAction` 枚举 |
| `rmcp` | MCP 协议实现，提供 `RequestId` |

### 配置依赖

```rust
// 启用条件 (spec.rs:333)
let include_tool_suggest = include_search_tool && features.enabled(Feature::ToolSuggest);

// 运行时检查 (spec.rs:2772)
if config.tool_suggest
    && let Some(discoverable_tools) = discoverable_tools
        .as_ref()
        .filter(|tools| !tools.is_empty())
{
    // 注册 tool_suggest
}
```

### 客户端限制

```rust
// handlers/tool_suggest.rs:105-111
if args.tool_type == DiscoverableToolType::Plugin
    && turn.app_server_client_name.as_deref() == Some("codex-tui")
{
    return Err(FunctionCallError::RespondToModel(
        "plugin tool suggestions are not available in codex-tui yet".to_string(),
    ));
}
```

---

## 风险、边界与改进建议

### 当前风险

1. **模板与代码耦合**
   - 模板文件 `{{discoverable_tools}}` 变量名硬编码在 Rust 代码中
   - 如果模板修改了变量名而代码未同步，会导致替换失败
   - **建议**：添加编译时模板变量验证或单元测试

2. **工具列表长度风险**
   - 如果可发现工具数量很多，渲染后的描述可能非常长
   - 可能超出模型上下文限制
   - **建议**：添加工具列表长度限制或分页机制

3. **客户端限制硬编码**
   - TUI 不支持 plugin 建议的检查是硬编码的
   - 如果新增客户端类型，需要修改代码
   - **建议**：考虑将客户端能力声明移到配置中

4. **仅支持 Install 操作**
   - 当前代码明确限制 `action_type` 必须为 "install"
   - 但模板和类型定义支持 "enable"
   - **建议**：统一实现或更新文档说明

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 无可发现工具 | tool_suggest 工具不注册 | 合理 |
| suggest_reason 为空 | 返回错误，要求模型重试 | 合理 |
| tool_id 不在列表中 | 返回错误，提示必须匹配列表 | 合理 |
| 用户拒绝建议 | `user_confirmed: false`, `completed: false` | 合理 |
| 用户接受但安装失败 | `user_confirmed: true`, `completed: false` | 合理 |
| TUI 客户端请求 Plugin | 返回错误，提示暂不支持 | 合理 |

### 改进建议

1. **模板验证**
   ```rust
   #[test]
   fn tool_suggest_description_template_has_required_placeholder() {
       assert!(TOOL_SUGGEST_DESCRIPTION_TEMPLATE.contains("{{discoverable_tools}}"));
   }
   ```

2. **动态列表截断**
   - 当可发现工具过多时，按相关性排序并截断
   - 或提供分类/搜索机制

3. **Enable 操作支持**
   - 当前仅实现 Install，考虑实现 Enable 流程
   - 或从模板中移除 Enable 选项避免混淆

4. **建议历史追踪**
   - 当前依赖模型遵守 "don't suggest that tool again" 的指令
   - 考虑在服务端追踪建议历史，强制避免重复

5. **国际化支持**
   - 当前模板为英文硬编码
   - 考虑支持多语言模板

6. **工具推荐评分**
   - 当前仅依赖模型判断 "strongly matches"
   - 可考虑添加相似度评分机制，只有高置信度才建议
