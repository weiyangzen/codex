# ThreadReadParams.json 研究文档

## 场景与职责

`ThreadReadParams` 是 Codex App-Server Protocol v2 API 中 `thread/read` 方法的请求参数结构，用于指定读取线程信息时的查询选项。

**核心场景：**
1. **线程概览获取** - 获取线程的基本元数据（名称、状态、预览等），不包含完整对话历史
2. **完整历史加载** - 当 `includeTurns=true` 时，加载线程的完整回合（Turn）和项目（Item）历史
3. **状态验证** - 在操作前后读取线程状态，验证变更是否生效
4. **离线线程浏览** - 读取已归档或未加载到内存的线程信息

**典型使用流程：**
```rust
// 基本读取（仅元数据）
ThreadReadParams {
    thread_id: "thread-uuid".to_string(),
    include_turns: false, // 默认
}

// 完整读取（含历史）
ThreadReadParams {
    thread_id: "thread-uuid".to_string(),
    include_turns: true,
}
```

## 功能点目的

### 1. 参数结构设计

```json
{
  "threadId": "thread-uuid-string",
  "includeTurns": false
}
```

**设计意图：**
- **精确控制数据量**：通过 `includeTurns` 开关控制是否加载完整历史，避免不必要的数据传输
- **向后兼容**：`includeTurns` 默认为 `false`，确保现有客户端行为不变
- **简单明确**：仅两个参数，降低 API 使用复杂度

### 2. 与 ThreadReadResponse 的关系

```rust
// 请求
pub struct ThreadReadParams {
    pub thread_id: String,
    #[serde(default)]
    pub include_turns: bool,
}

// 响应
pub struct ThreadReadResponse {
    pub thread: Thread, // 根据 includeTurns 决定是否填充 turns 字段
}
```

**Thread.turns 的填充规则：**
| includeTurns | turns 字段 |
|--------------|-----------|
| `false` | 空数组 `[]` |
| `true` | 从 rollout 文件加载的完整 Turn 列表 |

### 3. 性能考量

**默认行为（includeTurns=false）：**
- 仅从 SQLite/内存读取线程元数据
- 不访问 rollout 文件
- 响应时间 < 10ms

**完整加载（includeTurns=true）：**
- 需要解析 rollout JSONL 文件
- 可能涉及磁盘 I/O
- 响应时间取决于历史大小（可能 100ms+）

## 具体技术实现

### 1. Rust 源码定义

**文件路径：** `codex-rs/app-server-protocol/src/protocol/v2.rs:3048-3053`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadReadParams {
    pub thread_id: String,
    /// When true, include turns and their items from rollout history.
    #[serde(default)]
    pub include_turns: bool,
}
```

**关键属性：**
- `#[serde(default)]` - 反序列化时，缺失字段默认为 `false`
- 使用 `bool` 而非 `Option<bool>` - 明确的两态选择，无第三种语义

### 2. 服务器端处理流程

**文件路径：** `codex-rs/app-server/src/codex_message_processor.rs:3175-3200`

```rust
async fn thread_read(&mut self, request_id: ConnectionRequestId, params: ThreadReadParams) {
    let ThreadReadParams { thread_id, include_turns } = params;
    
    // 1. 解析 thread_id
    let thread_uuid = match ThreadId::from_string(&thread_id) {
        Ok(uuid) => uuid,
        Err(e) => { /* 返回错误 */ return; }
    };
    
    // 2. 获取线程句柄
    let thread = match self.get_thread(&thread_uuid).await {
        Some(t) => t,
        None => { /* 尝试从磁盘加载 */ }
    };
    
    // 3. 构建 Thread 对象
    let thread = self.build_thread_response(&thread, include_turns).await;
    
    // 4. 发送响应
    self.outgoing
        .send_response(request_id, ThreadReadResponse { thread })
        .await;
}
```

### 3. 请求注册

**文件路径：** `codex-rs/app-server-protocol/src/protocol/common.rs:291-294`

```rust
client_request_definitions! {
    // ...
    ThreadRead => "thread/read" {
        params: v2::ThreadReadParams,
        response: v2::ThreadReadResponse,
    },
    // ...
}
```

### 4. TypeScript 类型定义

**文件路径：** `codex-rs/app-server-protocol/schema/typescript/v2/ThreadReadParams.ts`

```typescript
export type ThreadReadParams = { 
  threadId: string, 
  /**
   * When true, include turns and their items from rollout history.
   */
  includeTurns: boolean, 
};
```

## 关键代码路径与文件引用

### 协议定义
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3048-3053 | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3055-3060 | ThreadReadResponse 定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 291-294 | 请求注册 |

### 服务器实现
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs` | 3175-3200+ | thread_read 处理方法 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 134-135 | 类型导入 |

### 生成的 Schema/类型
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadReadParams.json` | JSON Schema（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadReadParams.ts` | TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/ClientRequest.json` | 合并的请求 Schema |

### 测试
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_read.rs` | 核心集成测试 |
| `codex-rs/app-server/tests/suite/v2/thread_resume.rs` | 恢复后读取测试 |
| `codex-rs/app-server/tests/suite/v2/thread_unsubscribe.rs` | 取消订阅后读取测试 |

## 依赖与外部交互

### 1. 上游依赖（被调用方）

```
thread/read RPC
  └── ThreadReadParams
       ├── thread_id: String
       └── include_turns: bool
            └── 决定是否加载 Turn/Item 历史
                 └── 依赖 rollout 文件解析
```

### 2. 下游依赖（调用方）

```
ThreadReadParams
  └── thread/read
       ├── VSCode Extension
       ├── TUI Client
       ├── CLI Client
       └── 测试框架
```

### 3. 数据流

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Client        │────▶│  App Server      │────▶│   Storage       │
│                 │     │                  │     │                 │
│ thread/read     │     │ thread_read()    │     │ SQLite (元数据)  │
│   request       │     │                  │     │ Rollout (历史)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌──────────────────┐
                        │ includeTurns?    │
                        │ ──────────────── │
                        │ true: 加载 rollout│
                        │ false: 仅元数据   │
                        └──────────────────┘
                               │
                               ▼
┌─────────────────┐     ┌──────────────────┐
│   Client        │◀────│ ThreadReadResponse│
│                 │     │ { thread: Thread }│
└─────────────────┘     └──────────────────┘
```

### 4. 相关协议方法

| 方法 | 方向 | 说明 |
|------|------|------|
| `thread/read` | Client → Server | 读取线程信息（本方法） |
| `thread/resume` | Client → Server | 恢复线程（也返回 Thread） |
| `thread/list` | Client → Server | 列出线程（摘要信息） |
| `thread/fork` | Client → Server | 分叉线程（返回新 Thread） |

## 风险、边界与改进建议

### 1. 已知风险

**风险 1：includeTurns=true 时的大负载**
- **描述**：长线程的历史可能非常大（MB 级 JSON）
- **影响**：内存压力、网络延迟、客户端解析开销
- **缓解**：
  - 当前：客户端按需请求
  - 建议：实现分页/游标机制

**风险 2：未物化线程的读取限制**
- **描述**：新创建但未保存的线程（无 rollout 文件）不支持 `includeTurns=true`
- **影响**：返回错误 `"includeTurns is unavailable before first user message"`
- **缓解**：客户端应在首次用户消息后再请求完整历史

**风险 3：并发读取与写入**
- **描述**：读取时线程状态可能正在变化
- **影响**：获取到的是时间点快照，可能立即过时
- **缓解**：当前无事务隔离保证，依赖最终一致性

### 2. 边界情况

| 场景 | 行为 |
|------|------|
| 不存在的 thread_id | 返回标准错误响应 |
| 归档线程 | 支持读取，从归档目录加载 |
| 已加载线程 | 从内存获取最新状态 |
| includeTurns=true + 未物化 | 返回错误（见上文） |
| 空线程（无消息） | `turns: []` |

### 3. 改进建议

**建议 1：分页支持**
```rust
pub struct ThreadReadParams {
    pub thread_id: String,
    #[serde(default)]
    pub include_turns: bool,
    // 新增分页参数
    pub turn_cursor: Option<String>,
    pub turn_limit: Option<u32>,
}
```
- 解决大线程加载问题
- 支持渐进式历史加载

**建议 2：字段选择**
```rust
pub struct ThreadReadParams {
    pub thread_id: String,
    pub include_turns: bool,
    // 新增字段过滤
    pub include_fields: Option<Vec<String>>, // 白名单
    pub exclude_fields: Option<Vec<String>>, // 黑名单
}
```
- 减少不必要的数据传输
- 支持特定用例优化

**建议 3：条件读取（ETag）**
```rust
pub struct ThreadReadParams {
    pub thread_id: String,
    pub include_turns: bool,
    pub if_none_match: Option<String>, // 客户端缓存的 ETag
}

pub struct ThreadReadResponse {
    pub thread: Thread,
    pub etag: String, // 服务器生成的版本标识
}
```
- 支持 304 Not Modified 响应
- 减少重复数据传输

**建议 4：读取统计**
```rust
pub struct ThreadReadResponse {
    pub thread: Thread,
    pub stats: Option<ReadStats>, // 新增：读取耗时、数据大小等
}
```
- 帮助客户端优化性能
- 支持调试和监控

### 4. 测试缺口

| 缺口 | 优先级 | 说明 |
|------|--------|------|
| 大线程性能测试 | 高 | 验证大历史的加载性能 |
| 并发读取测试 | 中 | 验证多客户端同时读取 |
| 缓存一致性测试 | 中 | 验证读取与更新的顺序 |
| 网络中断恢复 | 低 | 大响应传输中断的处理 |
