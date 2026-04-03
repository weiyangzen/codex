# McpServerStatus 研究文档

## 1. 场景与职责

`McpServerStatus` 是 MCP (Model Context Protocol) 服务器状态信息的数据类型。该类型在系统中承担以下职责：

- **服务器状态展示**：提供 MCP 服务器的完整状态信息
- **工具/资源发现**：展示服务器提供的工具和资源
- **认证状态跟踪**：显示服务器的认证状态
- **客户端UI支持**：为客户端提供渲染服务器信息所需的数据

典型使用场景包括：
- 列出所有配置的 MCP 服务器及其状态
- 显示特定服务器的工具和资源
- 检查服务器的认证状态
- 管理服务器连接

## 2. 功能点目的

该类型存在的具体目的：

1. **状态聚合**：将服务器的各种信息（工具、资源、认证）聚合在一个类型中
2. **发现机制**：支持客户端发现服务器提供的功能
3. **认证可见性**：明确显示服务器的认证状态
4. **资源模板支持**：支持参数化的资源访问

## 3. 具体技术实现

### 数据结构

```typescript
export type McpServerStatus = {
  name: string;                                    // 服务器名称
  tools: { [key in string]?: Tool };              // 可用工具映射
  resources: Array<Resource>;                      // 可用资源列表
  resourceTemplates: Array<ResourceTemplate>;      // 资源模板列表
  authStatus: McpAuthStatus;                       // 认证状态
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | `string` | 是 | MCP服务器的唯一标识名称 |
| `tools` | `Record<string, Tool>` | 是 | 服务器提供的工具，键为工具名称 |
| `resources` | `Resource[]` | 是 | 服务器提供的静态资源列表 |
| `resourceTemplates` | `ResourceTemplate[]` | 是 | 参数化资源访问模板 |
| `authStatus` | `McpAuthStatus` | 是 | 服务器的当前认证状态 |

### Rust 实现细节

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

**特性注解说明**：
- `HashMap<String, McpTool>`: 工具以名称为键存储，便于快速查找
- `Vec<McpResource>`: 资源作为列表存储
- `Vec<McpResourceTemplate>`: 资源模板支持参数化访问

## 4. 关键代码路径与文件引用

### 主要源文件
- **Rust定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` 行1908-1917
- **TypeScript生成**: `codex-rs/app-server-protocol/schema/typescript/v2/McpServerStatus.ts`

### 相关类型定义
- `Tool` / `McpTool`: 工具定义
- `Resource` / `McpResource`: 资源定义
- `ResourceTemplate` / `McpResourceTemplate`: 资源模板定义
- `McpAuthStatus`: 认证状态枚举
- `ListMcpServerStatusResponse`: 服务器状态列表响应

### 使用场景
- 在 `mcpServer/list` RPC 方法的响应中使用
- 客户端展示服务器信息和功能

## 5. 依赖与外部交互

### 导入的类型

```typescript
import type { Resource } from "../Resource";
import type { ResourceTemplate } from "../ResourceTemplate";
import type { Tool } from "../Tool";
import type { McpAuthStatus } from "./McpAuthStatus";
```

### 依赖关系图

```
McpServerStatus
├── name: string
├── tools: Record<string, Tool>
│   └── Tool
│       ├── name
│       ├── description
│       └── inputSchema
├── resources: Resource[]
│   └── Resource
│       ├── uri
│       ├── name
│       └── mimeType
├── resourceTemplates: ResourceTemplate[]
│   └── ResourceTemplate
│       ├── uriTemplate
│       ├── name
│       └── mimeType
└── authStatus: McpAuthStatus
    └── "authenticated" | "unauthenticated" | "error" | ...

(被依赖)
└── ListMcpServerStatusResponse.data
```

### MCP概念说明

**Tools（工具）**：
- 服务器提供的可调用功能
- 每个工具有名称、描述和输入参数Schema
- 客户端可以调用工具执行操作

**Resources（资源）**：
- 服务器提供的可读数据
- 通过URI标识
- 可以是文件、API响应等

**Resource Templates（资源模板）**：
- 参数化的资源URI模板
- 支持动态资源访问
- 例如：`file:///{path}`

**Auth Status（认证状态）**：
- 显示服务器是否需要认证
- 当前认证状态

## 6. 风险、边界与改进建议

### 潜在风险

1. **数据量大**：工具和资源数量可能很大，影响传输性能
2. **状态过时**：状态信息可能在获取后迅速过时
3. **敏感信息**：工具描述或资源名称可能包含敏感信息
4. **空集合**：某些服务器可能没有工具或资源

### 边界情况

1. **空工具映射**：`tools` 可能为空对象 `{}`
2. **空资源列表**：`resources` 和 `resourceTemplates` 可能为空数组
3. **未知认证状态**：某些服务器可能无法确定认证状态
4. **重复名称**：工具名称在映射中应该是唯一的

### 改进建议

1. **分页支持**：
   ```typescript
   export type McpServerStatus = {
     name: string;
     tools: Record<string, Tool>;
     resources: Resource[];
     resourceTemplates: ResourceTemplate[];
     authStatus: McpAuthStatus;
     // 添加分页信息
     toolsCount?: number;
     resourcesCount?: number;
   };
   ```

2. **添加元数据**：
   ```typescript
   export type McpServerStatus = {
     name: string;
     tools: Record<string, Tool>;
     resources: Resource[];
     resourceTemplates: ResourceTemplate[];
     authStatus: McpAuthStatus;
     // 新增字段
     version?: string;           // 服务器版本
     description?: string;       // 服务器描述
     connectedAt?: number;       // 连接时间戳
     lastError?: string;         // 上次错误信息
   };
   ```

3. **工具分类**：
   ```typescript
   export type McpServerStatus = {
     name: string;
     tools: Record<string, Tool>;
     toolCategories?: Record<string, string[]>;  // 工具分类
     // ...
   };
   ```

4. **缓存控制**：
   ```typescript
   export type McpServerStatus = {
     // ...
     cacheHint?: {
       maxAge: number;           // 建议缓存时间（秒）
       staleWhileRevalidate?: boolean;
     };
   };
   ```

5. **TypeScript类型优化**：
   ```typescript
   // 建议：添加工具查找辅助类型
   export type ToolNames<T extends McpServerStatus> = 
     keyof T["tools"] & string;
   
   // 使用示例
   type MyServerTools = ToolNames<typeof myServerStatus>;
   // MyServerTools = "tool1" | "tool2" | ...
   ```

### 测试建议

- 测试各种集合大小（空、单个、多个）
- 测试特殊字符的工具名称
- 测试认证状态的各种值
- 验证序列化/反序列化的一致性

### 使用示例

```typescript
// 显示服务器状态
function displayServerStatus(status: McpServerStatus): void {
  console.log(`Server: ${status.name}`);
  console.log(`Auth: ${status.authStatus}`);
  
  console.log("\nTools:");
  Object.entries(status.tools).forEach(([name, tool]) => {
    console.log(`  - ${name}: ${tool.description}`);
  });
  
  console.log("\nResources:");
  status.resources.forEach(resource => {
    console.log(`  - ${resource.name} (${resource.uri})`);
  });
  
  console.log("\nResource Templates:");
  status.resourceTemplates.forEach(template => {
    console.log(`  - ${template.name}: ${template.uriTemplate}`);
  });
}

// 查找特定工具
function findTool(
  status: McpServerStatus,
  toolName: string
): Tool | undefined {
  return status.tools[toolName];
}

// 检查是否需要认证
function requiresAuth(status: McpServerStatus): boolean {
  return status.authStatus === "unauthenticated";
}

// 获取资源URI列表
function getResourceUris(status: McpServerStatus): string[] {
  return status.resources.map(r => r.uri);
}
```
