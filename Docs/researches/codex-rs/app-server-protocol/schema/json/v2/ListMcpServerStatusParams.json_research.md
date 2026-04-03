# ListMcpServerStatusParams.json 研究文档

## 场景与职责

`ListMcpServerStatusParams` 是 Codex App Server Protocol v2 中定义的客户端请求参数类型，用于 `mcpServerStatus/list` 方法。该参数用于查询 MCP（Model Context Protocol）服务器的状态列表，包括服务器可用性、认证状态、工具列表等信息。

MCP 是 Codex 与外部工具和服务集成的标准协议，此参数支持分页查询，便于客户端获取大量 MCP 服务器的分页状态信息。

## 功能点目的

1. **MCP 服务器发现**：查询已配置和可用的 MCP 服务器列表
2. **状态监控**：获取服务器的实时状态（在线、离线、认证状态等）
3. **工具发现**：获取每个服务器提供的工具、资源和资源模板
4. **分页查询**：支持大规模 MCP 服务器环境的分页浏览

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "cursor": {
      "description": "Opaque pagination cursor returned by a previous call.",
      "type": ["string", "null"]
    },
    "limit": {
      "description": "Optional page size; defaults to a server-defined value.",
      "format": "uint32",
      "minimum": 0.0,
      "type": ["integer", "null"]
    }
  },
  "title": "ListMcpServerStatusParams",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `cursor` | string/null | 否 | 分页游标，由上一次调用返回，用于获取下一页数据 |
| `limit` | uint32/null | 否 | 每页返回的最大条目数，不传则使用服务器默认值 |

### 协议映射

Rust 结构体定义（v2.rs）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ListMcpServerStatusParams {
    /// Opaque pagination cursor returned by a previous call.
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    /// Optional page size; defaults to a server-defined value.
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
}
```

客户端请求定义（common.rs）：
```rust
client_request_definitions! {
    McpServerStatusList => "mcpServerStatus/list" {
        params: v2::ListMcpServerStatusParams,
        response: v2::ListMcpServerStatusResponse,
    },
}
```

Wire 格式：`method: "mcpServerStatus/list"`

### 响应类型

对应的响应类型为 `ListMcpServerStatusResponse`：

```rust
pub struct ListMcpServerStatusResponse {
    pub data: Vec<McpServerStatus>,
    pub next_cursor: Option<String>,
}
```

**McpServerStatus** 包含：
- `name`: 服务器名称
- `tools`: 工具映射（工具名 -> Tool 定义）
- `resources`: 可用资源列表
- `resource_templates`: 资源模板列表
- `auth_status`: 认证状态（`Unsupported`, `NotLoggedIn`, `BearerToken`, `OAuth`）

## 关键代码路径与文件引用

### 核心定义文件

1. **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ListMcpServerStatusParams.json`
2. **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1899-1906)
3. **响应类型**: `v2.rs` 行 1919-1927
4. **McpServerStatus**: `v2.rs` 行 1908-1917
5. **协议枚举**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 420-423)

### 服务器处理代码

- **请求处理**: `codex-rs/app-server/src/codex_message_processor.rs`
- **MCP 状态收集**: `codex_core::mcp::collect_mcp_snapshot`
- **工具分组**: `codex_core::mcp::group_tools_by_server`

### 测试文件

- `codex-rs/app-server/tests/common/mcp_process.rs`

### 生成产物

- TypeScript: `typescript/v2/ListMcpServerStatusParams.ts`
- TypeScript: `typescript/v2/ListMcpServerStatusResponse.ts`
- 合并 Schema: `json/codex_app_server_protocol.v2.schemas.json`

## 依赖与外部交互

### 内部依赖

1. **MCP 核心库**: `codex_protocol::mcp::{Resource, ResourceTemplate, Tool}`
2. **MCP 客户端**: `codex_rmcp_client` 用于实际 MCP 通信
3. **认证状态**: `codex_protocol::protocol::McpAuthStatus`

### 外部交互

| 组件 | 交互 | 说明 |
|------|------|------|
| MCP 服务器 | MCP 协议 | 查询服务器状态和工具列表 |
| 认证系统 | 状态查询 | 获取当前认证状态 |
| TUI 客户端 | JSON-RPC | 显示 MCP 服务器列表和状态 |

### 认证状态枚举

```rust
pub enum McpAuthStatus {
    Unsupported,   // 服务器不支持认证
    NotLoggedIn,   // 需要登录但未登录
    BearerToken,   // 使用 Bearer Token 认证
    OAuth,         // 使用 OAuth 认证
}
```

## 风险、边界与改进建议

### 潜在风险

1. **服务器无响应**: 某个 MCP 服务器无响应可能导致整个查询超时
2. **大量服务器**: 在大量 MCP 服务器环境中，首次查询可能很慢
3. **状态不一致**: 返回的状态可能是缓存的，与实际状态有延迟

### 边界情况

1. **空列表**: 没有配置 MCP 服务器时返回空列表
2. **无效游标**: 使用过期或无效游标可能导致错误
3. **limit 为 0**: 可能返回空结果或错误

### 改进建议

1. **并行查询**: 并行查询多个 MCP 服务器减少延迟
2. **缓存机制**: 添加客户端缓存减少重复查询
3. **增量更新**: 支持增量更新，只返回变化的状态
4. **过滤条件**: 添加按认证状态、服务器名称等过滤
5. **健康检查**: 添加健康检查端点，快速检测服务器可用性

### 使用示例

```typescript
// 查询 MCP 服务器状态
async function listMcpServers() {
  const servers = [];
  let cursor: string | null = null;
  
  do {
    const response = await client.request({
      method: 'mcpServerStatus/list',
      params: {
        cursor,
        limit: 10
      }
    });
    
    servers.push(...response.data);
    cursor = response.nextCursor;
  } while (cursor);
  
  return servers;
}

// 检查需要登录的服务器
function getServersNeedingAuth(servers: McpServerStatus[]) {
  return servers.filter(s => s.authStatus === 'notLoggedIn');
}
```

### 分页最佳实践

1. **首次查询**: 不传 cursor，获取第一页
2. **后续查询**: 使用上次返回的 `nextCursor`
3. **结束条件**: `nextCursor` 为 null 表示没有更多数据
4. **错误处理**: 无效游标时重新从头查询
