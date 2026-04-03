# McpServerStatus 研究文档

## 场景与职责

`McpServerStatus` 表示单个 MCP (Model Context Protocol) 服务器的完整状态信息，包括其提供的工具、资源、资源模板以及认证状态。这是 MCP 服务器管理功能的核心数据类型。

## 功能点目的

该类型的核心功能是：
1. **服务器发现**: 展示 MCP 服务器提供的所有可用工具
2. **资源管理**: 列出服务器提供的资源和资源模板
3. **认证状态跟踪**: 显示服务器的当前认证状态
4. **客户端集成**: 支持客户端动态发现和调用 MCP 工具

## 具体技术实现

### 数据结构

```typescript
export type McpServerStatus = { 
  name: string, 
  tools: { [key in string]?: Tool }, 
  resources: Array<Resource>, 
  resourceTemplates: Array<ResourceTemplate>, 
  authStatus: McpAuthStatus 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerStatus {
    pub name: String,
    pub tools: std::collections::HashMap<String, McpTool>,
    pub resources: Vec<McpResource>,
    pub resource_templates: Vec<McpResourceTemplate>,
    pub auth_status: McpAuthStatus,
}
```

### 字段详解

| 字段 | 类型 | 说明 |
|-----|------|------|
| `name` | `string` | MCP 服务器的唯一标识名称 |
| `tools` | `Record<string, Tool>` | 服务器提供的工具映射表，键为工具名 |
| `resources` | `Resource[]` | 服务器提供的静态资源列表 |
| `resourceTemplates` | `ResourceTemplate[]` | 资源模板列表，用于动态资源发现 |
| `authStatus` | `McpAuthStatus` | 当前认证状态 |

### 认证状态枚举

```rust
pub enum McpAuthStatus {
    Unsupported,    // 服务器不支持认证
    NotLoggedIn,    // 尚未登录
    BearerToken,    // 使用 Bearer Token 认证
    OAuth,          // 使用 OAuth 认证
}
```

### 关联类型

- `Tool`: MCP 工具定义，包含名称、描述和输入模式
- `Resource`: MCP 资源，包含 URI、名称、MIME 类型等
- `ResourceTemplate`: 资源模板，用于动态构造资源 URI

### API 集成

```rust
// 列表查询参数
pub struct ListMcpServerStatusParams {
    pub cursor: Option<String>,    // 分页游标
    pub limit: Option<u32>,        // 每页数量
}

// 列表查询响应
pub struct ListMcpServerStatusResponse {
    pub data: Vec<McpServerStatus>,
    pub next_cursor: Option<String>,
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，行 1908-1917 |
| `codex-rs/app-server-protocol/schema/typescript/v2/McpServerStatus.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/McpAuthStatus.ts` | 认证状态枚举 |

## 依赖与外部交互

### 依赖类型
- `McpTool` (from codex_protocol::mcp): 工具定义
- `McpResource` (from codex_protocol::mcp): 资源定义
- `McpResourceTemplate` (from codex_protocol::mcp): 资源模板定义
- `McpAuthStatus`: 认证状态枚举

### 协议集成
- 属于 App-Server Protocol v2 API
- 方法名: `mcpServerStatus/list`
- 支持分页查询

### MCP 协议集成
- 基于 Model Context Protocol 规范
- 工具和资源信息来自 MCP 服务器的 `tools/list` 和 `resources/list` 端点
- 认证流程遵循 MCP OAuth/Bearer Token 规范

## 风险、边界与改进建议

### 潜在风险
1. **大型工具集**: 如果 MCP 服务器提供大量工具，响应可能很大
2. **动态变化**: 工具和资源可能在运行时变化，客户端需要定期刷新
3. **认证过期**: OAuth Token 可能过期，需要重新认证

### 边界情况
1. **空工具集**: 某些 MCP 服务器可能不提供任何工具
2. **资源模板解析**: 资源模板需要客户端正确解析 URI 模板
3. **并发修改**: 服务器配置可能在查询期间发生变化

### 改进建议
1. 添加 `version` 或 `lastUpdated` 字段帮助客户端判断缓存是否有效
2. 考虑添加 `capabilities` 字段描述服务器支持的 MCP 功能
3. 可以添加 `health` 字段表示服务器的健康状态
4. 考虑支持增量更新，只返回自上次查询以来的变化
5. 添加 `documentationUrl` 字段指向服务器文档
