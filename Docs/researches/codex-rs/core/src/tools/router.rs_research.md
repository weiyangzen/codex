# router.rs 深度研究文档

## 场景与职责

`router.rs` 是 Codex 工具系统的路由层，负责将模型返回的 `ResponseItem` 转换为内部 `ToolCall`，并分发到注册表执行。主要职责包括：

1. **协议转换**：将 API 响应项转换为内部工具调用表示
2. **工具调用构建**：解析不同类型的响应项（FunctionCall、ToolSearchCall、CustomToolCall、LocalShellCall）
3. **MCP 工具识别**：识别并解析 MCP 工具名称格式
4. **路由分发**：将工具调用分发到注册表执行
5. **Code Mode 支持**：支持 Code Mode 下的特殊工具处理

该模块是模型响应和工具执行之间的桥梁，处理所有进入工具系统的请求。

## 功能点目的

### 1. 工具调用结构 (ToolCall)

```rust
pub struct ToolCall {
    pub tool_name: String,
    pub tool_namespace: Option<String>,
    pub call_id: String,
    pub payload: ToolPayload,
}
```

统一的工具调用表示，支持命名空间隔离（用于 MCP 工具）。

### 2. 工具路由器 (ToolRouter)

```rust
pub struct ToolRouter {
    registry: ToolRegistry,
    specs: Vec<ConfiguredToolSpec>,
    model_visible_specs: Vec<ToolSpec>,
}
```

- **registry**: 工具处理器注册表
- **specs**: 所有配置的工具规格（含并行标志）
- **model_visible_specs**: 对模型可见的工具规格（Code Mode 过滤后）

### 3. 路由参数 (ToolRouterParams)

```rust
pub(crate) struct ToolRouterParams<'a> {
    pub(crate) mcp_tools: Option<HashMap<String, Tool>>,
    pub(crate) app_tools: Option<HashMap<String, ToolInfo>>,
    pub(crate) discoverable_tools: Option<Vec<DiscoverableTool>>,
    pub(crate) dynamic_tools: &'a [DynamicToolSpec],
}
```

构建路由器时传入的各类工具源。

### 4. 工具调用源 (ToolCallSource)

```rust
pub enum ToolCallSource {
    Direct,    // 直接调用（来自模型）
    JsRepl,    // 来自 JS REPL
    CodeMode,  // 来自 Code Mode
}
```

区分工具调用的来源，用于权限控制。

### 5. Code Mode 过滤

```rust
let model_visible_specs = if config.code_mode_only_enabled {
    specs
        .iter()
        .filter_map(|configured_tool| {
            if !is_code_mode_nested_tool(configured_tool.spec.name()) {
                Some(configured_tool.spec.clone())
            } else {
                None
            }
        })
        .collect()
}
```

当启用 `code_mode_only_enabled` 时，过滤掉 Code Mode 嵌套工具。

## 具体技术实现

### 核心构建流程

```
┌─────────────────────────────────────────────────────────────────┐
│              ToolRouter::from_config()                           │
├─────────────────────────────────────────────────────────────────┤
│ 1. 构建工具规格                                                  │
│    └─ build_specs_with_discoverable_tools()                     │
│       ├─ 基础工具（shell、apply_patch 等）                      │
│       ├─ MCP 工具                                                │
│       ├─ App 工具                                                │
│       ├─ 可发现工具                                              │
│       └─ 动态工具                                                │
├─────────────────────────────────────────────────────────────────┤
│ 2. 构建注册表                                                    │
│    └─ ToolRegistryBuilder::build()                              │
├─────────────────────────────────────────────────────────────────┤
│ 3. 过滤 Code Mode 工具（如启用）                                │
│    └─ is_code_mode_nested_tool()                                │
└─────────────────────────────────────────────────────────────────┘
```

### 工具调用构建流程

```
┌─────────────────────────────────────────────────────────────────┐
│           ToolRouter::build_tool_call()                          │
├─────────────────────────────────────────────────────────────────┤
│ ResponseItem::FunctionCall                                       │
│   ├─ 解析 MCP 工具名？                                           │
│   │   ├─ 是 → ToolPayload::Mcp { server, tool, raw_arguments }  │
│   │   └─ 否 → ToolPayload::Function { arguments }               │
│   └─ 返回 ToolCall                                               │
├─────────────────────────────────────────────────────────────────┤
│ ResponseItem::ToolSearchCall                                     │
│   ├─ execution == "client"？                                     │
│   │   ├─ 是 → ToolPayload::ToolSearch { arguments }             │
│   │   └─ 否 → 返回 None（服务器端执行）                         │
│   └─ 返回 ToolCall                                               │
├─────────────────────────────────────────────────────────────────┤
│ ResponseItem::CustomToolCall                                     │
│   └─ ToolPayload::Custom { input }                              │
├─────────────────────────────────────────────────────────────────┤
│ ResponseItem::LocalShellCall                                     │
│   └─ ToolPayload::LocalShell { params: ShellToolCallParams }    │
├─────────────────────────────────────────────────────────────────┤
│ 其他                                                             │
│   └─ 返回 None                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 关键代码路径

#### MCP 工具名称解析

```rust
// router.rs:129-147
if let Some((server, tool)) = session.parse_mcp_tool_name(&name, &namespace).await {
    Ok(Some(ToolCall {
        tool_name: name,
        tool_namespace: namespace,
        call_id,
        payload: ToolPayload::Mcp {
            server,
            tool,
            raw_arguments: arguments,
        },
    }))
} else {
    Ok(Some(ToolCall {
        tool_name: name,
        tool_namespace: namespace,
        call_id,
        payload: ToolPayload::Function { arguments },
    }))
}
```

#### JS REPL 工具限制

```rust
// router.rs:230-238
if source == ToolCallSource::Direct
    && turn.tools_config.js_repl_tools_only
    && !matches!(tool_name.as_str(), "js_repl" | "js_repl_reset")
{
    return Err(FunctionCallError::RespondToModel(
        "direct tool calls are disabled; use js_repl and codex.tool(...) instead"
            .to_string(),
    ));
}
```

#### ToolSearchCall 处理

```rust
// router.rs:149-168
ResponseItem::ToolSearchCall {
    call_id: Some(call_id),
    execution,
    arguments,
    ..
} if execution == "client" => {
    let arguments: SearchToolCallParams = serde_json::from_value(arguments)?;
    Ok(Some(ToolCall {
        tool_name: "tool_search".to_string(),
        tool_namespace: None,
        call_id,
        payload: ToolPayload::ToolSearch { arguments },
    }))
}
ResponseItem::ToolSearchCall { .. } => Ok(None),
```

### 数据结构详解

#### ToolRouter

```rust
pub struct ToolRouter {
    registry: ToolRegistry,                    // 工具处理器注册表
    specs: Vec<ConfiguredToolSpec>,            // 所有工具规格
    model_visible_specs: Vec<ToolSpec>,        // 对模型可见的规格
}
```

#### ToolCall

```rust
pub struct ToolCall {
    pub tool_name: String,           // 工具名称
    pub tool_namespace: Option<String>, // 命名空间（MCP 工具）
    pub call_id: String,             // 调用 ID
    pub payload: ToolPayload,        // 调用参数
}
```

#### ToolRouterParams

```rust
pub(crate) struct ToolRouterParams<'a> {
    pub(crate) mcp_tools: Option<HashMap<String, Tool>>,        // MCP 工具定义
    pub(crate) app_tools: Option<HashMap<String, ToolInfo>>,    // App 工具信息
    pub(crate) discoverable_tools: Option<Vec<DiscoverableTool>>, // 可发现工具
    pub(crate) dynamic_tools: &'a [DynamicToolSpec],            // 动态工具
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::tools::registry::*` | ToolRegistry、ConfiguredToolSpec |
| `crate::tools::context::*` | ToolCallSource、ToolInvocation、ToolPayload |
| `crate::tools::spec::*` | ToolsConfig、build_specs_with_discoverable_tools |
| `crate::tools::code_mode::*` | is_code_mode_nested_tool |
| `crate::codex::Session` | MCP 工具名称解析 |
| `crate::sandboxing::SandboxPermissions` | LocalShell 权限 |

### 外部协议依赖

| 协议类型 | 用途 |
|----------|------|
| `ResponseItem` | API 响应项类型 |
| `LocalShellAction` | LocalShell 动作类型 |
| `ShellToolCallParams` | Shell 工具参数 |
| `SearchToolCallParams` | 工具搜索参数 |
| `DynamicToolSpec` | 动态工具规格 |

### 调用关系

```
ToolRouter::from_config()
    ├── build_specs_with_discoverable_tools()     [spec.rs]
    │   ├── 基础工具规格
    │   ├── MCP 工具规格
    │   ├── App 工具规格
    │   └── 可发现工具规格
    ├── ToolRegistryBuilder::build()              [registry.rs]
    └── is_code_mode_nested_tool()                [code_mode.rs]

ToolRouter::build_tool_call()
    ├── session.parse_mcp_tool_name()             [codex.rs]
    └── serde_json::from_value()                  [参数解析]

ToolRouter::dispatch_tool_call_with_code_mode_result()
    ├── js_repl_tools_only 检查                   [权限控制]
    ├── ToolInvocation 构建                       [上下文封装]
    └── registry.dispatch_any()                   [registry.rs]
```

## 风险、边界与改进建议

### 已知风险

1. **MCP 工具名称解析依赖 Session**
   - `parse_mcp_tool_name` 是异步方法，需要 Session
   - 如果 Session 状态不一致，可能错误分类工具

2. **ToolSearchCall 执行端判断**
   - 仅根据 `execution == "client"` 判断是否本地执行
   - 如果服务器返回错误值，可能错误处理

3. **LocalShellCall ID 处理**
   ```rust
   let call_id = call_id.or(id).ok_or(FunctionCallError::MissingLocalShellCallId)?;
   ```
   - 优先使用 `call_id`，回退到 `id`
   - 两者都缺失时返回错误

4. **js_repl_tools_only 绕过风险**
   - 仅检查 `source == ToolCallSource::Direct`
   - 如果其他来源被错误标记，可能绕过限制

### 边界情况

1. **空命名空间字符串**
   - `Some("")` 和 `None` 在 MCP 解析时可能表现不同

2. **Code Mode 嵌套工具**
   - `is_code_mode_nested_tool` 需要与 `code_mode.rs` 保持同步
   - 不一致可能导致工具对模型不可见

3. **并发构建**
   - `ToolRouter` 构建不是异步的
   - 大量工具可能导致构建耗时

### 改进建议

1. **缓存 MCP 解析结果**
   ```rust
   // 建议：在 Session 中缓存解析结果
   struct McpToolCache {
       parsed: HashMap<String, Option<(String, String)>>,
   }
   ```

2. **验证 ToolSearchCall 参数**
   ```rust
   // 建议：添加参数验证
   if arguments.limit > MAX_SEARCH_LIMIT {
       return Err(FunctionCallError::RespondToModel("limit too large".to_string()));
   }
   ```

3. **改进错误信息**
   ```rust
   // 建议：更详细的 LocalShellCall ID 错误
   FunctionCallError::MissingLocalShellCallId => {
       "LocalShellCall missing both 'call_id' and 'id' fields"
   }
   ```

4. **Code Mode 过滤优化**
   ```rust
   // 建议：使用 HashSet 提高查找效率
   let nested_tools: HashSet<&str> = CODE_MODE_NESTED_TOOLS.iter().cloned().collect();
   ```

5. **工具规格缓存**
   - 缓存 `model_visible_specs` 的计算结果
   - 仅在配置变更时重新计算

6. **添加工具路由指标**
   - 记录每种 ResponseItem 类型的处理次数
   - 跟踪 MCP 工具解析成功率

### 相关文件引用

| 文件 | 关系 |
|------|------|
| `codex-rs/core/src/tools/router_tests.rs` | 单元测试 |
| `codex-rs/core/src/tools/registry.rs` | ToolRegistry 使用 |
| `codex-rs/core/src/tools/spec.rs` | 工具规格构建 |
| `codex-rs/core/src/tools/code_mode.rs` | Code Mode 嵌套工具判断 |
| `codex-rs/core/src/tools/context.rs` | ToolCall、ToolPayload 定义 |
| `codex-rs/core/src/codex.rs` | Session::parse_mcp_tool_name |
| `codex-rs/core/src/mcp_connection_manager.rs` | MCP 工具信息 |
