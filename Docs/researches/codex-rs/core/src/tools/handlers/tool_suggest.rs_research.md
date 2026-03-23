# tool_suggest.rs 研究文档

## 场景与职责

`tool_suggest.rs` 实现了 `tool_suggest` 工具处理器，提供可发现工具（Connector/Plugin）的推荐和安装功能。该工具允许模型向用户推荐第三方连接器（如 Google Calendar、Gmail）或插件，并通过交互式确认流程完成安装。是 Codex 扩展生态系统的关键入口。

## 功能点目的

### 1. 工具推荐
根据用户上下文和对话内容，模型可以推荐相关的连接器或插件，帮助用户扩展 Codex 的能力。

### 2. 交互式安装确认
通过 MCP Elicitation 机制向用户展示推荐信息，获取用户确认后才执行安装操作，确保用户知情同意。

### 3. 安装状态验证
安装完成后验证工具是否真正可用，确保推荐流程的完整性。

## 具体技术实现

### 核心数据结构

```rust
pub struct ToolSuggestHandler;

pub(crate) const TOOL_SUGGEST_TOOL_NAME: &str = "tool_suggest";
const TOOL_SUGGEST_APPROVAL_KIND_VALUE: &str = "tool_suggestion";

// 输入参数
#[derive(Debug, Deserialize)]
struct ToolSuggestArgs {
    tool_type: DiscoverableToolType,      // Connector 或 Plugin
    action_type: DiscoverableToolAction,  // 目前仅支持 Install
    tool_id: String,                      // 工具唯一标识
    suggest_reason: String,               // 推荐理由
}

// 输出结果
#[derive(Debug, Serialize, PartialEq, Eq)]
struct ToolSuggestResult {
    completed: bool,              // 是否完成安装
    user_confirmed: bool,         // 用户是否确认
    tool_type: DiscoverableToolType,
    action_type: DiscoverableToolAction,
    tool_id: String,
    tool_name: String,
    suggest_reason: String,
}

// Elicitation 元数据
#[derive(Debug, Serialize, PartialEq, Eq)]
struct ToolSuggestMeta<'a> {
    codex_approval_kind: &'static str,  // "tool_suggestion"
    tool_type: DiscoverableToolType,
    suggest_type: DiscoverableToolAction,
    suggest_reason: &'a str,
    tool_id: &'a str,
    tool_name: &'a str,
    install_url: Option<&'a str>,  // 连接器安装 URL
}
```

### 主处理流程

```rust
#[async_trait]
impl ToolHandler for ToolSuggestHandler {
    type Output = FunctionToolOutput;

    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        // 1. 解析参数
        let args: ToolSuggestArgs = parse_arguments(&arguments)?;

        // 2. 验证推荐理由
        if suggest_reason.is_empty() {
            return Err(FunctionCallError::RespondToModel("suggest_reason must not be empty".to_string()));
        }

        // 3. 验证操作类型
        if args.action_type != DiscoverableToolAction::Install {
            return Err(FunctionCallError::RespondToModel(
                "tool suggestions currently support only action_type=\"install\"".to_string()
            ));
        }

        // 4. 平台限制检查（TUI 暂不支持插件）
        if args.tool_type == DiscoverableToolType::Plugin
            && turn.app_server_client_name.as_deref() == Some("codex-tui")
        {
            return Err(FunctionCallError::RespondToModel(
                "plugin tool suggestions are not available in codex-tui yet".to_string()
            ));
        }

        // 5. 获取可发现工具列表
        let discoverable_tools = connectors::list_tool_suggest_discoverable_tools_with_auth(...).await?;
        let discoverable_tools = filter_tool_suggest_discoverable_tools_for_client(
            discoverable_tools,
            turn.app_server_client_name.as_deref(),
        );

        // 6. 查找目标工具
        let tool = discoverable_tools.into_iter()
            .find(|tool| tool.tool_type() == args.tool_type && tool.id() == args.tool_id)
            .ok_or_else(|| FunctionCallError::RespondToModel("tool_id must match...".to_string()))?;

        // 7. 发送 Elicitation 请求
        let request_id = RequestId::String(format!("tool_suggestion_{call_id}").into());
        let params = build_tool_suggestion_elicitation_request(...);
        let response = session.request_mcp_server_elicitation(turn.as_ref(), request_id, params).await;

        // 8. 判断用户确认
        let user_confirmed = response.as_ref().is_some_and(|r| r.action == ElicitationAction::Accept);

        // 9. 验证安装完成
        let completed = if user_confirmed {
            verify_tool_suggestion_completed(&session, &turn, &tool, auth.as_ref()).await
        } else {
            false
        };

        // 10. 合并连接器选择（如果是连接器）
        if completed && let DiscoverableTool::Connector(connector) = &tool {
            session.merge_connector_selection(HashSet::from([connector.id.clone()])).await;
        }

        // 11. 返回结果
        let content = serde_json::to_string(&ToolSuggestResult { ... })?;
        Ok(FunctionToolOutput::from_text(content, Some(true)))
    }
}
```

### Elicitation 请求构建

```rust
fn build_tool_suggestion_elicitation_request(
    thread_id: String,
    turn_id: String,
    args: &ToolSuggestArgs,
    suggest_reason: &str,
    tool: &DiscoverableTool,
) -> McpServerElicitationRequestParams {
    let tool_name = tool.name().to_string();
    let install_url = tool.install_url().map(ToString::to_string);

    McpServerElicitationRequestParams {
        thread_id,
        turn_id: Some(turn_id),
        server_name: CODEX_APPS_MCP_SERVER_NAME.to_string(),
        request: McpServerElicitationRequest::Form {
            meta: Some(json!(ToolSuggestMeta { ... })),
            message: suggest_reason.to_string(),
            requested_schema: McpElicitationSchema {
                schema_uri: None,
                type_: McpElicitationObjectType::Object,
                properties: BTreeMap::new(),
                required: None,
            },
        },
    }
}
```

### 安装验证

```rust
async fn verify_tool_suggestion_completed(
    session: &Session,
    turn: &TurnContext,
    tool: &DiscoverableTool,
    auth: Option<&CodexAuth>,
) -> bool {
    match tool {
        DiscoverableTool::Connector(connector) => {
            // 刷新 MCP 工具缓存
            let manager = session.services.mcp_connection_manager.read().await;
            match manager.hard_refresh_codex_apps_tools_cache().await {
                Ok(mcp_tools) => {
                    // 检查连接器是否可访问
                    let accessible_connectors = connectors::accessible_connectors_from_mcp_tools(&mcp_tools);
                    verified_connector_suggestion_completed(connector.id.as_str(), &accessible_connectors)
                }
                Err(err) => {
                    warn!("failed to refresh codex apps tools cache...");
                    false
                }
            }
        }
        DiscoverableTool::Plugin(plugin) => {
            // 重新加载配置
            session.reload_user_config_layer().await;
            let config = session.get_config().await;
            verified_plugin_suggestion_completed(plugin.id.as_str(), config.as_ref(), session.services.plugins_manager.as_ref())
        }
    }
}
```

## 关键代码路径与文件引用

### 模块结构
```
tool_suggest.rs
├── ToolSuggestHandler
│   └── ToolHandler trait 实现
├── ToolSuggestArgs (输入参数)
├── ToolSuggestResult (输出结果)
├── ToolSuggestMeta (Elicitation 元数据)
├── build_tool_suggestion_elicitation_request()
├── build_tool_suggestion_meta()
├── verify_tool_suggestion_completed()
│   ├── verified_connector_suggestion_completed()
│   └── verified_plugin_suggestion_completed()
└── tests (tool_suggest_tests.rs)
```

### 依赖关系
```rust
// 协议类型
use codex_app_server_protocol::{
    AppInfo, McpElicitationObjectType, McpElicitationSchema,
    McpServerElicitationRequest, McpServerElicitationRequestParams
};
use codex_rmcp_client::ElicitationAction;
use rmcp::model::RequestId;

// 内部模块
use crate::connectors;  // 连接器管理
use crate::mcp::CODEX_APPS_MCP_SERVER_NAME;
use crate::tools::discoverable::{
    DiscoverableTool, DiscoverableToolAction, DiscoverableToolType,
    filter_tool_suggest_discoverable_tools_for_client
};
```

### 相关文件
- `codex-rs/core/src/tools/handlers/tool_suggest_tests.rs` - 单元测试
- `codex-rs/core/src/tools/discoverable.rs` - 可发现工具类型定义
- `codex-rs/core/src/connectors.rs` - 连接器管理逻辑
- `codex-rs/core/src/mcp_connection_manager.rs` - MCP 工具缓存刷新

## 依赖与外部交互

### 数据流
```
模型调用 tool_suggest
    │
    ├──> 验证参数
    │       ├── tool_type: Connector/Plugin
    │       ├── action_type: Install (唯一支持)
    │       └── suggest_reason: 非空检查
    │
    ├──> 获取可发现工具
    │       └── connectors::list_tool_suggest_discoverable_tools_with_auth()
    │
    ├──> 查找目标工具
    │       └── 匹配 tool_type + tool_id
    │
    ├──> 发送 Elicitation
    │       ├── 构建 ToolSuggestMeta
    │       ├── 构建 McpServerElicitationRequest::Form
    │       └── session.request_mcp_server_elicitation()
    │
    ├──> 等待用户响应
    │       └── ElicitationAction::Accept / Decline
    │
    ├──> 验证安装（如果用户确认）
    │       ├── Connector: 刷新缓存 + 检查 is_accessible
    │       └── Plugin: 重载配置 + 检查 installed
    │
    └──> 返回 ToolSuggestResult
```

### Elicitation 流程
```rust
// 请求
McpServerElicitationRequest::Form {
    meta: Some({
        "codex_approval_kind": "tool_suggestion",
        "tool_type": "connector",
        "suggest_type": "install",
        "suggest_reason": "Plan and reference events from your calendar",
        "tool_id": "connector_xxx",
        "tool_name": "Google Calendar",
        "install_url": "https://chatgpt.com/apps/..."
    }),
    message: "Plan and reference events from your calendar",
    requested_schema: { ... }
}

// 响应
ElicitationResponse {
    action: ElicitationAction::Accept,  // 或 Decline
    content: None,
    meta: None,
}
```

## 风险、边界与改进建议

### 潜在风险

1. **平台限制硬编码**
   ```rust
   if args.tool_type == DiscoverableToolType::Plugin
       && turn.app_server_client_name.as_deref() == Some("codex-tui")
   ```
   - 硬编码客户端名称
   - 新增客户端时需要修改代码

2. **操作类型限制**
   ```rust
   if args.action_type != DiscoverableToolAction::Install
   ```
   - 仅支持 Install，不支持 Enable
   - 错误信息提示不够友好

3. **验证可靠性**
   - 连接器验证依赖缓存刷新成功
   - 插件验证依赖配置重载
   - 网络延迟可能导致验证失败

4. **竞态条件**
   ```rust
   // 用户确认后，其他会话可能同时修改状态
   let completed = verify_tool_suggestion_completed(...).await;
   if completed { session.merge_connector_selection(...).await; }
   ```

### 边界情况

1. **重复推荐**
   - 同一工具多次推荐，用户多次确认
   - 未检查工具是否已安装

2. **推荐理由长度**
   ```rust
   // 仅检查非空，未限制长度
   if suggest_reason.is_empty() { ... }
   ```
   - 超长理由可能影响 UI 显示

3. **工具 ID 不存在**
   ```rust
   let tool = discoverable_tools.into_iter()
       .find(...)
       .ok_or_else(|| FunctionCallError::RespondToModel(...))?;
   ```
   - 返回通用错误，未提示可用工具列表

4. **Elicitation 超时**
   - 测试未覆盖用户不响应的场景
   - 超时后行为未明确定义

### 改进建议

1. **增强平台适配**
   ```rust
   // 使用特性标志而非硬编码
   fn supports_plugin_suggestions(client_name: Option<&str>) -> bool {
       match client_name {
           Some("codex-tui") => false,
           Some("codex-vscode") => true,
           _ => true,  // 默认允许
       }
   }
   ```

2. **预检查已安装状态**
   ```rust
   // 推荐前检查是否已安装
   if tool.is_already_installed() {
       return Err(FunctionCallError::RespondToModel(
           "Tool is already installed".to_string()
       ));
   }
   ```

3. **增强验证重试**
   ```rust
   // 添加指数退避重试
   let completed = retry_with_backoff(
       || verify_tool_suggestion_completed(...),
       RetryPolicy::default(),
   ).await;
   ```

4. **支持 Enable 操作**
   ```rust
   match args.action_type {
       DiscoverableToolAction::Install => { ... }
       DiscoverableToolAction::Enable => {
           // 实现启用逻辑
       }
   }
   ```

5. **改进错误信息**
   ```rust
   .ok_or_else(|| {
       let available = discoverable_tools.iter()
           .map(|t| format!("{} ({})", t.id(), t.name()))
           .collect::<Vec<_>>()
           .join(", ");
       FunctionCallError::RespondToModel(format!(
           "tool_id must match one of: {}", available
       ))
   })?;
   ```

6. **添加指标收集**
   ```rust
   // 记录推荐成功率
   tracing::info!(
       tool_id = %args.tool_id,
       tool_type = ?args.tool_type,
       user_confirmed = user_confirmed,
       completed = completed,
       "tool_suggest completed"
   );
   ```

### 测试覆盖

当前测试在 `tool_suggest_tests.rs` 中覆盖：
- Elicitation 请求构建
- 元数据结构验证
- 客户端过滤（TUI）
- 连接器验证逻辑
- 插件安装验证

建议添加：
- 用户拒绝场景
- 超时场景
- 重复推荐场景
- 网络故障恢复
