# McpServerElicitationRequestParams.ts 研究文档

## 场景与职责

`McpServerElicitationRequestParams.ts` 定义了 MCP (Model Context Protocol) 服务器向客户端发送征求请求的参数类型。该类型支持两种征求模式：表单模式（form）和 URL 模式（url），用于在 MCP 工具执行过程中向用户请求额外信息或确认。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **双模式征求**: 支持表单模式（结构化数据收集）和 URL 模式（外部页面交互）
2. **上下文关联**: 关联到特定的线程（`threadId`）和回合（`turnId`）
3. **服务器标识**: 标识发送征求请求的 MCP 服务器
4. **元数据传递**: 支持传递额外的元数据供客户端使用

## 具体技术实现

### 数据结构

```typescript
export type McpServerElicitationRequestParams = { 
  threadId: string,                   // 线程 ID
  turnId: string | null,              // 回合 ID（可为 null）
  serverName: string,                 // MCP 服务器名称
} & (
  | {                                 // 表单模式
      "mode": "form",
      _meta: JsonValue | null,        // 额外元数据
      message: string,                // 显示给用户的消息
      requestedSchema: McpElicitationSchema,  // 表单模式定义
    }
  | {                                 // URL 模式
      "mode": "url",
      _meta: JsonValue | null,        // 额外元数据
      message: string,                // 显示给用户的消息
      url: string,                    // 外部页面 URL
      elicitationId: string,          // 征求唯一标识
    }
);
```

### 关键字段说明

#### 公共字段（两种模式共有）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | `string` | 是 | 关联的线程 ID |
| `turnId` | `string \| null` | 是 | 关联的回合 ID，可为 null（MCP 模型将征求视为独立请求） |
| `serverName` | `string` | 是 | 发送征求的 MCP 服务器名称 |
| `mode` | `"form" \| "url"` | 是 | 征求模式 |
| `_meta` | `JsonValue \| null` | 是 | 额外元数据，供客户端使用 |
| `message` | `string` | 是 | 显示给用户的消息/提示 |

#### 表单模式特有字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `requestedSchema` | `McpElicitationSchema` | 是 | 表单字段的模式定义 |

#### URL 模式特有字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `url` | `string` | 是 | 外部页面的 URL |
| `elicitationId` | `string` | 是 | 征求的唯一标识符 |

### 生成来源

该文件由 Rust 结构体通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerElicitationRequestParams {
    pub thread_id: String,
    pub turn_id: Option<String>,
    pub server_name: String,
    #[serde(flatten)]
    pub mode: McpServerElicitationMode,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "mode", rename_all = "camelCase")]
#[ts(tag = "mode")]
pub enum McpServerElicitationMode {
    Form {
        #[serde(rename = "_meta")]
        meta: Option<JsonValue>,
        message: String,
        requested_schema: McpElicitationSchema,
    },
    Url {
        #[serde(rename = "_meta")]
        meta: Option<JsonValue>,
        message: String,
        url: String,
        elicitation_id: String,
    },
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义 Rust 类型 |
| `codex-rs/core/src/mcp_tool_call.rs` | 发送征求请求 |
| `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs` | TUI 处理征求请求 |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 服务器端处理征求 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的征求对话框
- TUI 的征求提示界面
- 表单渲染和 URL 打开逻辑

### 相关类型

| 类型 | 说明 |
|------|------|
| `McpElicitationSchema.ts` | 表单模式定义 |
| `McpServerElicitationAction.ts` | 用户响应操作 |
| `JsonValue.ts` | 通用 JSON 值类型 |

### 相关测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs` | 集成测试 |
| `codex-rs/core/src/mcp_tool_call_tests.rs` | 单元测试 |

## 依赖与外部交互

### 直接依赖类型

- `JsonValue.ts`: 通用 JSON 值类型
- `McpElicitationSchema.ts`: 表单模式定义

### 被依赖类型

- 客户端处理征求请求的事件类型
- 服务器发送征求通知的参数类型

### MCP 协议集成

该类型实现了 MCP 规范中的 `elicitation/create` 请求：

#### 表单模式流程
```
MCP Server -> Client: McpServerElicitationRequestParams (mode: "form")
Client -> User: 显示表单 UI
User -> Client: 填写表单并提交
Client -> MCP Server: 表单数据 + action: "accept"
```

#### URL 模式流程
```
MCP Server -> Client: McpServerElicitationRequestParams (mode: "url")
Client -> User: 显示消息和打开 URL 按钮
User -> Client: 点击打开 URL
User -> External: 在外部页面完成交互
External -> MCP Server: 回调（通过 elicitationId）
```

### turnId 为 null 的设计

`turnId` 被设计为可为 null，因为：
1. MCP 模型将征求视为独立的 server-to-client 请求
2. 征求由 MCP 服务器请求 ID 标识，而非回合上下文
3. 回合关联是 app-server 的关联，而非协议身份的一部分

## 风险、边界与改进建议

### 风险点

1. **URL 模式安全性**: 打开的 URL 可能包含恶意内容，需要安全审查
2. **表单验证**: 客户端和服务器需要一致的表单验证逻辑
3. **超时处理**: 征求请求可能长时间无响应，需要超时机制
4. **并发征求**: 多个征求同时存在时的处理

### 边界情况

1. **无效 URL**: URL 模式中的 URL 格式无效或无法访问
2. **空表单提交**: 表单模式下用户提交空数据
3. **重复征求**: 相同的 `elicitationId` 重复发送
4. **线程/回合不存在**: 关联的线程或回合已结束

### 改进建议

1. **添加超时字段**:
   ```typescript
   {
     timeoutSeconds?: number;
     timeoutAction?: "accept" | "decline" | "cancel";
   }
   ```

2. **URL 模式安全增强**:
   ```typescript
   {
     mode: "url",
     url: string,
     allowedDomains?: string[];  // 允许的域名白名单
     requireHttps?: boolean;     // 是否强制 HTTPS
   }
   ```

3. **表单模式增强**:
   ```typescript
   {
     mode: "form",
     requestedSchema: McpElicitationSchema,
     validation?: {
       customValidator?: string;  // 自定义验证器脚本
     }
   }
   ```

4. **添加优先级**:
   ```typescript
   {
     priority?: "low" | "normal" | "high" | "urgent";
   }
   ```

### UI 建议

1. **表单模式**:
   - 根据 `requestedSchema` 动态生成表单字段
   - 显示 `message` 作为表单说明
   - 提供提交和取消按钮

2. **URL 模式**:
   - 显示 `message` 作为提示
   - 提供"打开链接"按钮
   - 显示 URL 域名供用户确认
   - 提供完成/取消按钮

### 示例使用场景

```typescript
// 表单模式示例：收集用户信息
const formElicitation: McpServerElicitationRequestParams = {
  threadId: "thread-123",
  turnId: "turn-456",
  serverName: "user-profile-server",
  mode: "form",
  _meta: { source: "onboarding" },
  message: "请填写您的个人信息以继续",
  requestedSchema: {
    type: "object",
    properties: {
      name: { type: "string", title: "姓名" },
      email: { type: "string", format: "email", title: "邮箱" }
    },
    required: ["name", "email"]
  }
};

// URL 模式示例：OAuth 授权
const urlElicitation: McpServerElicitationRequestParams = {
  threadId: "thread-123",
  turnId: null,
  serverName: "oauth-server",
  mode: "url",
  _meta: { provider: "github" },
  message: "请点击下方按钮授权访问您的 GitHub 账户",
  url: "https://github.com/login/oauth/authorize?client_id=...",
  elicitationId: "auth-789"
};
```
