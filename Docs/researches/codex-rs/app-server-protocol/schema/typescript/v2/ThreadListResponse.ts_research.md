# ThreadListResponse.ts 研究文档

## 场景与职责

`ThreadListResponse` 是 Codex App-Server Protocol v2 API 中 `thread/list` 方法的响应类型，返回线程列表及分页信息。

## 功能点目的

### 核心功能

| 字段 | 类型 | 说明 |
|------|------|------|
| `data` | `Array<Thread>` | 线程列表 |
| `nextCursor` | `string \| null` | 下一页游标，null 表示无更多数据 |

### 设计特点

1. **标准分页格式**：采用 cursor-based 分页，避免偏移量分页的问题
2. **数据包装**：线程列表包装在 `data` 字段中，便于扩展
3. **终止指示**：`nextCursor` 为 null 明确表示已到达末尾

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadListResponse = { 
  data: Array<Thread>, 
  nextCursor: string | null, 
};
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2989-2997) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadListResponse {
    pub data: Vec<Thread>,
    pub next_cursor: Option<String>,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2989-2997): Rust 类型定义

### 下游使用方
- 客户端接收 `thread/list` RPC 响应

### 相关类型
- `ThreadListParams.ts`: 列表查询参数
- `Thread.ts`: 线程类型

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadListResponse } from "./v2";

// 首次查询
const response: ThreadListResponse = await client.request("thread/list", {
  limit: 20
});

console.log(`Found ${response.data.length} threads`);

// 检查是否有更多数据
if (response.nextCursor) {
  // 加载下一页
  const nextPage: ThreadListResponse = await client.request("thread/list", {
    cursor: response.nextCursor,
    limit: 20
  });
  console.log(`Loaded ${nextPage.data.length} more threads`);
}

// 遍历所有线程
for (const thread of response.data) {
  console.log(`${thread.name || thread.preview} (${thread.id})`);
}
```

### 分页遍历示例

```typescript
async function* listAllThreads(client: Client) {
  let cursor: string | null = null;
  
  do {
    const response: ThreadListResponse = await client.request("thread/list", {
      cursor,
      limit: 50
    });
    
    for (const thread of response.data) {
      yield thread;
    }
    
    cursor = response.nextCursor;
  } while (cursor);
}

// 使用
for await (const thread of listAllThreads(client)) {
  console.log(thread.id);
}
```

## 风险、边界与改进建议

### 边界情况

1. **空列表**：`data` 为空数组，`nextCursor` 为 null
2. **游标失效**：使用过期游标查询可能返回错误
3. **数据一致性**：分页过程中数据变更可能导致重复或遗漏

### 改进建议

1. **添加总数**：`totalCount` 字段显示总线程数
2. **添加统计**：`stats` 字段显示各状态线程数量
3. **快照支持**：添加 `snapshotId` 支持一致性快照查询

### 注意事项

- 该文件为**自动生成**
- 游标是 opaque 的，客户端不应解析其内容
- 线程列表中的 `turns` 字段通常为空（性能优化）
