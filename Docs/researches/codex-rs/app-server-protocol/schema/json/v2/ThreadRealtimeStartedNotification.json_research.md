# ThreadRealtimeStartedNotification.json 研究文档

## 场景与职责

`ThreadRealtimeStartedNotification` 是 Codex App-Server Protocol v2 中的实验性服务器推送通知，用于确认实时对话（Realtime Conversation）会话已成功启动并准备好进行音频传输。

**核心场景：**
1. **启动确认** - 确认 `thread/realtime/start` 请求成功，后端实时服务已连接
2. **会话标识** - 提供后端分配的会话 ID，用于调试和追踪
3. **版本协商** - 告知客户端所使用的实时对话协议版本
4. **状态同步** - 客户端收到后可开始音频采集和传输

**典型使用流程：**
```
Client -> thread/realtime/start { threadId, prompt } -> Server
Server -> (建立 WebSocket 连接到后端实时服务)
Server -> ThreadRealtimeStartedNotification { threadId, sessionId, version } -> Client
Client -> (开始音频采集和发送)
```

**实验性状态：**
- 标记为 `EXPERIMENTAL`
- 需要启用 `realtime_conversation` 功能标志

## 功能点目的

### 1. 通知结构设计

```json
{
  "threadId": "thread-uuid-string",
  "sessionId": "sess-backend-id",
  "version": "v2"
}
```

**设计意图：**
- **明确关联**：`threadId` 关联到客户端请求的线程
- **会话追踪**：`sessionId` 标识后端实时服务会话，用于调试
- **版本协商**：`version` 确认协议版本，支持未来扩展

### 2. RealtimeConversationVersion 枚举

```rust
pub enum RealtimeConversationVersion {
    V1,  // 初始版本
    V2,  // 当前推荐版本
}
```

**版本演进：**
- **V1**：早期实验版本
- **V2**：当前稳定版本，支持更多功能和优化

### 3. 与 ThreadRealtimeStartResponse 的关系

| 特性 | ThreadRealtimeStartResponse | ThreadRealtimeStartedNotification |
|------|----------------------------|-----------------------------------|
| 类型 | RPC 响应 | 服务器通知 |
| 触发 | 立即返回 | 后端连接成功后发送 |
| 内容 | 空（`{}`） | 会话信息（sessionId, version） |
| 用途 | 确认请求接收 | 确认后端就绪 |

**典型序列：**
```
Client -> thread/realtime/start -> Server
Server -> ThreadRealtimeStartResponse {} -> Client  (立即)
Server -> (建立后端 WebSocket 连接)
Server -> ThreadRealtimeStartedNotification -> Client  (异步)
```

## 具体技术实现

### 1. Rust 源码定义

**文件路径：** `codex-rs/app-server-protocol/src/protocol/v2.rs:3766-3774`

```rust
/// EXPERIMENTAL - emitted when thread realtime startup is accepted.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRealtimeStartedNotification {
    pub thread_id: String,
    pub session_id: Option<String>,
    pub version: RealtimeConversationVersion,
}
```

**关键属性：**
- `pub session_id: Option<String>` - 后端会话 ID，可能为 null
- `pub version: RealtimeConversationVersion` - 协议版本

**RealtimeConversationVersion 定义：**
```rust
// 来自 codex_protocol
pub enum RealtimeConversationVersion {
    V1,
    V2,
}
```

### 2. 服务器通知注册

**文件路径：** `codex-rs/app-server-protocol/src/protocol/common.rs:921-922`

```rust
server_notification_definitions! {
    // ...
    #[experimental("thread/realtime/started")]
    ThreadRealtimeStarted => "thread/realtime/started" (v2::ThreadRealtimeStartedNotification),
    // ...
}
```

**Wire 格式：**
```json
{
  "method": "thread/realtime/started",
  "params": {
    "threadId": "thread-uuid",
    "sessionId": "sess_456",
    "version": "v2"
  }
}
```

### 3. 服务器端发送逻辑

**文件路径：** `codex-rs/app-server/src/bespoke_event_handling.rs`

服务器在成功建立与后端实时服务的 WebSocket 连接后发送：

```rust
// 从测试用例中看到的典型场景
// realtime_conversation.rs:114-119
let started =
    read_notification::<ThreadRealtimeStartedNotification>(&mut mcp, "thread/realtime/started")
        .await?;
assert_eq!(started.thread_id, thread_start.thread.id);
assert!(started.session_id.is_some());
assert_eq!(started.version, RealtimeConversationVersion::V2);
```

**启动流程：**
```
1. 接收 thread/realtime/start 请求
2. 验证线程和功能标志
3. 建立到后端实时服务的 WebSocket 连接
4. 发送 session.update 配置
5. 收到后端 session.updated 确认
6. 发送 ThreadRealtimeStartedNotification 给客户端
```

### 4. TypeScript 类型定义

**文件路径：** `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeStartedNotification.ts`

```typescript
import type { RealtimeConversationVersion } from "../RealtimeConversationVersion";

/**
 * EXPERIMENTAL - emitted when thread realtime startup is accepted.
 */
export type ThreadRealtimeStartedNotification = { 
  threadId: string, 
  sessionId: string | null, 
  version: RealtimeConversationVersion, 
};
```

**RealtimeConversationVersion.ts：**
```typescript
export type RealtimeConversationVersion = "v1" | "v2";
```

## 关键代码路径与文件引用

### 协议定义
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3766-3774 | Notification 结构体 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 921-922 | 通知注册 |

### 服务器实现
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | - | 实时事件处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 6157-6189 | realtime start 处理 |

### Core 协议依赖
| 文件 | 说明 |
|------|------|
| `codex_protocol::protocol::RealtimeConversationVersion` | Core 版本枚举 |

### 生成的 Schema/类型
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadRealtimeStartedNotification.json` | JSON Schema（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeStartedNotification.ts` | TypeScript 类型 |

### 测试
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/realtime_conversation.rs` | 集成测试（114-119 行） |

## 依赖与外部交互

### 1. 上游依赖

```
ThreadRealtimeStartedNotification
  └── OpenAI Realtime API
       ├── WebSocket 连接建立
       ├── session.update 请求
       └── session.updated 响应
```

### 2. 下游消费者

```
ThreadRealtimeStartedNotification
  ├── VSCode Extension
  │    ├── 显示"实时对话已启动"指示器
  │    ├── 启用麦克风按钮
  │    └── 开始音频采集
  ├── TUI Client
  │    └── 切换到实时模式 UI
  └── 其他客户端
       └── 准备音频 I/O
```

### 3. 启动状态机

```
┌─────────────────────────────────────────────────────────────────┐
│                         Client                                  │
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │   Idle      │───▶│  Starting   │───▶│      Active         │ │
│  │ (未连接)     │    │ (等待确认)   │    │ (音频双向传输)       │ │
│  └─────────────┘    └─────────────┘    └─────────────────────┘ │
│         │                  ▲                      │            │
│         │                  │                      │            │
│         │     ThreadRealtimeStartedNotification   │            │
│         │                  │                      │            │
│         │                  │                      ▼            │
│         │                  │              ┌─────────────┐      │
│         │                  │              │   Stopped   │      │
│         │                  │              │  (已关闭)    │      │
│         │                  │              └─────────────┘      │
│         │                  │                      ▲            │
│         └──────────────────┴──────────────────────┘            │
│              thread/realtime/stop 或错误                        │
└─────────────────────────────────────────────────────────────────┘
```

### 4. 相关协议方法

| 方法/通知 | 方向 | 说明 |
|-----------|------|------|
| `thread/realtime/start` | Client → Server | 请求启动实时对话 |
| `thread/realtime/started` | Server → Client | 启动成功通知（本通知） |
| `thread/realtime/appendAudio` | Client → Server | 发送音频输入 |
| `thread/realtime/outputAudio/delta` | Server → Client | 接收音频输出 |
| `thread/realtime/stop` | Client → Server | 停止实时对话 |

## 风险、边界与改进建议

### 1. 已知风险

**风险 1：启动超时**
- **描述**：后端连接可能耗时较长或失败
- **影响**：客户端长时间等待 StartedNotification
- **缓解**：
  - 客户端实现超时机制（建议 10-30 秒）
  - 超时后显示错误并允许重试

**风险 2：版本不匹配**
- **描述**：客户端请求的 version 与服务器实际使用的不同
- **影响**：行为不一致或功能缺失
- **缓解**：客户端应检查返回的 version 字段

**风险 3：实验性 API 的变更**
- **描述**：API 可能在未来版本中添加字段
- **影响**：旧客户端可能忽略新字段
- **缓解**：客户端应忽略未知字段

### 2. 边界情况

| 场景 | 行为 |
|------|------|
| 后端连接失败 | 发送 ErrorNotification，不发送 StartedNotification |
| 重复启动 | 返回错误，已有活跃会话 |
| session_id 为 null | 正常情况，某些配置下后端不提供 |
| 未知 version | 服务器选择默认版本，客户端应能处理 |

### 3. 改进建议

**建议 1：添加启动耗时**
```rust
pub struct ThreadRealtimeStartedNotification {
    pub thread_id: String,
    pub session_id: Option<String>,
    pub version: RealtimeConversationVersion,
    pub startup_ms: u64, // 新增：启动耗时（毫秒）
}
```

**建议 2：添加服务器信息**
```rust
pub struct ThreadRealtimeStartedNotification {
    pub thread_id: String,
    pub session_id: Option<String>,
    pub version: RealtimeConversationVersion,
    pub server_info: Option<RealtimeServerInfo>, // 新增
}

pub struct RealtimeServerInfo {
    pub region: String,      // 服务器区域
    pub protocol_version: String, // 协议版本
}
```

**建议 3：添加功能协商**
```rust
pub struct ThreadRealtimeStartedNotification {
    pub thread_id: String,
    pub session_id: Option<String>,
    pub version: RealtimeConversationVersion,
    pub capabilities: RealtimeCapabilities, // 新增：支持的功能
}

pub struct RealtimeCapabilities {
    pub max_input_channels: u16,
    pub supported_encodings: Vec<AudioEncoding>,
    pub supports_interruption: bool,
}
```

**建议 4：添加配置确认**
```rust
pub struct ThreadRealtimeStartedNotification {
    pub thread_id: String,
    pub session_id: Option<String>,
    pub version: RealtimeConversationVersion,
    pub effective_config: RealtimeConfig, // 新增：实际生效的配置
}

pub struct RealtimeConfig {
    pub instructions: String,  // 实际使用的 prompt
    pub voice: String,         // 语音设置
    pub turn_detection: TurnDetectionConfig,
}
```

### 4. 测试缺口

| 缺口 | 优先级 | 说明 |
|------|--------|------|
| 启动超时场景 | 高 | 验证超时处理 |
| 后端连接失败 | 高 | 验证错误通知 |
| 版本协商 | 中 | 验证版本选择逻辑 |
| 重复启动 | 中 | 验证错误处理 |
| 性能基准 | 低 | 测量启动耗时分布 |
