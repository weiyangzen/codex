# ListMcpServerStatusResponse.json 研究文档

## 场景与职责

`ListMcpServerStatusResponse` 是 Codex App Server Protocol v2 中定义的响应类型，用于 `mcpServerStatus/list` 方法的返回结果。该响应包含 MCP（Model Context Protocol）服务器的完整状态信息，包括服务器元数据、可用工具、资源、资源模板以及认证状态。

## 功能点目的

1. **服务器状态返回**：返回 MCP 服务器的完整状态列表
2. **工具发现**：提供每个服务器可用的工具定义（名称、描述、输入模式）
3. **资源发现**：提供服务器可访问的资源和资源模板
4. **认证状态通知**：告知客户端每个服务器的认证要求状态
5. **分页支持**：支持分页游标，便于遍历大量服务器

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "data": {
      "items": { "$ref": "#/definitions/McpServerStatus" },
      "type": "array"
    },
    "nextCursor": {
      "description": "Opaque cursor to pass to the next call...",
      "type": ["string", "null"]
    }
  },
  "required": ["data"],
  "title": "ListMcpServerStatusResponse",
  "type": "object"
}
```

### McpServerStatus 定义

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | MCP 服务器名称 |
| `tools` | object | 工具映射，键为工具名，值为 Tool 定义 |
| `resources` | array | 可用资源列表 |
| `resourceTemplates` | array | 资源模板列表 |
| `authStatus` | enum | 认证状态 |

### Tool 定义

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 工具名称 |
| `inputSchema` | any | JSON Schema 定义工具输入参数 |
| `description` | string/null | 工具描述 |
| `title` | string/null | 显示标题 |
| `icons` | array/null | 图标列表 |
| `annotations` | any | 工具注解 |
| `_meta` | any | 元数据 |
| `outputSchema` | any | 输出模式（可选） |

### Resource 定义

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 资源名称 |
| `uri` | string | 资源 URI |
| `description` | string/null | 资源描述 |
| `title` | string/null | 显示标题 |
| `mimeType` | string/null | MIME 类型 |
| `size` | int64/null | 资源大小（字节） |
| `icons` | array/null | 图标列表 |
| `annotations` | any | 资源注解 |
| `_meta` | any | 元数据 |

### ResourceTemplate 定义

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 模板名称 |
| `uriTemplate` | string | URI 模板（可包含变量） |
| `description` | string/null | 模板描述 |
| `title` | string/null | 显示标题 |
| `mimeType` | string/null | MIME 类型 |
| `annotations` | any | 模板注解 |

### 认证状态枚举

- `unsupported`: 服务器不支持认证
- `notLoggedIn`: 需要登录但未登录
- `bearerToken`: 使用 Bearer Token 认证
- `oAuth`: 使用 OAuth 认证

### 协议映射

Rust 结构体定义（v2.rs）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ListMcpServerStatusResponse {
    pub data: Vec<McpServerStatus>,
    /// Opaque cursor to pass to the next call to continue after the last item.
    /// If None, there are no more items to return.
    pub next_cursor: Option<String>,
}

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

## 关键代码路径与文件引用

### 核心定义文件

1. **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ListMcpServerStatusResponse.json`
2. **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1919-1927)
3. **McpServerStatus**: `v2.rs` 行 1908-1917
4. **McpAuthStatus**: `v2.rs` 行 334-340（通过宏定义）

### MCP 核心类型

- **McpTool**: 来自 `codex_protocol::mcp::Tool`
- **McpResource**: 来自 `codex_protocol::mcp::Resource`
- **McpResourceTemplate**: 来自 `codex_protocol::mcp::ResourceTemplate`

### 服务器处理代码

- **请求处理**: `codex-rs/app-server/src/codex_message_processor.rs`
  - `list_mcp_server_status` 方法
- **MCP 快照收集**: `codex_core::mcp::collect_mcp_snapshot`
- **工具分组**: `codex_core::mcp::group_tools_by_server`

### 测试文件

- `codex-rs/app-server/tests/common/mcp_process.rs`

### 生成产物

- TypeScript: `typescript/v2/ListMcpServerStatusResponse.ts`
- TypeScript: `typescript/v2/McpServerStatus.ts`
- 合并 Schema: `json/codex_app_server_protocol.v2.schemas.json`

## 依赖与外部交互

### 内部依赖

1. **MCP 协议库**: `codex_protocol::mcp` 模块
2. **RMCP 库**: `rmcp` 用于实际 MCP 协议通信
3. **认证系统**: `codex_core::mcp::auth` 模块

### 外部交互

| 组件 | 交互 | 说明 |
|------|------|------|
| MCP 服务器 | MCP 协议 | 获取工具列表、资源列表 |
| 认证服务 | 状态查询 | 获取当前认证状态 |
| 客户端 | JSON-RPC | 展示服务器状态和工具 |

### 认证流程

```
ListMcpServerStatusResponse
    ↓
检查 authStatus
    ↓
notLoggedIn → 提示用户登录 → McpServerOauthLogin
    ↓
bearerToken/oAuth → 已认证，可直接调用工具
```

## 风险、边界与改进建议

### 潜在风险

1. **工具定义过大**: `inputSchema` 可能包含复杂的 JSON Schema，导致响应体积过大
2. **资源数量过多**: 某些服务器可能提供大量资源，影响性能
3. **敏感信息泄露**: 工具定义可能包含敏感信息，需确保适当过滤

### 边界情况

1. **空工具列表**: 服务器可能不提供任何工具
2. **空资源列表**: 服务器可能不提供任何资源
3. **模板变量**: `uriTemplate` 包含变量，客户端需正确解析

### 改进建议

1. **增量更新**: 支持 ETag 或版本号，只返回变化的数据
2. **字段选择**: 支持字段选择，只返回需要的字段
3. **工具分类**: 添加工具分类或标签，便于组织
4. **使用统计**: 添加工具使用统计，帮助用户发现常用工具
5. **搜索功能**: 支持按名称、描述搜索工具和服务器

### 客户端使用示例

```typescript
interface McpServerBrowser {
  async listAllServers(): Promise<McpServerStatus[]>;
  async findServer(name: string): Promise<McpServerStatus | null>;
  async getToolsNeedingAuth(): Promise<McpServerStatus[]>;
}

class McpServerBrowserImpl implements McpServerBrowser {
  async listAllServers(): Promise<McpServerStatus[]> {
    const allServers = [];
    let cursor: string | null = null;
    
    do {
      const response: ListMcpServerStatusResponse = await this.client.request({
        method: 'mcpServerStatus/list',
        params: { cursor, limit: 20 }
      });
      
      allServers.push(...response.data);
      cursor = response.nextCursor;
    } while (cursor);
    
    return allServers;
  }
  
  async findServer(name: string): Promise<McpServerStatus | null> {
    // 假设服务器数量不多，直接遍历
    const servers = await this.listAllServers();
    return servers.find(s => s.name === name) || null;
  }
  
  async getToolsNeedingAuth(): Promise<McpServerStatus[]> {
    const servers = await this.listAllServers();
    return servers.filter(s => s.authStatus === 'notLoggedIn');
  }
  
  // 渲染工具列表
  renderTools(server: McpServerStatus): string {
    return Object.entries(server.tools)
      .map(([name, tool]) => {
        const required = tool.inputSchema.required || [];
        return `- ${name}: ${tool.description}
  参数: ${required.join(', ') || '无'}`;
      })
      .join('\n');
  }
}
```

### 性能考虑

1. **缓存策略**: 客户端应缓存工具定义，避免重复获取
2. **延迟加载**: 资源列表可能很大，考虑延迟加载
3. **增量更新**: 使用 `nextCursor` 分页，避免一次性加载大量数据
