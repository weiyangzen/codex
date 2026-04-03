# ThreadLoadedListResponse 类型研究文档

## 场景与职责

`ThreadLoadedListResponse` 是 Codex App Server Protocol v2 API 中 `thread/loaded/list` RPC 方法的响应类型。它返回当前已加载到服务器内存中的线程 ID 列表，是一个轻量级的内存状态查询接口。

### 主要使用场景

- **活跃会话发现**: 客户端快速获取当前内存中活跃的会话
- **会话状态同步**: 客户端重连后同步活跃会话状态
- **资源管理**: 监控服务器内存中的会话数量
- **调试诊断**: 排查哪些会话当前在内存中

### 架构定位

该类型与 `ThreadLoadedListParams` 形成轻量级查询契约，与 `ThreadListResponse` 相比：
- 数据来源：内存 vs 磁盘
- 返回内容：仅 ID 字符串 vs 完整 Thread 对象
- 查询速度：极快 vs 较慢

---

## 功能点目的

### 核心字段

| 字段 | 类型 | 目的 |
|------|------|------|
| `data` | `string[]` | 当前加载在内存中的线程 ID 数组 |
| `nextCursor` | `string \| null` | 下一页游标，`null` 表示无更多数据 |

### 设计意图

1. **极简设计**: 仅返回线程 ID，最小化响应体积
2. **快速查询**: 内存查询，无需序列化完整 Thread 对象
3. **分页支持**: 虽然内存中线程通常较少，仍支持分页以处理边界情况
4. **一致性**: 与 `ThreadListResponse` 保持相同的响应结构模式

---

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadLoadedListResponse = {
  data: Array<string>,
  nextCursor: string | null,
};
```

### Rust 实现细节

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadLoadedListResponse {
    /// Thread ids for sessions currently loaded in memory.
    pub data: Vec<String>,
    /// Opaque cursor to pass to the next call to continue after the last item.
    /// if None, there are no more items to return.
    pub next_cursor: Option<String>,
}
```

### 关键技术点

1. **ID 类型**: 使用 `String` 而非 `ThreadId` 内部类型，简化序列化
2. **游标复用**: 在简单场景下，游标可能直接是最后一个线程 ID
3. **空数组**: 无加载线程时返回空数组而非错误

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 作用 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3011-3021) | Rust 类型定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` (line 287-290) | RPC 方法注册 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadLoadedListResponse.ts` | TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/ThreadLoadedListResponse.json` | JSON Schema |

### 服务端实现

| 文件 | 作用 |
|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs` | 构造 ThreadLoadedListResponse |
| `codex-rs/app-server/src/thread_state.rs` | 提供加载线程列表 |

### 测试覆盖

| 文件 | 作用 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_loaded_list.rs` | 功能测试 |

### 关键测试断言

```rust
// 基本功能
let ThreadLoadedListResponse { mut data, next_cursor } = to_response::<ThreadLoadedListResponse>(resp)?;
data.sort();
assert_eq!(data, vec![thread_id]);
assert_eq!(next_cursor, None);

// 分页
let resp1 = ...;
assert_eq!(first_page, vec![expected[0].clone()]);
assert_eq!(next_cursor, Some(expected[0].clone()));

let resp2 = ...;
assert_eq!(second_page, vec![expected[1].clone()]);
assert_eq!(next_cursor, None);
```

---

## 依赖与外部交互

### 数据流

```
ThreadLoadedListParams (可选)
    ↓
查询内存线程状态映射
    ↓
提取所有线程 ID
    ↓
应用分页（如有 limit）
    ↓
ThreadLoadedListResponse { data: Vec<String>, next_cursor }
```

### 内存状态来源

服务器内部维护的数据结构：

```rust
// 伪代码表示
struct AppServer {
    threads: HashMap<ThreadId, ThreadState>,  // 加载的线程
    // ...
}
```

`thread/loaded/list` 直接读取 `threads.keys()` 并返回。

---

## 风险、边界与改进建议

### 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **瞬时性** | 内存状态随时变化，列表仅代表查询瞬间 | 客户端应快速使用结果，或轮询更新 |
| **信息有限** | 仅返回 ID，需额外查询获取线程详情 | 如需完整信息，使用 `thread/read` 或 `thread/list` |
| **服务器重启** | 重启后列表为空 | 客户端应持久化重要会话 ID |

### 边界情况

1. **空列表**: `data: [], nextCursor: null`（无加载线程或服务器刚启动）
2. **单线程**: `data: ["uuid"], nextCursor: null`
3. **大量线程**: 虽然罕见，分页机制确保可处理

### 改进建议

1. **添加状态信息**: 返回 `(id, status)` 元组数组，避免额外查询
2. **最后活动时间**: 包含每个线程的最后活动时间戳
3. **WebSocket 推送**: 提供加载/卸载事件的实时推送，替代轮询
4. **批量查询详情**: 添加 `thread/loaded/details` 接口，返回完整 Thread 对象
5. **内存统计**: 返回总内存占用估算

### 与 ThreadListResponse 对比

| 特性 | ThreadLoadedListResponse | ThreadListResponse |
|------|-------------------------|-------------------|
| 数据来源 | 内存 | 磁盘 |
| 返回类型 | `string[]`（ID 列表） | `Thread[]`（完整对象） |
| 典型延迟 | < 1ms | 10-100ms+ |
| 数据持久性 | 临时（进程生命周期） | 持久化 |
| 适用场景 | 活跃会话监控 | 历史浏览 |
| 过滤能力 | 无 | 丰富 |

### 使用模式建议

```typescript
// 模式 1: 快速检查活跃会话
const loaded = await client.threadLoadedList({});
if (loaded.data.includes(targetId)) {
  // 会话在内存中，可以直接交互
}

// 模式 2: 结合 thread/list 获取完整信息
const [loaded, all] = await Promise.all([
  client.threadLoadedList({}),
  client.threadList({ limit: 100 })
]);

const activeThreads = all.data.filter(t => loaded.data.includes(t.id));
```
