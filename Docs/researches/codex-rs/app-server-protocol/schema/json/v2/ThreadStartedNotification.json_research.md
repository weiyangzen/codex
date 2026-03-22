# ThreadStartedNotification.json 研究文档

## 场景与职责

`ThreadStartedNotification` 是 Codex App-Server Protocol v2 中的服务器通知（Server Notification），当新线程成功创建并启动后，服务器向所有订阅的客户端广播此通知。

该通知的核心职责：
- 广播线程创建事件给所有相关客户端
- 使多客户端场景（如 VSCode 扩展 + CLI）保持状态同步
- 提供线程初始状态的完整快照
- 支持线程监控和审计功能

与 `ThreadStartResponse` 的区别：
- `ThreadStartResponse`：RPC 响应，仅返回给调用 `thread/start` 的客户端
- `ThreadStartedNotification`：服务器推送通知，广播给所有订阅该线程的客户端

## 功能点目的

### 1. 线程信息广播

| 字段 | 类型 | 用途 |
|------|------|------|
| `thread` | `Thread` | 创建的线程完整信息（**必需**） |

### 2. Thread 结构字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 线程唯一标识符 |
| `created_at` | `i64` | 创建时间戳（Unix 秒） |
| `updated_at` | `i64` | 最后更新时间戳 |
| `cwd` | `String` | 工作目录 |
| `status` | `ThreadStatus` | 当前状态 |
| `turns` | `Vec<Turn>` | 回合列表（启动时为空） |
| `source` | `SessionSource` | 来源（cli/vscode/exec/appServer/subAgent） |
| `ephemeral` | `bool` | 是否为临时线程 |
| `model_provider` | `String` | 模型提供商 |
| `cli_version` | `String` | CLI 版本 |
| `preview` | `String` | 预览文本（通常为第一条用户消息） |
| `name` | `Option<String>` | 用户指定的线程名称 |
| `path` | `Option<String>` | 线程在磁盘上的路径（不稳定） |
| `git_info` | `Option<GitInfo>` | Git 元数据（branch/sha/originUrl） |
| `agent_nickname` | `Option<String>` | 子代理昵称（AgentControl 创建时） |
| `agent_role` | `Option<String>` | 子代理角色（AgentControl 创建时） |

### 3. 嵌套类型定义

#### ThreadStatus（线程状态）

```json
{
  "oneOf": [
    { "type": "object", "properties": { "type": { "enum": ["notLoaded"] } } },
    { "type": "object", "properties": { "type": { "enum": ["idle"] } } },
    { "type": "object", "properties": { "type": { "enum": ["systemError"] } } },
    { "type": "object", "properties": { 
        "type": { "enum": ["active"] },
        "activeFlags": { "items": { "$ref": "#/definitions/ThreadActiveFlag" } }
    }}
  ]
}
```

#### SessionSource（会话来源）

```json
{
  "oneOf": [
    { "enum": ["cli", "vscode", "exec", "appServer", "unknown"] },
    { "type": "object", "properties": { "subAgent": { "$ref": "#/definitions/SubAgentSource" } } }
  ]
}
```

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadStartedNotification {
    pub thread: Thread,
}
```

### 通知注册

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs:877
server_notification_definitions! {
    ThreadStarted => "thread/started" (v2::ThreadStartedNotification),
    // ... 其他通知
}
```

### Thread 结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct Thread {
    pub id: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub cwd: String,
    pub status: ThreadStatus,
    pub turns: Vec<Turn>,
    pub source: SessionSource,
    pub ephemeral: bool,
    pub model_provider: String,
    pub cli_version: String,
    pub preview: String,
    pub name: Option<String>,
    pub path: Option<String>,
    pub git_info: Option<GitInfo>,
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
}
```

### 序列化特性

1. **camelCase 命名**：所有字段使用 camelCase 序列化
2. **TypeScript 导出**：通过 `ts_rs` 生成 TypeScript 类型到 `v2/` 目录
3. **JSON Schema 生成**：通过 `schemars` 生成 JSON Schema

### 嵌套类型的完整定义

#### Turn（回合）

```rust
pub struct Turn {
    pub id: String,
    pub status: TurnStatus,  // completed, interrupted, failed, inProgress
    pub items: Vec<ThreadItem>,
    pub error: Option<TurnError>,
}
```

#### ThreadItem（线程项）

支持多种类型的线程项：
- `userMessage`: 用户消息
- `agentMessage`: 代理消息
- `plan`: 计划项（实验性）
- `reasoning`: 推理内容
- `commandExecution`: 命令执行
- `fileChange`: 文件变更
- `mcpToolCall`: MCP 工具调用
- `dynamicToolCall`: 动态工具调用
- `collabAgentToolCall`: 协作代理工具调用
- `webSearch`: 网页搜索
- `imageView`: 图片查看
- `imageGeneration`: 图片生成
- `enteredReviewMode`/`exitedReviewMode`: 审查模式
- `contextCompaction`: 上下文压缩

#### GitInfo

```rust
pub struct GitInfo {
    pub sha: Option<String>,
    pub branch: Option<String>,
    pub origin_url: Option<String>,
}
```

## 关键代码路径与文件引用

### 定义位置
- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs:4616-4618`
- **Thread 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs:699-811`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/ThreadStartedNotification.json`

### 通知注册
- **位置**：`codex-rs/app-server-protocol/src/protocol/common.rs:874-940`
- **方法名**：`thread/started`
- **通知类型**：`ThreadStartedNotification`

### 相关类型定义

| 类型 | 位置 | 说明 |
|------|------|------|
| `Thread` | `v2.rs:699-811` | 线程核心结构 |
| `ThreadStatus` | `ThreadStartResponse.json` schema | 线程状态 |
| `Turn` | `ThreadStartResponse.json` schema | 回合结构 |
| `ThreadItem` | `ThreadStartResponse.json` schema | 线程项枚举 |
| `SessionSource` | `ThreadStartResponse.json` schema | 会话来源 |
| `SubAgentSource` | `ThreadStartResponse.json` schema | 子代理来源 |
| `GitInfo` | `ThreadStartResponse.json` schema | Git 元数据 |

### Schema 生成与测试

- **生成位置**：`codex-rs/app-server-protocol/src/export.rs`
- **测试验证**：`export.rs:2469`
```rust
{ "$ref": "#/definitions/v2/ThreadStartedNotification" },
```

- **Schema 写入**：`export.rs:2519-2527`
```rust
"ThreadStartedNotification": {
    "title": "ThreadStartedNotification",
    "type": "object",
    "properties": {
        "thread": { "$ref": "#/definitions/v2/Thread" }
    },
    "required": ["thread"]
}
```

## 依赖与外部交互

### 内部依赖

| 依赖 | 用途 |
|------|------|
| `Thread` | 线程核心数据结构 |
| `ThreadStatus` | 线程状态枚举 |
| `Turn` | 回合数据结构 |
| `SessionSource` | 会话来源枚举 |
| `GitInfo` | Git 元数据 |

### 通知系统架构

```
┌─────────────┐     thread/start      ┌─────────────┐
│   Client A  │ --------------------> │   Server    │
│  (调用者)    │                       │             │
└─────────────┘                       │  创建线程    │
                                      │             │
┌─────────────┐                       │  广播通知    │
│   Client B  │ <-------------------- │             │
│  (订阅者)    │  notification:thread/started       │
└─────────────┘                       └─────────────┘
                                      │
┌─────────────┐                       │
│   Client C  │ <---------------------│
│  (订阅者)    │  notification:thread/started
└─────────────┘
```

### 与 ThreadStartResponse 的协同

| 特性 | ThreadStartResponse | ThreadStartedNotification |
|------|--------------------|---------------------------|
| 方向 | Server -> Client | Server -> Client |
| 触发 | RPC 调用响应 | 事件广播 |
| 接收者 | 仅调用者 | 所有订阅者 |
| 包含字段 | Thread + 配置详情 | Thread |
| 用途 | 确认创建结果 | 状态同步 |

### 客户端处理建议

1. **去重处理**：调用者可能同时收到 Response 和 Notification
2. **状态合并**：使用 Notification 更新本地线程列表
3. **订阅管理**：通过 `thread/unsubscribe` 取消订阅

## 风险、边界与改进建议

### 已知风险

1. **通知丢失**
   - 如果客户端在通知发送后才订阅，可能错过初始状态
   - 建议新订阅者主动调用 `thread/read` 获取当前状态

2. **状态不一致**
   - `turns` 在启动通知中为空，不代表线程无历史
   - 需要 `thread/resume` 或 `thread/read` 获取完整历史

3. **路径不稳定**
   - `path` 字段标记为 `[UNSTABLE]`，未来可能变更
   - 客户端不应依赖此字段进行持久化

### 边界情况

1. **ephemeral 线程**
   - `ephemeral: true` 时 `path` 为 null
   - 临时线程不会触发存档相关通知

2. **SubAgent 来源**
   - `source.subAgent` 包含嵌套信息（depth, parent_thread_id 等）
   - 需要递归处理以理解代理层级

3. **GitInfo 缺失**
   - 非 Git 仓库中创建的线程 `git_info` 为 null
   - 子代理线程可能继承父线程的 git_info

### 改进建议

1. **通知增强**
   - 添加 `created_by` 字段标识创建者
   - 添加 `initial_config` 字段显示初始配置

2. **序列化优化**
   - 考虑为大型线程提供 `ThreadSummary` 轻量版本
   - 添加 `include_turns` 选项控制回合数据

3. **文档完善**
   - 明确 `preview` 字段的截断逻辑
   - 文档化 `agent_nickname` 和 `agent_role` 的生成规则

4. **测试覆盖**
   - 增加多客户端订阅场景测试
   - 增加通知顺序保证测试

5. **向后兼容**
   - 监控 `path` 字段的使用情况
   - 考虑添加 deprecation 计划
