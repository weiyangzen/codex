# McpServerElicitationRequestParams 研究文档

## 场景与职责

`McpServerElicitationRequestParams` 是 MCP (Model Context Protocol) 服务器向客户端发起交互式请求时的参数类型。它定义了服务器请求用户输入或确认时所需的完整信息，支持两种主要模式：表单模式 (form) 和 URL 模式 (url)。

该类型是 MCP 协议中人机交互的核心组件，使 MCP 服务器能够在工具执行过程中动态请求额外信息，如 OAuth 授权、配置参数、用户确认等。

## 功能点目的

1. **线程上下文关联**: 通过 `threadId` 和可选的 `turnId` 将请求关联到特定对话上下文
2. **服务器标识**: 通过 `serverName` 标识发起请求的 MCP 服务器
3. **双模式支持**:
   - **表单模式 (form)**: 结构化数据收集，支持 JSON Schema 定义的表单
   - **URL 模式 (url)**: 外部链接跳转，如 OAuth 授权页面
4. **元数据传递**: 支持携带任意 JSON 元数据，供客户端扩展使用
5. **消息展示**: 向用户展示可读的请求说明信息

## 具体技术实现

### 数据结构

```typescript
export type McpServerElicitationRequestParams = { 
  threadId: string, 
  turnId: string | null, 
  serverName: string, 
} & (
  | { 
      "mode": "form", 
      _meta: JsonValue | null, 
      message: string, 
      requestedSchema: McpElicitationSchema, 
    } 
  | { 
      "mode": "url", 
      _meta: JsonValue | null, 
      message: string, 
      url: string, 
      elicitationId: string, 
    }
);
```

### 字段详解

#### 基础字段（所有模式共有）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | `string` | 是 | 请求关联的线程 ID |
| `turnId` | `string \| null` | 是 | 请求关联的回合 ID，可能为 null |
| `serverName` | `string` | 是 | 发起请求的 MCP 服务器名称 |

#### 表单模式 (mode: "form")

| 字段 | 类型 | 说明 |
|------|------|------|
| `_meta` | `JsonValue \| null` | 扩展元数据 |
| `message` | `string` | 向用户展示的消息 |
| `requestedSchema` | `McpElicitationSchema` | 表单结构定义 |

#### URL 模式 (mode: "url")

| 字段 | 类型 | 说明 |
|------|------|------|
| `_meta` | `JsonValue \| null` | 扩展元数据 |
| `message` | `string` | 向用户展示的消息 |
| `url` | `string` | 跳转的目标 URL |
| `elicitationId` | `string` | 请求的唯一标识 |

### 依赖类型

- `JsonValue`: 来自 `../serde_json/JsonValue`，表示任意 JSON 值
- `McpElicitationSchema`: 来自 `./McpElicitationSchema`，定义表单结构

### 生成信息

该文件为自动生成代码，由 [ts-rs](https://github.com/Aleph-Alpha/ts-rs) 从 Rust 源代码生成。

对应的 Rust 定义（简化）：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerElicitationRequestParams {
    pub thread_id: String,
    pub turn_id: Option<String>,
    pub server_name: String,
    #[serde(flatten)]
    pub mode: McpElicitationMode,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "mode", rename_all = "camelCase")]
#[ts(tag = "mode")]
pub enum McpElicitationMode {
    Form { ... },
    Url { ... },
}
```

## 关键代码路径与文件引用

### TypeScript 定义
- **文件**: `codex-rs/app-server-protocol/schema/typescript/v2/McpServerElicitationRequestParams.ts`
- **索引**: `codex-rs/app-server-protocol/schema/typescript/v2/index.ts`

### Rust 源文件
- **主定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **通用定义**: `codex-rs/app-server-protocol/src/protocol/common.rs`

### 核心使用位置

1. **App Server 事件处理**
   - 文件: `codex-rs/app-server/src/bespoke_event_handling.rs`
   - 行号: 涉及 `McpServerElicitationRequestParams` 的导入和使用
   - 功能: 处理 MCP 服务器发来的 elicitation 请求

2. **核心 MCP 工具调用**
   - 文件: `codex-rs/core/src/mcp_tool_call.rs`
   - 功能: 在工具调用过程中处理 elicitation

3. **TUI 应用服务器**
   - 文件: `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs`
   - 功能: TUI 界面处理 elicitation 请求

4. **ChatWidget 处理**
   - 文件: `codex-rs/tui_app_server/src/chatwidget.rs`
   - 功能: 聊天界面集成

5. **测试套件**
   - 文件: `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs`
   - 功能: 完整的 elicitation 流程测试

### 协议定义

**ServerRequest 定义**（来自 `common.rs`）：
```rust
server_request_definitions! {
    McpServerElicitationRequest => "mcpServer/elicitation/request" {
        params: v2::McpServerElicitationRequestParams,
        response: v2::McpServerElicitationRequestResponse,
    },
    // ...
}
```

## 依赖与外部交互

### 完整协议流程

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        MCP Elicitation 流程                              │
└─────────────────────────────────────────────────────────────────────────┘

  MCP Server                    App Server                    Client
      │                             │                            │
      │  1. 工具调用需要用户输入      │                            │
      │────────────────────────────▶│                            │
      │                             │                            │
      │                             │ 2. 构建 ServerRequest        │
      │                             │    (McpServerElicitationRequest)
      │                             │                            │
      │                             │───────────────────────────▶│
      │                             │                            │
      │                             │                    3. 展示 UI
      │                             │                    (form/url)
      │                             │                            │
      │                             │◀───────────────────────────│
      │                             │    4. 用户响应              │
      │                             │    (action: accept/decline/cancel)
      │                             │                            │
      │◀────────────────────────────│                            │
      │  5. 响应转发到 MCP Server    │                            │
      │                             │                            │
```

### 与核心协议的集成

1. **Event 系统**: 通过 `codex_protocol::protocol::Event` 传递 elicitation 事件
2. **工具调用**: 在 `McpToolCall` 执行过程中触发
3. **审批流程**: 与 `AskForApproval` 配置集成，控制是否自动审批

### 下游使用者

| 组件 | 文件路径 | 用途 |
|------|----------|------|
| TUI | `tui/src/bottom_pane/approval_overlay.rs` | 审批界面展示 |
| TUI App Server | `tui_app_server/src/bottom_pane/mcp_server_elicitation.rs` | 处理 elicitation UI |
| Core Tests | `core/src/mcp_tool_call_tests.rs` | 工具调用测试 |

## 风险、边界与改进建议

### 已知风险

1. **turnId 为空**: 文档明确指出 `turnId` 可能为 null，因为 MCP 协议将 elicitation 视为独立的服务器到客户端请求
   - 风险: 客户端可能无法准确关联到当前回合
   - 缓解: 依赖 `threadId` 和 `serverName` 进行关联

2. **模式切换复杂性**: 两种模式 (form/url) 的字段不完全相同
   - 风险: 客户端需要分别处理，增加复杂度
   - 缓解: 使用 TypeScript 的 discriminated union 确保类型安全

3. **URL 模式安全性**: `url` 字段可能包含任意 URL
   - 风险: 潜在的安全隐患（钓鱼、恶意网站等）
   - 建议: 客户端应验证 URL 白名单或明确提示用户

### 边界情况

1. **并发 Elicitation**: 多个 MCP 服务器同时发起请求
   - 需要队列机制或明确的优先级策略

2. **超时处理**: 用户长时间未响应
   - 需要定义超时行为和默认动作

3. **会话中断**: 网络问题导致请求或响应丢失
   - 需要重试机制和状态同步

4. **Schema 验证失败**: `requestedSchema` 格式错误
   - 需要前置验证和友好的错误提示

### 改进建议

1. **添加超时配置**:
   ```typescript
   timeoutSecs?: number;
   defaultAction?: McpServerElicitationAction;
   ```

2. **URL 模式增强**:
   - 添加 `urlType` 字段区分内部/外部链接
   - 添加 `callbackUrl` 支持 OAuth 回调

3. **表单模式增强**:
   - 支持多步骤表单 (wizard)
   - 支持条件字段显示

4. **安全性增强**:
   - 添加 `trusted` 标记标识可信服务器
   - URL 白名单验证

5. **可观测性**:
   - 添加 `correlationId` 便于追踪
   - 记录 elicitation 耗时和结果

### 测试建议

1. **单元测试**: 验证两种模式的序列化/反序列化
2. **集成测试**: 完整的请求-响应流程
3. **边界测试**: 
   - turnId 为 null 的处理
   - 超长 message 的展示
   - 复杂 schema 的渲染
4. **安全测试**: URL 模式的 XSS 和钓鱼防护

### 相关配置

在 `AskForApproval` 配置中控制 elicitation 审批行为：
```rust
AskForApproval::Granular {
    mcp_elicitations: bool,  // 控制是否自动审批 MCP elicitation
    // ...
}
```
