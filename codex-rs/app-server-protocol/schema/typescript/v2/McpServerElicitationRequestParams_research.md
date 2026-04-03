# McpServerElicitationRequestParams 研究文档

## 1. 场景与职责

`McpServerElicitationRequestParams` 是 MCP (Model Context Protocol) 服务器请求用户输入的参数类型。该类型在系统中承担以下职责：

- **请求参数封装**：封装 MCP 服务器向用户请求信息所需的所有参数
- **模式区分**：支持表单模式（form）和URL模式（url）两种请求类型
- **上下文关联**：关联请求到特定的线程（thread）和轮次（turn）
- **服务器标识**：标识发起请求的 MCP 服务器

典型使用场景包括：
- MCP 服务器需要用户填写表单提供信息
- MCP 服务器需要用户通过外部URL完成授权或验证
- 客户端需要展示服务器请求并收集用户响应

## 2. 功能点目的

该类型存在的具体目的：

1. **统一请求接口**：为不同类型的 MCP 请求（表单、URL）提供统一的参数结构
2. **上下文追踪**：通过 `threadId` 和 `turnId` 将请求关联到对话上下文
3. **灵活模式**：通过联合类型支持多种请求模式
4. **元数据支持**：通过 `_meta` 字段支持扩展元数据

## 3. 具体技术实现

### 数据结构

```typescript
export type McpServerElicitationRequestParams = {
  threadId: string;           // 线程ID
  turnId: string | null;      // 轮次ID（可能为null）
  serverName: string;         // MCP服务器名称
} & (
  | {                         // 表单模式
      mode: "form";
      _meta: JsonValue | null;
      message: string;
      requestedSchema: McpElicitationSchema;
    }
  | {                         // URL模式
      mode: "url";
      _meta: JsonValue | null;
      message: string;
      url: string;
      elicitationId: string;
    }
);
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | `string` | 是 | 关联的线程ID |
| `turnId` | `string \| null` | 是 | 关联的轮次ID，可能为null（见注释说明） |
| `serverName` | `string` | 是 | 发起请求的MCP服务器名称 |
| `mode` | `"form" \| "url"` | 是 | 请求模式，决定后续字段 |

### 表单模式字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `mode` | `"form"` | 是 | 固定值为 `"form"` |
| `_meta` | `JsonValue \| null` | 是 | 扩展元数据 |
| `message` | `string` | 是 | 向用户展示的消息 |
| `requestedSchema` | `McpElicitationSchema` | 是 | 表单Schema定义 |

### URL模式字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `mode` | `"url"` | 是 | 固定值为 `"url"` |
| `_meta` | `JsonValue \| null` | 是 | 扩展元数据 |
| `message` | `string` | 是 | 向用户展示的消息 |
| `url` | `string` | 是 | 外部URL地址 |
| `elicitationId` | `string` | 是 | 请求唯一标识 |

### Rust 实现细节

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerElicitationRequestParams {
    pub thread_id: String,
    /// Active Codex turn when this elicitation was observed, if app-server could correlate one.
    ///
    /// This is nullable because MCP models elicitation as a standalone server-to-client request
    /// identified by the MCP server request id. It may be triggered during a turn, but turn
    /// context is app-server correlation rather than part of the protocol identity of the
    /// elicitation itself.
    pub turn_id: Option<String>,
    pub server_name: String,
    #[serde(flatten)]
    pub request: McpServerElicitationRequest,
    // TODO: When core can correlate an elicitation with an MCP tool call, expose the associated
    // McpToolCall item id here as an optional field. The current core event does not carry that
    // association.
}
```

**特性注解说明**：
- `#[serde(flatten)]`: 将 `request` 字段的内容内联到父结构中
- `turn_id` 的详细注释解释了为什么它可能为null

## 4. 关键代码路径与文件引用

### 主要源文件
- **Rust定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` 行5167-5185
- **TypeScript生成**: `codex-rs/app-server-protocol/schema/typescript/v2/McpServerElicitationRequestParams.ts`

### 相关类型定义
- `McpElicitationSchema`: 表单Schema定义
- `McpServerElicitationRequest`: 内部联合类型（form/url）

### 使用场景
- 在 MCP 服务器需要向用户请求信息时使用
- 客户端接收并处理服务器请求

## 5. 依赖与外部交互

### 导入的类型

```typescript
import type { JsonValue } from "../serde_json/JsonValue";
import type { McpElicitationSchema } from "./McpElicitationSchema";
```

### 依赖关系图

```
McpServerElicitationRequestParams
├── threadId: string
├── turnId: string | null
├── serverName: string
└── McpServerElicitationRequest (flattened union)
    ├── Form variant
    │   ├── _meta: JsonValue | null
    │   ├── message: string
    │   └── requestedSchema: McpElicitationSchema
    └── Url variant
        ├── _meta: JsonValue | null
        ├── message: string
        ├── url: string
        └── elicitationId: string
```

### 关于 turnId 的注释说明

```rust
/// Active Codex turn when this elicitation was observed, if app-server could correlate one.
///
/// This is nullable because MCP models elicitation as a standalone server-to-client request
/// identified by the MCP server request id. It may be triggered during a turn, but turn
/// context is app-server correlation rather than part of the protocol identity of the
/// elicitation itself.
```

这表明 `turnId` 为null的原因是：
- MCP 将 elicitation 建模为独立的服务器到客户端请求
- 轮次上下文是 app-server 的关联信息，而非 elicitation 协议身份的一部分
- app-server 可能无法总是将 elicitation 与特定轮次关联

## 6. 风险、边界与改进建议

### 潜在风险

1. **模式识别**：由于使用扁平化联合类型，客户端需要检查 `mode` 字段来区分变体
2. **turnId 缺失**：当 `turnId` 为null时，可能难以在UI中显示正确的上下文
3. **URL安全性**：URL模式的 `url` 字段可能包含恶意链接，需要客户端验证
4. **TODO项**：代码中有TODO注释，计划添加 `McpToolCall` item id 关联

### 边界情况

1. **空消息**：`message` 为空字符串时，客户端需要处理无消息展示的情况
2. **无效URL**：`url` 可能不是有效的URL格式
3. **空Schema**：表单模式下 `requestedSchema` 可能有空的 `properties`
4. **元数据扩展**：`_meta` 可以包含任意JSON数据，可能导致意外行为

### 改进建议

1. **添加验证**：
   - 验证URL格式（URL模式）
   - 验证Schema非空（表单模式）
   - 验证消息非空

2. **URL安全**：
   - 添加允许的URL协议白名单（如 https://）
   - 考虑添加URL域名白名单

3. **完成TODO**：
   - 实现 `McpToolCall` item id 关联
   - 更新类型定义以包含新字段

4. **TypeScript类型优化**：
   ```typescript
   // 建议：添加类型守卫
   export function isFormElicitation(
     params: McpServerElicitationRequestParams
   ): params is McpServerElicitationRequestParams & { mode: "form" } {
     return params.mode === "form";
   }
   
   export function isUrlElicitation(
     params: McpServerElicitationRequestParams
   ): params is McpServerElicitationRequestParams & { mode: "url" } {
     return params.mode === "url";
   }
   ```

5. **添加字段**：
   - `timeout`: 请求超时时间
   - `priority`: 请求优先级
   - `icon`: 服务器图标URL

### 测试建议

- 测试两种模式（form/url）的序列化和反序列化
- 测试 `turnId` 为null的情况
- 测试各种边界值（空消息、无效URL等）
- 验证扁平化序列化的正确性

### 使用示例

```typescript
// 表单模式请求
const formRequest: McpServerElicitationRequestParams = {
  threadId: "thread-123",
  turnId: "turn-456",
  serverName: "github-mcp",
  mode: "form",
  _meta: null,
  message: "Please provide your GitHub token",
  requestedSchema: {
    type: "object",
    properties: {
      token: {
        type: "string",
        title: "GitHub Token",
        description: "Your personal access token"
      }
    },
    required: ["token"]
  }
};

// URL模式请求
const urlRequest: McpServerElicitationRequestParams = {
  threadId: "thread-123",
  turnId: null,
  serverName: "oauth-provider",
  mode: "url",
  _meta: { provider: "github" },
  message: "Please authorize access to your GitHub account",
  url: "https://github.com/login/oauth/authorize?client_id=...",
  elicitationId: "elicitation-789"
};
```
