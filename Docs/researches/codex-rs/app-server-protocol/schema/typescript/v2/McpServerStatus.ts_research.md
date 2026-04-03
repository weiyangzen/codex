# McpServerStatus.ts 研究文档

## 场景与职责

`McpServerStatus.ts` 定义了 MCP (Model Context Protocol) 服务器的状态类型。该类型包含服务器的名称、可用工具、资源、资源模板以及身份验证状态，用于客户端了解 MCP 服务器的当前能力和状态。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **服务器信息**: 提供 MCP 服务器的基本信息（名称）
2. **能力发现**: 列出服务器提供的工具、资源和资源模板
3. **身份验证状态**: 显示服务器的当前身份验证状态
4. **状态监控**: 支持客户端监控服务器状态变化

## 具体技术实现

### 数据结构

```typescript
export type McpServerStatus = { 
  name: string,                                    // 服务器名称
  tools: { [key in string]?: Tool },               // 可用工具映射
  resources: Array<Resource>,                      // 可用资源列表
  resourceTemplates: Array<ResourceTemplate>,      // 资源模板列表
  authStatus: McpAuthStatus,                       // 身份验证状态
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | `string` | 是 | MCP 服务器的唯一名称/标识符 |
| `tools` | `Record<string, Tool>` | 是 | 服务器提供的工具映射，键为工具名称 |
| `resources` | `Resource[]` | 是 | 服务器提供的静态资源列表 |
| `resourceTemplates` | `ResourceTemplate[]` | 是 | 服务器提供的资源模板列表 |
| `authStatus` | `McpAuthStatus` | 是 | 当前身份验证状态 |

### 身份验证状态 (`McpAuthStatus`)

```typescript
type McpAuthStatus = 
  | "unsupported"      // 服务器不支持身份验证
  | "notLoggedIn"      // 未登录
  | "bearerToken"      // 使用 Bearer Token 认证
  | "oauth";           // 使用 OAuth 认证
```

### 生成来源

该文件由 Rust 结构体通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerStatus {
    pub name: String,
    pub tools: BTreeMap<String, Tool>,
    pub resources: Vec<Resource>,
    pub resource_templates: Vec<ResourceTemplate>,
    pub auth_status: McpAuthStatus,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义 Rust 类型 |
| `codex-rs/core/src/mcp_connection_manager.rs` | 管理 MCP 连接和状态 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 处理状态查询 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的服务器状态显示
- TUI 的服务器列表和状态面板
- 工具选择界面

### 相关类型

| 类型 | 说明 |
|------|------|
| `Tool.ts` | 工具定义 |
| `Resource.ts` | 资源定义 |
| `ResourceTemplate.ts` | 资源模板定义 |
| `McpAuthStatus.ts` | 身份验证状态枚举 |

### 相关测试

| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/mcp_connection_manager_tests.rs` | 连接管理测试 |

## 依赖与外部交互

### 直接依赖类型

- `Resource.ts`: 资源类型
- `ResourceTemplate.ts`: 资源模板类型
- `Tool.ts`: 工具类型
- `McpAuthStatus.ts`: 身份验证状态

### 被依赖类型

- 服务器列表响应类型
- 状态更新通知类型

### MCP 协议集成

该类型实现了 MCP 规范中的服务器能力发现：
1. 客户端连接到 MCP 服务器
2. 服务器报告其能力（工具、资源、模板）
3. 客户端根据能力展示相应的 UI
4. 身份验证状态变化时更新状态

### 状态变化场景

| 场景 | 状态变化 |
|------|----------|
| 服务器初始化 | 从空状态到完整状态 |
| 工具更新 | `tools` 字段更新 |
| 资源变化 | `resources` 或 `resourceTemplates` 更新 |
| 登录/登出 | `authStatus` 变化 |
| 服务器断开 | 状态移除或标记为离线 |

## 风险、边界与改进建议

### 风险点

1. **状态同步延迟**: 服务器状态变化可能无法实时同步到客户端
2. **大数据量**: 大量工具或资源可能影响性能
3. **敏感信息泄露**: 资源 URI 可能包含敏感信息

### 边界情况

1. **空服务器**: 没有任何工具、资源的服务器
2. **离线服务器**: 服务器断开连接后的状态处理
3. **重复工具名**: 工具映射中的键冲突

### 改进建议

1. **添加版本信息**:
   ```typescript
   {
     name: string;
     version?: string;           // 服务器版本
     protocolVersion?: string;   // MCP 协议版本
     // ...
   }
   ```

2. **添加健康状态**:
   ```typescript
   {
     // ...
     health: "healthy" | "degraded" | "unhealthy";
     lastError?: string;
   }
   ```

3. **添加元数据**:
   ```typescript
   {
     // ...
     metadata: {
       description?: string;
       icon?: string;
       homepage?: string;
     };
   }
   ```

4. **分页支持**: 对于大量工具/资源，支持分页查询
   ```typescript
   {
     tools: Record<string, Tool>;
     toolsPagination?: {
       total: number;
       cursor?: string;
     };
   }
   ```

### 示例使用场景

```typescript
// 服务器状态示例
const serverStatus: McpServerStatus = {
  name: "github-server",
  tools: {
    "create_issue": {
      name: "create_issue",
      description: "创建 GitHub Issue",
      inputSchema: { /* ... */ }
    },
    "list_repos": {
      name: "list_repos",
      description: "列出仓库",
      inputSchema: { /* ... */ }
    }
  },
  resources: [
    {
      uri: "github://user/repos",
      name: "用户仓库列表",
      mimeType: "application/json"
    }
  ],
  resourceTemplates: [
    {
      uriTemplate: "github://repos/{owner}/{repo}/issues",
      name: "仓库 Issues"
    }
  ],
  authStatus: "oauth"
};
```
