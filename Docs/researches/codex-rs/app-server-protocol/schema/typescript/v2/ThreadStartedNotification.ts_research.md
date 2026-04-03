# ThreadStartedNotification Research Document

## 场景与职责 (Usage Scenarios and Responsibilities)

`ThreadStartedNotification` 是服务器向客户端发送的异步通知，用于广播新线程已成功创建的事件。与 `ThreadStartResponse` 不同，这是一个服务器主动推送的通知，可能被多个订阅者接收。

**核心使用场景：**
1. **多客户端同步**：当线程被创建时，通知所有已连接的客户端
2. **UI 状态更新**：客户端接收通知后更新线程列表或导航状态
3. **协作场景**：在多用户或 Agent 协作场景中广播线程创建事件
4. **审计日志**：记录线程生命周期事件用于分析和监控

**职责范围：**
- 广播线程创建事件
- 提供新线程的完整元数据
- 支持客户端线程列表的实时更新
- 与 `thread/started` 事件方法名对应

## 功能点目的 (Purpose of the Functionality)

**主要设计目标：**

1. **事件驱动架构**
   - 采用发布-订阅模式，解耦线程创建与通知逻辑
   - 支持多个客户端同时接收同一事件

2. **状态同步**
   - 确保所有相关客户端都能及时获知新线程的创建
   - 提供与 `ThreadStartResponse` 一致的线程数据

3. **生命周期管理**
   - 作为线程生命周期的起点事件
   - 与 `ThreadStatusChangedNotification`、`ThreadClosedNotification` 等形成完整生命周期事件链

4. **数据一致性**
   - 通知中携带的 `Thread` 对象与创建者收到的响应一致
   - 确保所有观察者看到相同的初始状态

## 具体技术实现 (Technical Implementation Details)

### 数据结构定义

**Rust 源码**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 4613-4618）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadStartedNotification {
    pub thread: Thread,
}
```

**TypeScript 生成类型**（`ThreadStartedNotification.ts`）：

```typescript
export type ThreadStartedNotification = { thread: Thread };
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `thread` | `Thread` | 新创建线程的完整元数据 |

### Thread 对象结构

```typescript
type Thread = {
    id: string,
    preview: string,           // 通常是第一条用户消息
    ephemeral: boolean,        // 是否为临时线程
    modelProvider: string,     // 模型提供商
    createdAt: number,         // Unix 时间戳（秒）
    updatedAt: number,         // Unix 时间戳（秒）
    status: ThreadStatus,      // 当前状态
    path: string | null,       // 磁盘路径（临时线程为 null）
    cwd: string,               // 工作目录
    cliVersion: string,        // CLI 版本
    source: SessionSource,     // 来源（CLI、VSCode 等）
    agentNickname: string | null,
    agentRole: string | null,
    gitInfo: GitInfo | null,
    name: string | null,       // 用户可见的线程标题
    turns: Array<Turn>,        // 轮次列表（通常为空）
};
```

### 通知注册

**RPC 协议注册**（`codex-rs/app-server-protocol/src/protocol/common.rs` line 877）：

```rust
server_notification_definitions! {
    // ...
    ThreadStarted => "thread/started" (v2::ThreadStartedNotification),
    // ...
}
```

### ServerNotification 枚举

```rust
pub enum ServerNotification {
    // ...
    ThreadStarted(v2::ThreadStartedNotification),
    // ...
}
```

## 关键代码路径与文件引用 (Key Code Paths and File References)

### 协议定义
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 4613-4618)
  - `ThreadStartedNotification` 结构体定义

- **`codex-rs/app-server-protocol/src/protocol/common.rs`** (line 877)
  - 通知方法注册：`ThreadStarted => "thread/started"`

### TypeScript 生成文件
- **`codex-rs/app-server-protocol/schema/typescript/v2/ThreadStartedNotification.ts`**
- **`codex-rs/app-server-protocol/schema/json/v2/ThreadStartedNotification.json`**

### 服务器实现
- **`codex-rs/app-server/src/bespoke_event_handling.rs`**
  - 事件处理和通知分发逻辑

- **`codex-rs/app-server/src/in_process.rs`**
  - 线程创建后的通知触发

### 测试文件
- **`codex-rs/app-server/tests/suite/v2/thread_start.rs`** (lines 107-148)
  - 测试 `thread/started` 通知的接收和验证
  - 验证通知中的线程数据与响应一致

### 客户端实现
- **`codex-rs/tui_app_server/src/app.rs`**
  - TUI 应用接收和处理线程通知

## 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `Thread` | 线程核心数据结构 |
| `ThreadStatus` | 线程状态枚举 |
| `SessionSource` | 会话来源枚举 |
| `GitInfo` | Git 元数据 |
| `Turn` | 轮次数据结构 |

### 通知流程

```
客户端 A 调用 thread/start
        ↓
服务器创建线程
        ↓
服务器发送 ThreadStartResponse 给客户端 A
        ↓
服务器广播 ThreadStartedNotification 给所有订阅客户端
        ↓
客户端 A/B/C 接收通知并更新 UI
```

### 序列化格式

**JSON-RPC 2.0 通知格式：**

```json
{
    "jsonrpc": "2.0",
    "method": "thread/started",
    "params": {
        "thread": {
            "id": "thread-uuid",
            "preview": "",
            "ephemeral": false,
            "modelProvider": "openai",
            "createdAt": 1704067200,
            "updatedAt": 1704067200,
            "status": { "type": "idle" },
            "path": "/home/user/.codex/sessions/...",
            "cwd": "/home/user/project",
            "cliVersion": "1.0.0",
            "source": "cli",
            "agentNickname": null,
            "agentRole": null,
            "gitInfo": null,
            "name": null,
            "turns": []
        }
    }
}
```

## 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 已知风险

1. **通知顺序**
   - 测试代码中明确检查了 `thread/start` 响应不应有前置的 `thread/status/changed`
   - 需要确保通知顺序的一致性

2. **数据一致性**
   - 通知中的 `Thread` 必须与创建响应中的完全一致
   - 测试验证了 `thread.id`、`thread.name`、`thread.ephemeral` 等字段的一致性

3. **空值处理**
   - 新线程的 `name` 字段为 `null`，需要正确序列化为 `null` 而非省略
   - `preview` 字段在新线程中为空字符串

### 边界情况

1. **临时线程通知**
   - 临时线程（`ephemeral: true`）同样会触发通知
   - `path` 字段为 `null`，客户端需要正确处理

2. **多客户端并发**
   - 多个客户端同时创建线程时，通知需要正确路由
   - 避免通知风暴或重复通知

3. **网络分区**
   - 通知可能在传输中丢失
   - 客户端需要能够通过 `thread/list` 或 `thread/read` 进行状态同步

### 改进建议

1. **通知去重**
   - 考虑添加通知序列号或时间戳，便于客户端去重
   - 对于创建者客户端，可以考虑跳过通知（因为已有响应）

2. **增量更新**
   - 当前通知携带完整的 `Thread` 对象
   - 对于高频更新场景，考虑支持增量更新模式

3. **批量通知**
   - 支持批量线程创建时的合并通知
   - 减少网络开销和客户端处理压力

4. **订阅控制**
   - 考虑支持细粒度的通知订阅（按线程、按事件类型）
   - 与现有的 `optOutNotificationMethods` 机制结合

5. **错误处理**
   - 当前通知是单向的，无确认机制
   - 考虑添加轻量级的接收确认或重试机制
