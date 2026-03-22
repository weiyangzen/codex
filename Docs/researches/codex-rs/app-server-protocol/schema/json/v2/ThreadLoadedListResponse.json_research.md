# ThreadLoadedListResponse.json 研究文档

## 场景与职责

`ThreadLoadedListResponse.json` 是 Codex App Server Protocol v2 API 的 JSON Schema 定义文件，定义了 `thread/loaded/list` 方法的响应结构。该响应返回当前已加载到内存中的线程 ID 列表，用于客户端监控活跃会话。

**主要使用场景：**
- 获取当前内存中活跃的线程 ID 列表
- 与 `thread/list` 配合，区分已加载和未加载的会话
- 客户端连接后同步已加载的线程状态
- 批量操作活跃线程前的查询

## 功能点目的

### 1. 响应结构 (ThreadLoadedListResponse)

| 字段 | 类型 | 说明 |
|------|------|------|
| `data` | string[] | 已加载线程的 ID 数组（必需） |
| `nextCursor` | string? | 下一页游标，null 表示无更多数据 |

### 2. 与 ThreadListResponse 的区别

| 特性 | ThreadLoadedListResponse | ThreadListResponse |
|------|--------------------------|-------------------|
| 返回数据 | 仅线程 ID 字符串数组 | 完整 Thread 对象数组 |
| 数据来源 | 内存中的 ThreadManager | 文件系统 + SQLite |
| 数据量 | 轻量（仅 ID） | 较重（完整元数据） |
| 实时性 | 实时（内存状态） | 可能略有延迟 |
| 使用场景 | 活跃线程监控 | 历史会话浏览 |

### 3. 分页机制

- 使用游标（cursor）而非偏移量分页
- 游标值为线程 ID 字符串
- 返回的 `nextCursor` 是当前页最后一个线程 ID
- 最后一页返回 `nextCursor: null`

## 具体技术实现

### 关键流程

1. **响应构造流程** (`codex_message_processor.rs:3116-3170`):
```rust
async fn thread_loaded_list(
    &self,
    request_id: ConnectionRequestId,
    params: ThreadLoadedListParams,
) {
    let ThreadLoadedListParams { cursor, limit } = params;
    
    // 1. 获取所有已加载线程 ID
    let mut data = self
        .thread_manager
        .list_thread_ids()
        .await
        .into_iter()
        .map(|thread_id| thread_id.to_string())
        .collect::<Vec<_>>();
    
    // 2. 按字母顺序排序
    data.sort();
    
    // 3. 应用分页
    let total = data.len();
    let start = match cursor {
        Some(cursor) => {
            let cursor = match ThreadId::from_string(&cursor) {
                Ok(id) => id.to_string(),
                Err(_) => {
                    // 无效游标，返回错误
                    let error = JSONRPCErrorError {
                        code: INVALID_REQUEST_ERROR_CODE,
                        message: format!("invalid cursor: {cursor}"),
                        data: None,
                    };
                    self.outgoing.send_error(request_id, error).await;
                    return;
                }
            };
            // 查找游标位置，从下一个开始
            data.iter()
                .position(|id| id == &cursor)
                .map(|pos| pos + 1)
                .unwrap_or(total)
        }
        None => 0,
    };
    
    let limit = limit.map(|l| l as usize).unwrap_or(total);
    let end = (start + limit).min(total);
    let page_data = data[start..end].to_vec();
    
    // 4. 确定下一页游标
    let next_cursor = if end < total {
        Some(page_data.last().unwrap().clone())
    } else {
        None
    };
    
    // 5. 构造响应
    let response = ThreadLoadedListResponse {
        data: page_data,
        next_cursor,
    };
    self.outgoing.send_response(request_id, response).await;
}
```

2. **数据来源**:
   - `ThreadManager::list_thread_ids()` - 返回内存中所有线程的 UUID
   - 实时反映当前加载状态

### 数据结构

**Rust 结构定义** (`app-server-protocol/src/protocol/v2.rs:3011-3020`):
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

### 分页算法

```
输入: cursor (可选), limit (可选)
1. 获取所有已加载线程 ID 列表
2. 按字母顺序排序
3. 确定起始位置:
   - 如果 cursor 存在，找到该 ID 的索引 + 1
   - 如果 cursor 不存在或无效，从 0 开始
4. 计算结束位置: min(起始 + limit, 总数)
5. 截取子数组作为当前页数据
6. 如果结束位置 < 总数，设置 nextCursor 为当前页最后一个 ID
7. 否则 nextCursor 为 null
```

## 关键代码路径与文件引用

### 核心实现

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3011-3020` | ThreadLoadedListResponse 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:287-290` | ClientRequest 枚举中注册 thread/loaded/list 方法 |
| `codex-rs/app-server/src/codex_message_processor.rs:3116-3170` | thread_loaded_list 方法实现 |

### 测试代码

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_loaded_list.rs` | 完整的功能测试套件 |
| `codex-rs/app-server/tests/suite/v2/thread_loaded_list.rs:18-46` | 基础列表响应测试 |
| `codex-rs/app-server/tests/suite/v2/thread_loaded_list.rs:48-100` | 分页响应测试 |

### 生成的 Schema 和类型

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadLoadedListResponse.json` | JSON Schema 定义（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadLoadedListResponse.ts` | TypeScript 类型定义 |

## 依赖与外部交互

### 上游依赖

1. **ThreadManager** (`codex_core::ThreadManager`):
   - `list_thread_ids()` 方法返回 `Vec<ThreadId>`
   - 反映内存中当前加载的所有线程

2. **ThreadId** (`codex_protocol::ThreadId`):
   - 线程唯一标识符
   - 支持字符串转换

### 下游消费

1. **VSCode 扩展**: 活跃会话列表 UI
2. **TUI 客户端**: 状态监控面板
3. **CLI 客户端**: `ps` 或 `list --loaded` 命令

### 相关请求

- `ThreadLoadedListParams` - 请求参数（cursor, limit）
- `ThreadReadParams` - 获取单个线程详情

## 风险、边界与改进建议

### 已知风险

1. **数据一致性**:
   - 查询过程中线程可能被加载或卸载
   - 分页结果可能不一致

2. **游标有效性**:
   - 如果游标指向的线程被卸载，后续查询可能跳过某些线程
   - 无效游标返回错误（而非忽略）

3. **排序稳定性**:
   - 按 ID 字母顺序排序
   - 不反映加载时间或优先级

### 边界情况

1. **空列表**:
   - 如果没有已加载线程，返回 `data: []`
   - `nextCursor` 为 `null`

2. **无效游标**:
   - 返回 JSON-RPC 错误（code: -32600）
   - 错误消息包含无效游标值

3. **单页全部**:
   - 默认 limit 为无限制（返回所有）
   - 建议显式设置 limit 进行分页

4. **并发修改**:
   - 查询和遍历过程中线程列表可能变化
   - 可能返回已卸载的线程 ID（短暂不一致）

### 改进建议

1. **快照机制**:
   - 使用快照保证分页一致性
   - 避免并发修改问题

2. **时间戳信息**:
   - 添加 `loadedAt` 时间戳
   - 支持按加载时间排序

3. **状态信息**:
   - 可选返回线程状态（idle/active）
   - 减少后续查询

4. **增量更新**:
   - 支持 `since` 参数
   - 只返回某时间后加载的线程

5. **事件推送**:
   - WebSocket 推送线程加载/卸载事件
   - 实时同步客户端

6. **批量详情接口**:
   - 提供 `thread/loaded/details` 接口
   - 批量获取已加载线程的元数据
