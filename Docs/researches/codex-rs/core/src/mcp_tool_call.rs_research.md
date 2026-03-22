# mcp_tool_call.rs 研究文档

## 场景与职责

`mcp_tool_call.rs` 是 Codex 核心库中处理 MCP (Model Context Protocol) 工具调用的核心模块。它负责：

1. **MCP 工具调用生命周期管理**：处理从接收工具调用请求到返回结果的完整流程
2. **审批流程控制**：实现多层次的工具调用审批机制，包括自动审批、用户确认、Guardian 审查等
3. **安全监控集成**：与 ARC (AI Risk Controller) 安全监控系统集成，对高风险操作进行拦截
4. **持久化审批状态**：支持将用户审批选择持久化到配置文件，避免重复询问
5. **事件通知**：发送工具调用开始/结束事件，用于 UI 更新和日志记录

该模块是 Codex 与外部 MCP 服务器（包括内置的 codex_apps 服务器）交互的关键桥梁，确保工具调用在安全、可控的前提下执行。

## 功能点目的

### 1. 主入口函数 `handle_mcp_tool_call`

**目的**：作为 MCP 工具调用的统一入口，协调整个调用流程。

**关键流程**：
1. 解析工具调用参数（JSON 格式）
2. 查询工具元数据（annotations、connector 信息等）
3. 检查工具是否被配置禁用
4. 发送 `McpToolCallBegin` 事件
5. 执行审批流程（如需要）
6. 调用实际工具并获取结果
7. 清理结果中的图像内容（如模型不支持图像输入）
8. 发送 `McpToolCallEnd` 事件
9. 记录分析数据

### 2. 审批决策系统

**目的**：根据工具注解和用户配置决定是否需要审批，以及审批方式。

**决策类型 (`McpToolApprovalDecision`)**：
- `Accept`：直接执行
- `AcceptForSession`：执行并记住本次会话的选择
- `AcceptAndRemember`：执行并持久化到配置文件
- `Decline`：拒绝执行
- `Cancel`：取消执行
- `BlockedBySafetyMonitor`：被安全监控拦截

**审批模式 (`AppToolApproval`)**：
- `Auto`：自动模式，根据注解决定是否需要审批
- `Approve`：总是需要审批（除非注解表明安全）
- `Prompt`：提示模式，简化审批选项

### 3. 审批键值系统

**目的**：支持会话级和持久化的审批记忆功能。

**键值结构 (`McpToolApprovalKey`)**：
```rust
struct McpToolApprovalKey {
    server: String,        // MCP 服务器名称
    connector_id: Option<String>,  // 连接器 ID（仅 codex_apps）
    tool_name: String,     // 工具名称
}
```

- **Session 级记忆**：仅当前会话有效，存储在内存中
- **Persistent 级记忆**：写入 `config.toml` 文件，跨会话保留

### 4. ARC 安全监控集成

**目的**：对高风险工具调用进行 AI 驱动的安全审查。

**集成点**：
- `maybe_monitor_auto_approved_mcp_tool_call`：对自动审批的调用进行监控
- `prepare_arc_request_action`：构建 ARC 请求数据
- 根据 ARC 返回结果决定是否拦截、询问用户或通过

### 5. Guardian 审批代理

**目的**：将审批决策委托给 Guardian 子代理进行智能审查。

**流程**：
1. 构建 `GuardianApprovalRequest` 请求
2. 调用 `review_approval_request` 进行审查
3. 将 Guardian 决策转换为 MCP 工具审批决策

### 6. MCP Elicitation 系统

**目的**：通过 MCP 协议本身进行用户确认（而非传统的 RequestUserInput）。

**关键结构**：
- `McpToolApprovalElicitationRequest`：Elicitation 请求参数
- `build_mcp_tool_approval_elicitation_request`：构建请求
- `parse_mcp_tool_approval_elicitation_response`：解析响应

### 7. 工具结果清理

**目的**：确保返回给模型的内容符合其能力（如图像输入支持）。

**函数**：`sanitize_mcp_tool_result_for_model`
- 如果模型不支持图像输入，将图像内容替换为文本占位符
- 保留其他所有内容不变

## 具体技术实现

### 关键数据结构

```rust
// 工具调用审批元数据
pub(crate) struct McpToolApprovalMetadata {
    annotations: Option<ToolAnnotations>,  // 工具注解（destructive_hint 等）
    connector_id: Option<String>,          // 连接器 ID
    connector_name: Option<String>,        // 连接器显示名称
    connector_description: Option<String>, // 连接器描述
    tool_title: Option<String>,            // 工具标题
    tool_description: Option<String>,      // 工具描述
    codex_apps_meta: Option<serde_json::Map<String, serde_json::Value>>,  // 扩展元数据
}

// 审批提示选项
struct McpToolApprovalPromptOptions {
    allow_session_remember: bool,    // 是否允许会话级记忆
    allow_persistent_approval: bool, // 是否允许持久化审批
}
```

### 审批判断逻辑

```rust
fn requires_mcp_tool_approval(annotations: &ToolAnnotations) -> bool {
    // 如果标记为破坏性操作，必须审批
    if annotations.destructive_hint == Some(true) {
        return true;
    }
    // 非只读且涉及外部世界的操作需要审批
    annotations.read_only_hint == Some(false) && annotations.open_world_hint == Some(true)
}
```

### 持久化审批配置

```rust
async fn persist_codex_app_tool_approval(
    codex_home: &Path,
    connector_id: &str,
    tool_name: &str,
) -> anyhow::Result<()> {
    ConfigEditsBuilder::new(codex_home)
        .with_edits([ConfigEdit::SetPath {
            segments: vec![
                "apps".to_string(),
                connector_id.to_string(),
                "tools".to_string(),
                tool_name.to_string(),
                "approval_mode".to_string(),
            ],
            value: value("approve"),
        }])
        .apply()
        .await
}
```

写入的配置格式示例：
```toml
[apps.calendar.tools."calendar/list_events"]
approval_mode = "approve"
```

### 完整审批流程

```
handle_mcp_tool_call
├── lookup_mcp_tool_metadata (查询工具元数据)
├── 检查工具是否被禁用
├── maybe_request_mcp_tool_approval (审批流程)
│   ├── requires_mcp_tool_approval (检查注解)
│   ├── maybe_monitor_auto_approved_mcp_tool_call (ARC 监控)
│   ├── 检查 session/persistent 记忆
│   ├── routes_approval_to_guardian (是否路由到 Guardian)
│   │   └── review_approval_request
│   ├── tool_call_mcp_elicitation_enabled (使用 MCP Elicitation)
│   │   ├── build_mcp_tool_approval_elicitation_request
│   │   └── request_mcp_server_elicitation
│   └── 使用传统 RequestUserInput
├── sess.call_tool (实际执行工具调用)
├── sanitize_mcp_tool_result_for_model (清理结果)
└── notify_mcp_tool_call_event (发送结束事件)
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `mcp_tool_approval_templates.rs` | 工具审批提示模板渲染 |
| `mcp_tool_call_tests.rs` | 单元测试 |
| `guardian.rs` | Guardian 审批代理集成 |
| `arc_monitor.rs` | ARC 安全监控集成 |
| `connectors.rs` | 连接器配置查询 |
| `config/edit.rs` | 配置文件编辑 |
| `codex.rs` | Session 和 TurnContext 定义 |
| `protocol.rs` (protocol crate) | `McpInvocation`, `McpToolCallBeginEvent` 等 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `codex_protocol` | 协议类型定义 (`McpInvocation`, `CallToolResult` 等) |
| `codex_app_server_protocol` | MCP Elicitation 相关类型 |
| `codex_rmcp_client` | ElicitationAction, ElicitationResponse |
| `rmcp` | ToolAnnotations, RequestId |
| `toml_edit` | 配置文件编辑 |

### 关键常量

```rust
const MCP_TOOL_APPROVAL_QUESTION_ID_PREFIX: &str = "mcp_tool_call_approval";
const MCP_TOOL_APPROVAL_ACCEPT: &str = "Allow";
const MCP_TOOL_APPROVAL_ACCEPT_FOR_SESSION: &str = "Allow for this session";
const MCP_TOOL_APPROVAL_ACCEPT_AND_REMEMBER: &str = "Allow and don't ask me again";
const MCP_TOOL_APPROVAL_CANCEL: &str = "Cancel";
const MCP_TOOL_APPROVAL_DECLINE_SYNTHETIC: &str = "__codex_mcp_decline__";  // 内部使用

// 持久化键值
const MCP_TOOL_APPROVAL_PERSIST_SESSION: &str = "session";
const MCP_TOOL_APPROVAL_PERSIST_ALWAYS: &str = "always";
```

## 依赖与外部交互

### 1. MCP 连接管理器

通过 `sess.services.mcp_connection_manager` 查询工具元数据：
```rust
let tools = sess.services.mcp_connection_manager.read().await.list_all_tools().await;
```

### 2. 状态数据库

标记线程内存模式被污染（当使用 MCP 工具时）：
```rust
state_db::mark_thread_memory_mode_polluted(
    sess.services.state_db.as_deref(),
    sess.conversation_id,
    "mcp_tool_call",
).await;
```

### 3. 分析事件客户端

跟踪应用使用情况：
```rust
sess.services.analytics_events_client.track_app_used(
    tracking,
    AppInvocation { connector_id, app_name, invocation_type },
);
```

### 4. 配置文件系统

通过 `ConfigEditsBuilder` 持久化审批设置到用户配置。

### 5. Guardian 审批代理

当 `routes_approval_to_guardian` 返回 true 时，将审批请求发送给 Guardian 子代理处理。

### 6. ARC 安全监控

调用 `/codex/safety/arc` 端点进行风险评估，根据返回的 `ArcMonitorOutcome` 决定后续处理。

## 风险、边界与改进建议

### 已知风险

1. **配置持久化失败回退**：当持久化到配置文件失败时，仅回退到会话级记忆，用户可能在重启后再次看到相同的审批提示。

2. **ARC 监控延迟**：ARC 调用是同步的，可能增加工具调用的响应延迟。

3. **图像内容清理**：`sanitize_mcp_tool_result_for_model` 仅检查模型是否支持图像输入，但不检查图像大小或格式，可能导致后续处理错误。

4. **并发审批状态竞争**：`mcp_tool_approval_is_remembered` 和 `remember_mcp_tool_approval` 之间可能存在竞争条件。

### 边界情况

1. **空参数处理**：空字符串参数被解析为 `None`，而非空的 JSON 对象。

2. **非 codex_apps 服务器**：自定义 MCP 服务器不支持持久化审批，仅支持会话级记忆。

3. **Guardian 不可用**：当 Guardian 审查失败时，行为取决于具体错误处理，可能回退到传统审批流程。

4. **工具元数据缺失**：当无法查询到工具元数据时，使用默认策略，可能导致意外的审批行为。

### 改进建议

1. **批量 ARC 检查**：考虑对多个工具调用进行批量 ARC 检查，减少网络往返。

2. **审批缓存预热**：在会话开始时预加载常用工具的审批状态，减少首次调用延迟。

3. **更细粒度的图像处理**：根据图像大小和格式进行更智能的内容过滤。

4. **审批决策日志**：记录所有审批决策的完整上下文，便于审计和调试。

5. **配置验证**：在持久化审批设置前验证配置文件的写入权限和格式正确性。

6. **并发控制优化**：使用更细粒度的锁或原子操作管理审批状态，减少竞争条件。

7. **模板国际化**：`mcp_tool_approval_templates.rs` 中的模板目前仅支持英文，可考虑国际化支持。
