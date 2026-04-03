# SessionSource 研究文档

## 场景与职责

`SessionSource` 是 Codex app-server-protocol v2 协议中的会话来源类型，用于标识会话的创建来源。该类型支持多种来源：CLI、VS Code、Exec、App Server、SubAgent 等，便于系统追踪会话的创建上下文和进行来源特定的处理。

在 Codex 的会话管理体系中，`SessionSource` 承担以下职责：
1. **来源追踪**：记录会话的创建来源
2. **行为适配**：根据来源调整行为（如交互模式）
3. **安全控制**：基于来源应用不同的安全策略
4. **分析统计**：用于使用分析和遥测

## 功能点目的

### 核心功能
- **来源标识**：标识会话的创建方式（CLI、VS Code、Exec 等）
- **嵌套追踪**：支持 SubAgent 来源的嵌套追踪
- **默认来源**：提供默认值（VSCode）
- **未知处理**：支持未知来源的优雅处理

### 设计意图
- **覆盖全面**：覆盖所有已知的会话创建方式
- **可扩展**：易于添加新的来源类型
- **嵌套支持**：支持子代理的嵌套来源追踪
- **向后兼容**：支持未知来源的序列化

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`SessionSource.ts`）：
```typescript
export type SessionSource = 
  | "cli" 
  | "vscode" 
  | "exec" 
  | "appServer" 
  | { "subAgent": SubAgentSource } 
  | "unknown";
```

**Rust 定义**（`v2.rs` 行 1464-1501）：
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

### 变体说明

| 变体 | 说明 | 使用场景 |
|------|------|----------|
| `Cli` | 命令行界面 | 用户通过终端使用 Codex |
| `VsCode` | VS Code 扩展 | 用户通过 VS Code 扩展使用（默认） |
| `Exec` | 执行模式 | 通过 `codex exec` 执行脚本 |
| `AppServer` | 应用服务器 | 通过 MCP 协议访问 |
| `SubAgent` | 子代理 | 由其他代理创建的子会话 |
| `Unknown` | 未知来源 | 无法识别的来源 |

### SubAgentSource 详情

**核心定义**（`protocol/src/protocol.rs`）：
```rust
pub enum SubAgentSource {
    ThreadSpawn {
        agent_nickname: String,
        agent_role: String,
        depth: i32,
    },
    MemoryConsolidation,
    Review,
    Other(String),
}
```

### 与核心类型的映射

| SessionSource | CoreSessionSource | 说明 |
|---------------|-------------------|------|
| `Cli` | `Cli` | 命令行 |
| `VsCode` | `VSCode` | VS Code 扩展 |
| `Exec` | `Exec` | 执行模式 |
| `AppServer` | `Mcp` | MCP 协议 |
| `SubAgent` | `SubAgent` | 子代理 |
| `Unknown` | `Unknown` | 未知 |

### 嵌套深度追踪

在 `core/src/agent/guards.rs` 行 53-61：
```rust
fn session_depth(session_source: &SessionSource) -> i32 {
    match session_source {
        SessionSource::SubAgent(SubAgentSource::ThreadSpawn { depth, .. }) => *depth,
        SessionSource::SubAgent(_) => 0,
        _ => 0,
    }
}

pub(crate) fn next_thread_spawn_depth(session_source: &SessionSource) -> i32 {
    session_depth(session_source) + 1
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 1464-1501
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/SessionSource.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/ThreadReadResponse.json`

### 使用位置
- **Thread**：`v2.rs` 行 3498 - 线程的来源字段
- ** guards**：`core/src/agent/guards.rs` - 深度控制
- **控制逻辑**：`core/src/agent/control.rs` - 代理控制

### 相关类型
- `CoreSessionSource`：核心协议中的对应类型（`protocol/src/protocol.rs` 行 2269）
- `SubAgentSource`：子代理来源类型
- `Thread`：包含 `source: SessionSource`（行 3498）

### 使用示例

在 `core/src/agent/control.rs` 行 232-266：
```rust
fn create_sub_agent_session_source(
    session_source: SessionSource,
) -> SessionSource {
    match session_source {
        SessionSource::SubAgent(SubAgentSource::ThreadSpawn { depth, .. }) => {
            SessionSource::SubAgent(SubAgentSource::ThreadSpawn {
                depth: depth + 1,
                // ...
            })
        }
        _ => SessionSource::SubAgent(SubAgentSource::ThreadSpawn {
            depth: 1,
            // ...
        }),
    }
}
```

## 依赖与外部交互

### 依赖项
- `CoreSubAgentSource`：核心子代理来源类型
- `serde`：序列化/反序列化支持
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 上游依赖
- `CoreSessionSource`（核心协议）：`protocol/src/protocol.rs`

### 下游使用
- `Thread`：线程类型
- `ConversationSummary`：会话摘要
- 遥测和统计

### 协议集成
- 通过 `thread/start` 等响应返回
- 用于遥测数据收集
- 影响交互模式决策

## 风险、边界与改进建议

### 潜在风险
1. **来源伪造**：恶意客户端可能伪造来源信息
2. **嵌套过深**：SubAgent 嵌套过深可能导致性能问题
3. **来源混淆**：Mcp → AppServer 的映射可能造成混淆
4. **统计偏差**：Unknown 来源过多影响分析准确性

### 边界情况
1. **循环嵌套**：SubAgent 循环创建导致的无限嵌套
2. **深度限制**：超过最大嵌套深度的处理
3. **序列化失败**：未知变体的序列化处理
4. **来源变更**：会话运行中来源变更的情况

### 改进建议
1. **安全增强**：
   - 添加来源验证机制
   - 实现来源签名
   - 限制 SubAgent 嵌套深度

2. **功能扩展**：
   ```rust
   pub enum SessionSource {
       // 现有变体...
       WebInterface,      // Web 界面
       MobileApp,         // 移动应用
       Api,               // 直接 API 调用
       ScheduledTask,     // 定时任务
   }
   ```

3. **元数据增强**：
   ```rust
   pub struct SessionSourceInfo {
       pub source: SessionSource,
       /// 创建时间戳
       pub created_at: i64,
       /// 创建者标识
       pub created_by: Option<String>,
       /// 客户端版本
       pub client_version: Option<String>,
   }
   ```

4. **可观测性**：
   - 记录来源分布统计
   - 监控嵌套深度
   - 提供来源追踪可视化

5. **用户体验**：
   - 在 UI 中显示会话来源
   - 提供来源筛选功能
   - 显示嵌套层级

6. **企业功能**：
   - 支持按来源设置策略
   - 实现来源审计日志
   - 提供来源合规报告
