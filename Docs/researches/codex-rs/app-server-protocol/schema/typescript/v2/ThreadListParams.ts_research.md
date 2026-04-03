# ThreadListParams.ts 研究文档

## 场景与职责

`ThreadListParams` 是 Codex App-Server Protocol v2 API 中 `thread/list` 方法的请求参数类型，用于查询线程列表。支持分页、排序、过滤等多种查询条件。

## 功能点目的

### 核心功能

| 字段 | 类型 | 说明 |
|------|------|------|
| `cursor` | `string \| null` | 分页游标（上一页返回的 nextCursor） |
| `limit` | `number \| null` | 每页数量限制 |
| `sortKey` | `ThreadSortKey \| null` | 排序字段（created_at 或 updated_at） |
| `modelProviders` | `Array<string> \| null` | 按模型提供商过滤 |
| `sourceKinds` | `Array<ThreadSourceKind> \| null` | 按来源类型过滤 |
| `archived` | `boolean \| null` | 是否包含已归档线程 |
| `cwd` | `string \| null` | 按工作目录精确匹配过滤 |
| `searchTerm` | `string \| null` | 按线程标题子串搜索 |

### 设计特点

1. **游标分页**：使用 opaque cursor 实现稳定分页
2. **多维度过滤**：支持来源、提供商、归档状态等多种过滤条件
3. **灵活排序**：支持按创建时间或更新时间排序

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadListParams = { 
  cursor?: string | null, 
  limit?: number | null, 
  sortKey?: ThreadSortKey | null, 
  modelProviders?: Array<string> | null, 
  sourceKinds?: Array<ThreadSourceKind> | null, 
  archived?: boolean | null, 
  cwd?: string | null, 
  searchTerm?: string | null, 
};
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2932-2961) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadListParams {
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
    #[ts(optional = nullable)]
    pub sort_key: Option<ThreadSortKey>,
    #[ts(optional = nullable)]
    pub model_providers: Option<Vec<String>>,
    #[ts(optional = nullable)]
    pub source_kinds: Option<Vec<ThreadSourceKind>>,
    #[ts(optional = nullable)]
    pub archived: Option<bool>,
    #[ts(optional = nullable)]
    pub cwd: Option<String>,
    #[ts(optional = nullable)]
    pub search_term: Option<String>,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2932-2961): Rust 类型定义

### 下游使用方
- 客户端调用 `thread/list` RPC 方法

### 相关类型
- `ThreadListResponse.ts`: 列表查询响应
- `ThreadSortKey.ts`: 排序字段枚举
- `ThreadSourceKind.ts`: 来源类型枚举

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadListParams } from "./v2";

// 基本查询
const params: ThreadListParams = {
  limit: 20,
  sortKey: "updated_at"
};

// 查询已归档线程
const archivedParams: ThreadListParams = {
  archived: true,
  limit: 10
};

// 按来源过滤
const filteredParams: ThreadListParams = {
  sourceKinds: ["cli", "vscode"],
  modelProviders: ["openai"],
  limit: 50
};

// 分页查询
const paginatedParams: ThreadListParams = {
  cursor: "eyJsYXN0X2lkIjogMTIzfQ==",
  limit: 20
};

// 搜索
const searchParams: ThreadListParams = {
  searchTerm: "refactor",
  limit: 10
};

const response = await client.request("thread/list", params);
```

## 风险、边界与改进建议

### 边界情况

1. **游标过期**：游标可能因数据变更而失效
2. **空结果**：过滤条件过于严格时可能返回空列表
3. **性能问题**：大量线程时的查询性能

### 改进建议

1. **添加时间范围过滤**：`createdAfter`, `createdBefore`
2. **添加标签过滤**：支持按标签查询
3. **模糊搜索增强**：支持正则或更高级的搜索语法
4. **排序方向**：添加 `sortDirection` 支持升序/降序

### 注意事项

- 该文件为**自动生成**
- `archived` 为 null 时默认不包含已归档线程
- `sourceKinds` 为空数组时包含所有来源
