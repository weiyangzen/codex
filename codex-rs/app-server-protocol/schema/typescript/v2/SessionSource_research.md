# SessionSource 研究文档

## 1. 场景与职责

`SessionSource` 是 Codex app-server-protocol v2 协议中的会话来源类型，用于标识会话的创建来源。该类型支持多种来源：CLI、VS Code、Exec、App Server、SubAgent 等，便于系统追踪会话的创建上下文和进行来源特定的处理。

### 使用场景
- **会话追踪**：识别会话是从哪个客户端或集成点创建的
- **来源特定逻辑**：根据来源执行不同的业务逻辑
- **审计和统计**：按来源统计使用情况和性能指标
- **子代理管理**：追踪子代理会话的父级关系

## 2. 功能点目的

该类型的核心目的是：
1. **来源标识**：明确会话的创建来源
2. **上下文传递**：在子代理场景中保持调用链信息
3. **默认行为**：为不同来源提供适当的默认配置

### 来源类型对比
| 来源 | 描述 | 典型使用场景 |
|------|------|--------------|
| `cli` | 命令行界面 | 终端用户使用 |
| `vscode` | VS Code 扩展 | IDE 集成（默认来源） |
| `exec` | Exec 模式 | 脚本和自动化 |
| `appServer` | App Server | MCP 协议接入 |
| `subAgent` | 子代理 | 代理间协作 |
| `unknown` | 未知来源 | 无法识别的来源 |

## 3. 具体技术实现

### TypeScript 类型定义
```typescript
import type { SubAgentSource } from "../SubAgentSource";

export type SessionSource = 
  | "cli" 
  | "vscode" 
  | "exec" 
  | "appServer" 
  | { "subAgent": SubAgentSource } 
  | "unknown";
```

### 字段说明
| 值 | 说明 |
|----|------|
| `"cli"` | 命令行界面创建的会话 |
| `"vscode"` | VS Code 扩展创建的会话（默认） |
| `"exec"` | Exec 模式创建的会话 |
| `"appServer"` | App Server（MCP）创建的会话 |
| `{ "subAgent": SubAgentSource }` | 子代理创建的会话，包含详细的子代理来源信息 |
| `"unknown"` | 未知或无法识别的来源 |

### SubAgentSource 类型
```rust
// 核心协议定义
codex_protocol::protocol::SubAgentSource {
    Review,
    Compact,
    ThreadSpawn { parent_thread_id, depth, agent_nickname, agent_role },
    MemoryConsolidation,
    Other(String),
}
```

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase", export_to = "v2/")]
#[derive(Default)]
pub enum SessionSource {
    Cli,
    #[serde(rename = "vscode")]
    #[ts(rename = "vscode")]
    #[default]
    VsCode,
    Exec,
    AppServer,
    SubAgent(CoreSubAgentSource),
    #[serde(other)]
    Unknown,
}
```

### 类型转换实现
```rust
impl From<CoreSessionSource> for SessionSource {
    fn from(value: CoreSessionSource) -> Self {
        match value {
            CoreSessionSource::Cli => SessionSource::Cli,
            CoreSessionSource::VSCode => SessionSource::VsCode,
            CoreSessionSource::Exec => SessionSource::Exec,
            CoreSessionSource::Mcp => SessionSource::AppServer,
            CoreSessionSource::SubAgent(sub) => SessionSource::SubAgent(sub),
            CoreSessionSource::Unknown => SessionSource::Unknown,
        }
    }
}

impl From<SessionSource> for CoreSessionSource {
    fn from(value: SessionSource) -> Self {
        match value {
            SessionSource::Cli => CoreSessionSource::Cli,
            SessionSource::VsCode => CoreSessionSource::VSCode,
            SessionSource::Exec => CoreSessionSource::Exec,
            SessionSource::AppServer => CoreSessionSource::Mcp,
            SessionSource::SubAgent(sub) => CoreSessionSource::SubAgent(sub),
            SessionSource::Unknown => CoreSessionSource::Unknown,
        }
    }
}
```

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1460-1501)
- **核心协议**: `codex-rs/protocol/src/protocol.rs` (行 2265-2353)
- **TypeScript 文件**: `codex-rs/app-server-protocol/schema/typescript/v2/SessionSource.ts`

### 使用位置

#### 会话元数据
- **文件**: `codex-rs/protocol/src/protocol.rs` (行 2360-2374)
  - 作为 `SessionMeta` 的 `source` 字段

#### 过滤器
- **文件**: `codex-rs/app-server/src/filters.rs` (行 63-78, 132-133)
  - 根据来源进行过滤和处理

#### 消息处理器
- **文件**: `codex-rs/app-server/src/codex_message_processor.rs` (行 8191-8836)
  - 处理子代理来源的会话创建

#### API 请求头
- **文件**: `codex-rs/codex-api/src/requests/headers.rs` (行 18-26)
  - 将来源转换为请求头

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`

## 5. 依赖与外部交互

### 导入依赖
| 类型 | 来源 | 说明 |
|------|------|------|
| `SubAgentSource` | `../SubAgentSource` | 子代理来源详情 |

### 被依赖类型
- `SessionMeta` - 会话元数据
- `CreateThreadParams` - 创建线程参数

### 核心协议映射
| v2 类型 | 核心类型 |
|---------|----------|
| `SessionSource::Cli` | `CoreSessionSource::Cli` |
| `SessionSource::VsCode` | `CoreSessionSource::VSCode` |
| `SessionSource::Exec` | `CoreSessionSource::Exec` |
| `SessionSource::AppServer` | `CoreSessionSource::Mcp` |
| `SessionSource::SubAgent` | `CoreSessionSource::SubAgent` |
| `SessionSource::Unknown` | `CoreSessionSource::Unknown` |

## 6. 风险、边界与改进建议

### 潜在风险
1. **默认值依赖**：`VsCode` 是默认来源，可能导致统计偏差
2. **序列化兼容性**：`#[serde(other)]` 处理未知变体
3. **子代理嵌套**：深层嵌套的子代理可能产生复杂的来源链

### 边界情况
- **未知来源**：无法识别的来源被映射为 `Unknown`
- **MCP 映射**：`AppServer` 对应核心协议的 `Mcp`，命名不一致
- **子代理深度**：`ThreadSpawn` 包含 `depth` 字段限制嵌套层级

### 改进建议
1. **统一命名**：
   - 考虑将 `AppServer` 重命名为 `Mcp` 以与核心协议一致
   - 或添加别名支持

2. **添加版本信息**：
   ```typescript
   export type SessionSource = 
     | { type: "cli", version?: string }
     | { type: "vscode", version?: string }
     | ...;
   ```

3. **子代理链追踪**：
   ```typescript
   export type SubAgentSource = {
     type: "threadSpawn",
     parentThreadId: string,
     depth: number,
     agentNickname?: string,
     agentRole?: string,
     rootSource?: SessionSource;  // 追踪原始来源
   };
   ```

4. **统计增强**：
   - 添加来源使用统计 API
   - 支持按来源的性能分析

### 使用示例
```typescript
// 创建会话时指定来源
const createThreadParams = {
  source: "vscode",
  // ...
};

// 处理子代理来源
function handleSessionSource(source: SessionSource): void {
  if (typeof source === "object" && "subAgent" in source) {
    const subAgent = source.subAgent;
    console.log(`Sub-agent depth: ${subAgent.depth}`);
    
    if (subAgent.type === "threadSpawn") {
      console.log(`Agent: ${subAgent.agentNickname} (${subAgent.agentRole})`);
    }
  } else {
    console.log(`Source: ${source}`);
  }
}

// 类型守卫
function isSubAgentSource(source: SessionSource): source is { subAgent: SubAgentSource } {
  return typeof source === "object" && "subAgent" in source;
}
```

### 相关类型关系
```
SessionMeta
├── id: ThreadId
├── source: SessionSource  <-- 本类型
│   ├── "cli"
│   ├── "vscode" (default)
│   ├── "exec"
│   ├── "appServer"
│   ├── { subAgent: SubAgentSource }
│   │   ├── Review
│   │   ├── Compact
│   │   ├── ThreadSpawn { parentThreadId, depth, agentNickname, agentRole }
│   │   ├── MemoryConsolidation
│   │   └── Other(string)
│   └── "unknown"
└── ...
```

### 注意事项
- `VsCode` 是默认来源，如果未显式指定来源，将使用此值
- `AppServer` 与核心协议的 `Mcp` 对应，这是历史命名原因
- 子代理来源包含详细的上下文信息，用于追踪调用链
