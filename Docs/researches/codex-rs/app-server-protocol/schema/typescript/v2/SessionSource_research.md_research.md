# SessionSource 研究文档

## 场景与职责

`SessionSource` 是 Codex App Server Protocol v2 中用于定义会话来源的枚举类型。它标识了 Codex 会话的创建来源，如 CLI、VSCode 扩展、exec 命令、App Server 或子代理。

该类型在 `Thread` 结构中使用，用于追踪线程的创建来源，支持遥测分析、用户行为追踪和调试。

## 功能点目的

1. **来源追踪**：标识会话的创建来源
2. **遥测分析**：支持按来源统计使用数据
3. **功能适配**：根据来源适配不同的行为
4. **调试支持**：帮助诊断问题来源

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase", export_to = "v2/")]
#[derive(Default)]
pub enum SessionSource {
    Cli,
    #[serde(rename = "vscode")]
    #[ts(rename = "vscode")]
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

```typescript
// TypeScript 生成类型 (schema/typescript/v2/SessionSource.ts)
import type { SubAgentSource } from "../SubAgentSource";

export type SessionSource = "cli" | "vscode" | "exec" | "appServer" | { "subAgent": SubAgentSource } | "unknown";
```

### 变体说明

| 变体 | 值 | 说明 |
|------|-----|------|
| `Cli` | `"cli"` | 命令行界面 |
| `VsCode` | `"vscode"` | VSCode 扩展 |
| `Exec` | `"exec"` | `codex exec` 命令 |
| `AppServer` | `"appServer"` | App Server（MCP） |
| `SubAgent` | `{ "subAgent": SubAgentSource }` | 子代理创建 |
| `Unknown` | `"unknown"` | 未知来源 |

### 核心协议映射

```rust
// CoreSessionSource 定义在 codex_protocol::protocol
pub enum CoreSessionSource {
    Cli,
    VSCode,
    Exec,
    Mcp,  // 内部称为 Mcp，API 中称为 AppServer
    SubAgent(SubAgentSource),
    Unknown,
}

// 注意：CoreSessionSource::Mcp 映射到 SessionSource::AppServer
// 这是为了与 API 命名保持一致
```

### 使用上下文

```rust
// 在 Thread 结构中使用
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct Thread {
    pub id: String,
    // ...
    /// Origin of the thread (CLI, VSCode, codex exec, codex app-server, etc.).
    pub source: SessionSource,
    // ...
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 1463-1501)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/SessionSource.ts`

### 相关类型
- `SubAgentSource`: 子代理来源详情
- `Thread`: 包含 `source` 字段
- `CoreSessionSource`: 核心协议类型

### 使用场景
- 线程创建时记录来源
- 遥测数据收集
- 调试信息输出
- 功能开关控制

## 依赖与外部交互

### 内部依赖
- `CoreSessionSource`: 核心协议类型
- `CoreSubAgentSource`: 子代理来源类型
- `serde`: 序列化/反序列化
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**线程信息示例**:
```json
{
    "id": "thread-123",
    "preview": "Hello, can you help me...",
    "ephemeral": false,
    "modelProvider": "openai",
    "createdAt": 1699999999,
    "updatedAt": 1699999999,
    "status": "active",
    "cwd": "/home/user/project",
    "cliVersion": "1.0.0",
    "source": "cli",
    "turns": []
}
```

**子代理来源示例**:
```json
{
    "source": {
        "subAgent": {
            "parentThreadId": "thread-parent-456",
            "agentRole": "code-reviewer",
            "agentNickname": "reviewer-1"
        }
    }
}
```

## 风险、边界与改进建议

### 当前限制
1. **命名不一致**：内部 `Mcp` 与 API `AppServer` 的命名差异可能造成混淆
2. **有限来源**：只支持预定义的来源类型
3. **无版本信息**：不包含来源客户端的版本信息

### 边界情况
1. **未知来源**：使用 `#[serde(other)]` 处理未知的来源值
2. **子代理嵌套**：子代理可能创建子代理，形成嵌套链
3. **来源切换**：会话来源在生命周期中不应改变

### 遥测使用

从代码搜索可以看到 `SessionSource` 在遥测中的使用：

```rust
// otel/src/events/session_telemetry.rs
pub struct SessionTelemetry {
    pub source: SessionSource,
    // ...
}

// 用于记录会话来源的遥测数据
```

### 改进建议

1. **添加版本信息**：
   ```rust
   pub struct SessionSourceInfo {
       pub source: SessionSource,
       pub version: Option<String>,  // 客户端版本
       pub platform: Option<String>, // 平台信息
   }
   ```

2. **添加更多来源**：
   ```rust
   pub enum SessionSource {
       // ...
       JetBrains,  // JetBrains IDE 插件
       Vim,        // Vim 插件
       Emacs,      // Emacs 插件
       Web,        // Web 界面
       Api,        // 直接 API 调用
   }
   ```

3. **添加来源能力**：
   ```rust
   pub struct SessionSource {
       pub kind: SessionSourceKind,
       pub capabilities: SourceCapabilities,  // 来源支持的功能
   }
   
   pub struct SourceCapabilities {
       pub supports_ui: bool,
       pub supports_filesystem: bool,
       pub supports_network: bool,
   }
   ```

### 兼容性注意
- 使用 `#[serde(other)]` 确保向前兼容（处理未知来源）
- `VsCode` 使用小写 `"vscode"` 序列化
- `SubAgent` 使用嵌套对象格式

### 使用示例

```rust
// 创建线程时记录来源
let thread = Thread {
    id: generate_thread_id(),
    source: SessionSource::Cli,
    // ...
};

// 子代理线程
let sub_agent_thread = Thread {
    id: generate_thread_id(),
    source: SessionSource::SubAgent(CoreSubAgentSource {
        parent_thread_id: parent_id,
        agent_role: Some("assistant".to_string()),
        agent_nickname: Some("helper-1".to_string()),
    }),
    // ...
};
```

### 来源统计示例

```rust
// 遥测分析中使用
fn analyze_session_sources(threads: &[Thread]) -> HashMap<SessionSource, u32> {
    let mut counts = HashMap::new();
    for thread in threads {
        *counts.entry(thread.source.clone()).or_insert(0) += 1;
    }
    counts
}

// 结果示例：
// {
//     SessionSource::Cli: 100,
//     SessionSource::VsCode: 250,
//     SessionSource::AppServer: 50,
// }
```
