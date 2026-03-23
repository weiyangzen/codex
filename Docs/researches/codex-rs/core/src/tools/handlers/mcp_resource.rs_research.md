# mcp_resource.rs 研究文档

## 场景与职责

`mcp_resource.rs` 实现了 MCP (Model Context Protocol) 资源管理工具处理器 (`McpResourceHandler`)。该处理器提供三个核心功能：

1. **`list_mcp_resources`** - 列出 MCP 服务器上的资源
2. **`list_mcp_resource_templates`** - 列出资源模板
3. **`read_mcp_resource`** - 读取特定资源内容

**核心职责：**
- 为 AI 模型提供统一的 MCP 资源访问接口
- 支持单服务器查询和全服务器聚合查询
- 实现分页支持（cursor-based）
- 提供标准化的事件通知（begin/end）
- 处理参数解析和验证

## 功能点目的

### 1. 资源列表 (`list_mcp_resources`)

**单服务器模式：**
- 指定 `server` 参数时，查询特定 MCP 服务器
- 支持 `cursor` 分页
- 返回资源列表和 `next_cursor`

**全服务器模式：**
- 不指定 `server` 时，聚合所有服务器的资源
- 按服务器名称排序
- 不支持 cursor 分页（返回全部）

### 2. 资源模板列表 (`list_mcp_resource_templates`)

与资源列表类似，但查询的是资源模板（URI 模板模式）：
- 支持单服务器和全服务器查询
- 支持 cursor 分页（单服务器模式）

### 3. 资源读取 (`read_mcp_resource`)

- 必须指定 `server` 和 `uri`
- 调用 MCP 服务器的 `resources/read` 方法
- 返回资源内容和元数据

### 4. 事件通知

每个操作都会发送 begin/end 事件：
- `McpToolCallBeginEvent`：操作开始时发送
- `McpToolCallEndEvent`：操作结束时发送，包含耗时和结果

## 具体技术实现

### 数据结构

**参数结构：**
```rust
#[derive(Debug, Deserialize, Default)]
struct ListResourcesArgs {
    #[serde(default)]
    server: Option<String>,   // None = 查询所有服务器
    #[serde(default)]
    cursor: Option<String>,   // 分页游标
}

#[derive(Debug, Deserialize)]
struct ReadResourceArgs {
    server: String,  // 必需
    uri: String,     // 必需
}
```

**响应结构：**
```rust
// 带服务器信息的资源包装
#[derive(Debug, Serialize)]
struct ResourceWithServer {
    server: String,
    #[serde(flatten)]
    resource: Resource,  // 来自 rmcp crate
}

// 列表响应 payload
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ListResourcesPayload {
    #[serde(skip_serializing_if = "Option::is_none")]
    server: Option<String>,
    resources: Vec<ResourceWithServer>,
    #[serde(skip_serializing_if = "Option::is_none")]
    next_cursor: Option<String>,
}

// 读取响应 payload
#[derive(Debug, Serialize)]
struct ReadResourcePayload {
    server: String,
    uri: String,
    #[serde(flatten)]
    result: ReadResourceResult,  // 来自 rmcp crate
}
```

### 核心算法流程

**1. 工具分发：**
```rust
async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
    match tool_name.as_str() {
        "list_mcp_resources" => handle_list_resources(...).await,
        "list_mcp_resource_templates" => handle_list_resource_templates(...).await,
        "read_mcp_resource" => handle_read_resource(...).await,
        other => Err(FunctionCallError::RespondToModel(...)),
    }
}
```

**2. 列表资源流程：**
```rust
async fn handle_list_resources(...) -> Result<FunctionToolOutput, FunctionCallError> {
    // 1. 解析参数
    let args: ListResourcesArgs = parse_args_with_default(arguments.clone())?;
    
    // 2. 规范化字符串（trim 空字符串为 None）
    let server = normalize_optional_string(server);
    let cursor = normalize_optional_string(cursor);
    
    // 3. 创建调用描述
    let invocation = McpInvocation { ... };
    
    // 4. 发送 begin 事件
    emit_tool_call_begin(&session, turn.as_ref(), &call_id, invocation.clone()).await;
    let start = Instant::now();
    
    // 5. 执行查询
    let payload_result: Result<ListResourcesPayload, FunctionCallError> = async {
        if let Some(server_name) = server.clone() {
            // 单服务器模式
            let params = cursor.map(|c| PaginatedRequestParams { ... });
            let result = session.list_resources(&server_name, params).await?;
            Ok(ListResourcesPayload::from_single_server(server_name, result))
        } else {
            // 全服务器模式
            if cursor.is_some() {
                return Err("cursor can only be used when a server is specified");
            }
            let resources = session.services.mcp_connection_manager
                .read().await
                .list_all_resources().await;
            Ok(ListResourcesPayload::from_all_servers(resources))
        }
    }.await;
    
    // 6. 处理结果并发送 end 事件
    match payload_result {
        Ok(payload) => {
            let output = serialize_function_output(payload)?;
            emit_tool_call_end(..., Ok(...)).await;
            Ok(output)
        }
        Err(err) => {
            emit_tool_call_end(..., Err(...)).await;
            Err(err)
        }
    }
}
```

**3. 全服务器资源聚合：**
```rust
fn from_all_servers(resources_by_server: HashMap<String, Vec<Resource>>) -> Self {
    // 1. 按服务器名称排序
    let mut entries: Vec<(String, Vec<Resource>)> = resources_by_server.into_iter().collect();
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    
    // 2. 扁平化为 ResourceWithServer 列表
    let mut resources = Vec::new();
    for (server, server_resources) in entries {
        for resource in server_resources {
            resources.push(ResourceWithServer::new(server.clone(), resource));
        }
    }
    
    Self { server: None, resources, next_cursor: None }
}
```

### 关键代码路径

**入口点：**
```rust
// mcp_resource.rs:189-243
impl ToolHandler for McpResourceHandler {
    fn kind(&self) -> ToolKind { ToolKind::Function }
    
    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        // 根据 tool_name 分发到具体处理函数
    }
}
```

**事件发送：**
```rust
// mcp_resource.rs:555-591
async fn emit_tool_call_begin(...) {
    session.send_event(turn, EventMsg::McpToolCallBegin(...)).await;
}

async fn emit_tool_call_end(...) {
    session.send_event(turn, EventMsg::McpToolCallEnd(...)).await;
}
```

**参数解析辅助函数：**
```rust
// mcp_resource.rs:593-663
fn normalize_optional_string(input: Option<String>) -> Option<String> {
    input.and_then(|value| {
        let trimmed = value.trim().to_string();
        if trimmed.is_empty() { None } else { Some(trimmed) }
    })
}

fn parse_arguments(raw_args: &str) -> Result<Option<Value>, FunctionCallError> {
    if raw_args.trim().is_empty() {
        Ok(None)
    } else {
        serde_json::from_str(raw_args).map_err(...)
    }
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::codex::{Session, TurnContext}` | 会话和回合上下文 |
| `crate::protocol::{EventMsg, McpInvocation, McpToolCallBeginEvent, McpToolCallEndEvent}` | 事件协议 |
| `crate::tools::registry::{ToolHandler, ToolKind}` | 工具处理器 trait |
| `crate::tools::context::{ToolInvocation, ToolPayload, FunctionToolOutput}` | 工具调用上下文 |
| `crate::function_tool::FunctionCallError` | 错误类型 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `rmcp::model::*` | MCP 协议类型（Resource, ResourceTemplate, PaginatedRequestParams 等） |
| `codex_protocol::mcp::CallToolResult` | MCP 调用结果 |
| `codex_protocol::models::function_call_output_content_items_to_text` | 输出内容转换 |
| `serde::{Deserialize, Serialize}` | 序列化 |
| `async_trait` | 异步 trait |

### MCP 连接管理

通过 `McpConnectionManager` 与 MCP 服务器交互：
```rust
// 单服务器查询
session.list_resources(&server_name, params).await

// 全服务器查询
session.services.mcp_connection_manager
    .read().await
    .list_all_resources().await
```

## 风险、边界与改进建议

### 已知风险

1. **全服务器查询性能**
   - `list_all_resources()` 会查询所有连接的 MCP 服务器
   - 服务器数量多或网络延迟高时，响应时间可能很长
   - **建议：** 添加超时机制或并行查询

2. **空字符串处理**
   - 使用 `normalize_optional_string` 将空字符串转为 `None`
   - 这可能导致用户显式传递 `""` 时被忽略

3. **错误处理一致性**
   - 单服务器模式返回具体错误
   - 全服务器模式可能部分失败但不报告

### 边界情况

| 场景 | 当前行为 |
|------|----------|
| server 参数为空字符串 | 视为 None（查询所有服务器） |
| cursor 参数为空字符串 | 视为 None（无游标） |
| 全服务器查询 + cursor | 返回错误 "cursor can only be used when a server is specified" |
| 读取不存在的资源 | 依赖底层 MCP 服务器返回错误 |
| 序列化失败 | 返回 `FunctionCallError::RespondToModel` |

### 改进建议

1. **添加超时控制**
```rust
let payload_result = tokio::time::timeout(
    Duration::from_secs(30),
    async { ... }
).await.map_err(|_| FunctionCallError::RespondToModel("timeout".to_string()))?;
```

2. **优化全服务器查询**
```rust
// 使用 futures::future::join_all 并行查询
let futures = servers.iter().map(|s| session.list_resources(s, None));
let results = futures::future::join_all(futures).await;
```

3. **增强错误信息**
```rust
// 区分服务器连接错误和资源不存在错误
Err(FunctionCallError::RespondToModel(
    format!("Server '{}' not found or not connected", server_name)
))
```

4. **添加缓存机制**
- 资源列表变化不频繁，可以考虑添加短时间缓存
- 减少重复的 MCP 服务器查询

### 测试覆盖

测试文件 `mcp_resource_tests.rs` 覆盖：
- 序列化逻辑（`ResourceWithServer`, `ListResourcesPayload`）
- 参数解析（`parse_arguments`）
- 结果构建（`call_tool_result_from_content`）

**测试盲点：**
- 未测试实际的 MCP 服务器调用（需要 mock）
- 未测试错误处理路径
- 未测试事件发送

### 代码统计

| 指标 | 数值 |
|------|------|
| 代码行数 | ~667 行 |
| 主要函数 | 3 个处理函数 + 辅助函数 |
| 数据结构 | 8 个结构体 |

这是一个功能完整的 MCP 资源管理实现，提供了统一的资源访问抽象层。
