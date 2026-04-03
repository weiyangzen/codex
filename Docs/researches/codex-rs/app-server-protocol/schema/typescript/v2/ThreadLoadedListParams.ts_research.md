# ThreadLoadedListParams.ts 研究文档

## 场景与职责

`ThreadLoadedListParams` 是 Codex App-Server Protocol v2 API 中 `thread/loaded/list` 方法的请求参数类型，用于查询当前已加载到内存中的线程列表。与 `thread/list` 不同，该接口仅返回内存中的活跃线程。

## 功能点目的

### 核心功能

| 字段 | 类型 | 说明 |
|------|------|------|
| `cursor` | `string \| null` | 分页游标 |
| `limit` | `number \| null` | 每页数量限制，默认无限制 |

### 设计特点

1. **内存状态查询**：查询当前内存中的线程，而非持久化存储
2. **轻量分页**：仅支持基本分页参数
3. **无过滤**：不支持复杂的过滤条件

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadLoadedListParams = { 
  cursor?: string | null, 
  limit?: number | null, 
};
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2999-3009) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadLoadedListParams {
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2999-3009): Rust 类型定义

### 下游使用方
- 客户端调用 `thread/loaded/list` RPC 方法

### 相关类型
- `ThreadLoadedListResponse.ts`: 响应类型
- `ThreadListParams.ts`: 完整列表查询参数（对比）

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadLoadedListParams } from "./v2";

// 查询所有已加载线程
const params: ThreadLoadedListParams = {};

// 分页查询
const paginatedParams: ThreadLoadedListParams = {
  cursor: "some_cursor",
  limit: 100
};

const response = await client.request("thread/loaded/list", params);
console.log(`Loaded threads: ${response.data.join(", ")}`);
```

### 与 thread/list 的区别

| 特性 | thread/list | thread/loaded/list |
|------|-------------|-------------------|
| 数据来源 | 持久化存储 | 内存 |
| 返回内容 | 完整 Thread 对象 | 仅线程 ID |
| 过滤条件 | 丰富 | 无 |
| 使用场景 | 浏览历史 | 管理活跃会话 |

## 风险、边界与改进建议

### 边界情况

1. **无加载线程**：返回空列表
2. **线程卸载**：查询结果可能随时变化（线程被卸载）

### 改进建议

1. **添加状态过滤**：按线程状态过滤（active, idle 等）
2. **添加统计信息**：返回内存中线程数量统计
3. **添加加载时间**：显示线程加载到内存的时间

### 注意事项

- 该文件为**自动生成**
- 返回的是线程 ID 列表而非完整线程对象
- 结果反映的是瞬时的内存状态
