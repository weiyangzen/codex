# state.rs 深度研究文档

## 场景与职责

`state.rs` 是 debug-client 的状态定义模块，负责定义跨线程共享的状态结构。它是整个应用程序的"单一事实来源"，协调主线程和 reader 线程之间的状态同步。

**核心定位**：
- 共享状态的数据定义（`State` 结构体）
- 请求跟踪枚举（`PendingRequest`）
- 线程间事件通信（`ReaderEvent`）

**设计哲学**：
- 最小化共享状态，仅包含必要信息
- 使用标准库类型，无外部依赖
- 简单、可克隆的事件类型

## 功能点目的

### 1. State 结构体

```rust
#[derive(Debug, Default)]
pub struct State {
    pub pending: HashMap<RequestId, PendingRequest>,  // 待处理请求
    pub thread_id: Option<String>,                     // 当前活动线程
    pub known_threads: Vec<String>,                    // 已知线程列表
}
```

**字段说明**：

| 字段 | 类型 | 用途 | 访问模式 |
|------|------|------|----------|
| `pending` | `HashMap<RequestId, PendingRequest>` | 跟踪已发送但未收到响应的请求 | reader 写，main 读 |
| `thread_id` | `Option<String>` | 当前活动线程 ID | 双向读写 |
| `known_threads` | `Vec<String>` | 用户交互过的线程列表 | 双向读写 |

**设计决策**：
- 使用 `HashMap` 存储 pending 请求，O(1) 查找
- `known_threads` 使用 `Vec` 保持顺序，但查找为 O(n)
- 所有字段 `pub`，简化访问（由外部 `Mutex` 保护）

### 2. PendingRequest 枚举

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PendingRequest {
    Start,   // thread/start 请求
    Resume,  // thread/resume 请求
    List,    // thread/list 请求
}
```

**用途**：
- 标识 pending 请求的类型，用于正确解析响应
- 在 `client.rs` 中创建，在 `reader.rs` 中消费

**为什么是 `Copy`**：
- 无堆分配，复制成本低
- 从 `HashMap` 移除时无需克隆

### 3. ReaderEvent 枚举

```rust
#[derive(Debug, Clone)]
pub enum ReaderEvent {
    ThreadReady {
        thread_id: String,
    },
    ThreadList {
        thread_ids: Vec<String>,
        next_cursor: Option<String>,
    },
}
```

**事件类型**：

| 变体 | 触发条件 | 携带数据 |
|------|----------|----------|
| `ThreadReady` | thread/start 或 thread/resume 响应 | 新线程 ID |
| `ThreadList` | thread/list 响应 | 线程 ID 列表 + 分页游标 |

**设计决策**：
- 使用 `Clone` 而非 `Copy`，因为包含 `String`/`Vec`
- 事件是"一次性"的，消费后从通道移除
- 通道容量无界（标准 `mpsc`），理论上可能内存增长

## 具体技术实现

### 数据结构关系

```
State (在 Arc<Mutex<>> 中)
    ├─ pending: HashMap<RequestId, PendingRequest>
    │               ↓
    │           PendingRequest
    │               ├─ Start
    │               ├─ Resume
    │               └─ List
    │
    ├─ thread_id: Option<String>
    └─ known_threads: Vec<String>

ReaderEvent (通过 mpsc::channel 发送)
    ├─ ThreadReady { thread_id: String }
    └─ ThreadList { thread_ids: Vec<String>, next_cursor: Option<String> }
```

### 状态流转

**线程创建流程**：
```
main 线程:
    client.request_thread_start(params)
        ↓
    state.pending.insert(request_id, PendingRequest::Start)
        ↓
    发送 JSON-RPC 请求

reader 线程:
    接收响应
        ↓
    state.pending.remove(&response.id) → Some(PendingRequest::Start)
        ↓
    解析 ThreadStartResponse
        ↓
    state.thread_id = Some(thread_id.clone())
    state.known_threads.push(thread_id.clone())
        ↓
    events.send(ReaderEvent::ThreadReady { thread_id })

main 线程:
    drain_events()
        ↓
    接收 ReaderEvent::ThreadReady
        ↓
    output.set_prompt(&thread_id)
```

**线程切换流程**（`:use` 命令）：
```
main 线程:
    handle_command(UserCommand::Use(thread_id))
        ↓
    client.use_thread(thread_id)
        ↓
    state.thread_id = Some(thread_id)  // 仅本地更新
    // 注意：known_threads 可能不包含此 ID
```

### 并发访问模式

| 状态字段 | 主线程 | reader 线程 | 同步机制 |
|----------|--------|-------------|----------|
| `pending` | 插入 | 移除 | `Mutex` |
| `thread_id` | 读取、更新 | 更新 | `Mutex` |
| `known_threads` | 读取 | 追加 | `Mutex` |

**锁使用模式**：
```rust
// 主线程
let state = state.lock().expect("state lock poisoned");
let thread_id = state.thread_id.clone();  // 读取

// reader 线程
let mut state = state.lock().expect("state lock poisoned");
state.thread_id = Some(new_id);  // 写入
state.known_threads.push(new_id);
```

## 关键代码路径与文件引用

### 内部依赖

无内部依赖，是基础定义模块。

### 外部依赖

| Crate | 类型 | 用途 |
|-------|------|------|
| `std::collections::HashMap` | 标准库 | pending 请求存储 |
| `codex-app-server-protocol::RequestId` | 外部 | pending 的 key 类型 |

### 调用关系

**State 被使用位置**：

| 文件 | 使用方式 | 场景 |
|------|----------|------|
| `client.rs:48` | `Arc<Mutex<State>>` | 存储在 `AppServerClient` 中 |
| `client.rs:255-265` | `state.lock()` | `track_pending`, `remember_thread_locked` |
| `reader.rs:37` | `Arc<Mutex<State>>` | 参数传递 |
| `reader.rs:149-202` | `state.lock()` | `handle_response` 中更新状态 |

**PendingRequest 被使用位置**：

| 文件 | 使用方式 | 场景 |
|------|----------|------|
| `client.rs:39` | 导入 | 请求跟踪 |
| `client.rs:151,162,173` | `track_pending()` | 记录 pending 请求 |
| `reader.rs:30` | 导入 | 响应处理 |
| `reader.rs:158,172,185` | `match pending` | 根据类型处理响应 |

**ReaderEvent 被使用位置**：

| 文件 | 使用方式 | 场景 |
|------|----------|------|
| `client.rs:40` | 导入 | 事件通道 |
| `main.rs:24` | 导入 | 事件处理 |
| `main.rs:101` | `mpsc::channel()` | 创建通道 |
| `main.rs:251-282` | `drain_events()` | 处理事件 |
| `reader.rs:31` | 导入 | 发送事件 |
| `reader.rs:170,183,197` | `events.send()` | 发送事件 |

## 依赖与外部交互

### RequestId 类型

来自 `codex-app-server-protocol`：
```rust
pub enum RequestId {
    String(String),
    Integer(i64),
}
```

**特点**：
- 支持字符串和整数两种格式
- 实现 `Eq + Hash`，可用作 `HashMap` 的 key
- debug-client 使用整数 ID（自增）

### 标准库依赖

| 类型 | 用途 |
|------|------|
| `std::collections::HashMap` | pending 请求存储 |
| `std::sync::Arc` | 跨线程共享 |
| `std::sync::Mutex` | 互斥访问 |
| `std::sync::mpsc` | 事件通道 |

## 风险、边界与改进建议

### 当前风险

**1. known_threads 性能**
```rust
pub known_threads: Vec<String>,
```
- 查找为 O(n)，线程数量大时效率低
- 可能包含重复项（虽然有检查，但非原子）

**2. 无持久化**
- 程序退出后 `known_threads` 丢失
- 用户需要重新 `:resume` 之前的线程

**3. 通道无界**
```rust
let (event_tx, event_rx) = mpsc::channel();  // 无界通道
```
- 如果主线程阻塞，事件队列可能无限增长
- 可能导致内存不足

**4. 锁粒度**
- 整个 `State` 在一个 `Mutex` 中
- 高并发时可能成为瓶颈（虽然 debug-client 并发低）

### 边界情况

**1. 线程 ID 不一致**
```rust
// reader 线程更新 thread_id
state.thread_id = Some(thread_id.clone());

// 主线程可能同时通过 :use 切换
client.use_thread(other_id);  // 覆盖 reader 的设置
```
- 无冲突检测机制，最后写入者获胜

**2. 重复事件**
- 如果服务器发送重复响应（异常情况下）
- `ReaderEvent` 会重复发送，主线程可能重复处理

**3. 内存增长**
```rust
known_threads: Vec<String>,
```
- 长期使用可能积累大量线程 ID
- 无清理机制

### 改进建议

**1. 使用 HashSet 优化 known_threads**
```rust
pub struct State {
    // ...
    pub known_threads: HashSet<String>,  // O(1) 查找
    pub thread_order: Vec<String>,       // 保持显示顺序
}
```

**2. 添加持久化**
```rust
impl State {
    pub fn save(&self, path: &Path) -> Result<()> {
        let serialized = serde_json::to_string(&self.known_threads)?;
        fs::write(path, serialized)?;
        Ok(())
    }
    
    pub fn load(path: &Path) -> Result<Self> {
        // ...
    }
}
```

**3. 有界通道**
```rust
use std::sync::mpsc::sync_channel;

// 限制队列大小，背压处理
let (event_tx, event_rx) = sync_channel(100);
```

**4. 细粒度锁**
```rust
pub struct State {
    pub pending: Mutex<HashMap<RequestId, PendingRequest>>,
    pub thread_id: RwLock<Option<String>>,  // 读多写少
    pub known_threads: RwLock<Vec<String>>,
}
```

**5. 添加更多事件类型**
```rust
pub enum ReaderEvent {
    ThreadReady { thread_id: String },
    ThreadList { thread_ids: Vec<String>, next_cursor: Option<String> },
    // 建议添加：
    Error { message: String },           // 错误通知
    ConnectionLost,                       // 连接断开
    TurnCompleted { turn_id: String },    // 轮次完成
}
```

**6. 状态快照**
```rust
#[derive(Clone)]
pub struct StateSnapshot {
    pub thread_id: Option<String>,
    pub known_threads: Vec<String>,
    pub pending_count: usize,
}

impl State {
    pub fn snapshot(&self) -> StateSnapshot {
        let state = self.lock().expect("...");
        StateSnapshot {
            thread_id: state.thread_id.clone(),
            known_threads: state.known_threads.clone(),
            pending_count: state.pending.len(),
        }
    }
}
```

### 代码质量

**优点**：
- 极简设计，职责清晰
- 无外部依赖（除协议 crate）
- 类型安全，避免字符串魔术值

**可改进点**：
- `known_threads` 使用 `Vec` 而非 `HashSet`
- 无文档注释（虽然结构简单）
- 无默认值常量

### 与 AGENTS.md 规范符合度

检查项目规范：
- ✅ 模块极小（28 行）
- ✅ 简单数据结构
- ✅ 使用标准库类型

无违规项。

### 扩展性考虑

**未来可能添加的状态**：
- `current_turn_id: Option<String>` - 跟踪当前轮次
- `pending_approvals: Vec<ApprovalRequest>` - 待处理审批队列
- `connection_state: ConnectionState` - 连接状态（Connected, Reconnecting, Disconnected）
- `last_activity: Instant` - 最后活动时间（用于超时检测）

**保持简单的理由**：
- debug-client 定位为简单调试工具
- 复杂状态管理应由 TUI 或正式客户端处理
- 当前状态已满足基本需求
