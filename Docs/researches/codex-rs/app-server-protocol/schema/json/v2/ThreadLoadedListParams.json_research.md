# ThreadLoadedListParams.json 研究文档

## 场景与职责

`ThreadLoadedListParams.json` 是 Codex App Server Protocol v2 API 的 JSON Schema 定义文件，定义了 `thread/loaded/list` 方法的请求参数结构。该参数用于查询当前已加载到内存中的线程（活跃会话）列表，与 `thread/list` 不同，它只返回已加载线程的 ID 列表。

**主要使用场景：**
- 获取当前活跃的会话列表
- 监控哪些线程正在运行
- 客户端连接后同步已加载的线程状态
- 与 `thread/list` 配合，区分已加载和未加载的会话

## 功能点目的

### 1. 分页参数

| 字段 | 类型 | 说明 |
|------|------|------|
| `cursor` | string? | 分页游标，用于获取下一页结果 |
| `limit` | integer? | 每页大小，默认无限制 |

### 2. 与 ThreadListParams 的区别

| 特性 | ThreadLoadedListParams | ThreadListParams |
|------|------------------------|------------------|
| 查询范围 | 仅内存中的线程 | 所有持久化线程 |
| 返回数据 | 仅线程 ID | 完整线程元数据 |
| 过滤选项 | 无 | 丰富的过滤选项 |
| 排序 | 按 ID 字母排序 | 按时间排序 |
| 使用场景 | 活跃线程监控 | 历史会话浏览 |

## 具体技术实现

### 关键流程

1. **请求处理流程** (`codex_message_processor.rs:3116-3170`):
```rust
async fn thread_loaded_list(
    &self,
    request_id: ConnectionRequestId,
    params: ThreadLoadedListParams,
) {
    let ThreadLoadedListParams { cursor, limit } = params;
    
    // 1. 从 ThreadManager 获取所有已加载线程 ID
    let mut data = self.thread_manager.list_thread_ids()
        .await
        .into_iter()
        .map(|thread_id| thread_id.to_string())
        .collect::<Vec<_>>();
    
    // 2. 排序（字母顺序）
    data.sort();
    
    // 3. 分页处理
    let total = data.len();
    let start = match cursor {
        Some(cursor) => {
            // 查找游标位置
            let cursor_id = ThreadId::from_string(&cursor)?;
            data.iter().position(|id| id == &cursor_id.to_string())
                .map(|pos| pos + 1)
                .unwrap_or(total)
        }
        None => 0,
    };
    
    let limit = limit.map(|l| l as usize).unwrap_or(total);
    let end = (start + limit).min(total);
    let page_data = data[start..end].to_vec();
    
    // 4. 构造响应
    let next_cursor = if end < total {
        Some(page_data.last().unwrap().clone())
    } else {
        None
    };
    
    let response = ThreadLoadedListResponse {
        data: page_data,
        next_cursor,
    };
}
```

2. **数据来源**:
   - 直接从 `ThreadManager` 获取
   - 反映内存中的实时状态
   - 不包含已卸载或从未加载的线程

### 数据结构

**Rust 结构定义** (`app-server-protocol/src/protocol/v2.rs:2999-3009`):
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadLoadedListParams {
    /// Opaque pagination cursor returned by a previous call.
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    /// Optional page size; defaults to no limit.
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
}
```

### 分页逻辑

- **游标**: 使用线程 ID 作为游标
- **排序**: 按 ID 字符串字母顺序排序
- **默认限制**: 无限制（返回所有已加载线程）
- **下一页**: 返回当前页最后一个 ID 作为 nextCursor

## 关键代码路径与文件引用

### 核心实现

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:2999-3009` | ThreadLoadedListParams 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:287-290` | ClientRequest 枚举中注册 thread/loaded/list 方法 |
| `codex-rs/app-server/src/codex_message_processor.rs:3116-3170` | thread_loaded_list 方法实现 |

### 测试代码

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_loaded_list.rs` | 完整的功能测试套件 |
| `codex-rs/app-server/tests/suite/v2/thread_loaded_list.rs:18-46` | 基础列表测试 |
| `codex-rs/app-server/tests/suite/v2/thread_loaded_list.rs:48-100` | 分页测试 |

### 生成的 Schema 和类型

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadLoadedListParams.json` | JSON Schema 定义（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadLoadedListParams.ts` | TypeScript 类型定义 |

## 依赖与外部交互

### 上游依赖

1. **ThreadManager** (`codex_core::ThreadManager`):
   - `list_thread_ids()` 方法返回已加载线程 ID 列表
   - 内存中的实时状态

2. **ThreadId** (`codex_protocol::ThreadId`):
   - 线程标识符类型
   - 字符串与类型之间的转换

### 下游消费

1. **VSCode 扩展**: 活跃会话列表
2. **TUI 客户端**: 状态监控
3. **CLI 客户端**: 会话管理

### 相关响应

- `ThreadLoadedListResponse` - 包含 `data`（ID 数组）和 `nextCursor`

## 风险、边界与改进建议

### 已知风险

1. **瞬时状态**:
   - 线程列表可能随时变化（加载/卸载）
   - 分页过程中数据可能不一致

2. **游标失效**:
   - 如果游标指向的线程被卸载，可能跳过某些线程
   - 建议使用无状态游标设计

### 边界情况

1. **空列表**:
   - 如果没有已加载线程，返回空数组
   - `nextCursor` 为 `null`

2. **无效游标**:
   - 如果游标无效，从列表开头返回
   - 不会返回错误

3. **线程卸载**:
   - 查询过程中线程可能被卸载
   - 结果可能包含已卸载线程 ID（短暂不一致）

### 改进建议

1. **快照机制**:
   - 使用快照保证分页一致性
   - 避免查询过程中数据变化

2. **时间戳过滤**:
   - 添加 `since` 参数，只返回某时间后加载的线程
   - 支持增量同步

3. **状态过滤**:
   - 添加 `status` 过滤（如只返回 active 线程）
   - 更精确的状态查询

4. **批量详情**:
   - 提供选项返回线程基本信息（不只是 ID）
   - 减少后续查询次数

5. **WebSocket 推送**:
   - 推送线程加载/卸载事件
   - 实时同步客户端状态
