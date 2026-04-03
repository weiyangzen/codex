# ExperimentalFeatureListParams.ts 研究文档

## 场景与职责

`ExperimentalFeatureListParams.ts` 定义了实验性功能列表查询的参数类型，用于客户端向服务器请求实验性功能列表。支持分页查询，使客户端能够高效获取大量实验性功能信息。

该类型在实验性功能发现、设置界面初始化、功能状态同步等场景中发挥作用。

## 功能点目的

1. **分页查询**: 支持游标分页，高效处理大量功能
2. **列表控制**: 允许客户端控制返回结果的数量
3. **增量同步**: 支持基于游标的增量数据获取

## 具体技术实现

### 数据结构定义

```typescript
export type ExperimentalFeatureListParams = { 
  /**
   * Opaque pagination cursor returned by a previous call.
   */
  cursor?: string | null, 
  /**
   * Optional page size; defaults to a reasonable server-side value.
   */
  limit?: number | null, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `cursor` | `string \| null` | 分页游标，上一页返回的 `nextCursor`，首次查询为 `null` |
| `limit` | `number \| null` | 每页返回的最大功能数量，服务器有默认值 |

### 使用示例

```typescript
// 首次查询
const params: ExperimentalFeatureListParams = {
  cursor: null,
  limit: 20
};

// 后续分页查询
const nextParams: ExperimentalFeatureListParams = {
  cursor: response.nextCursor,  // 使用上一页的游标
  limit: 20
};
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1835-1845)

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ExperimentalFeatureListParams {
    /// Opaque pagination cursor returned by a previous call.
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    /// Optional page size; defaults to a reasonable server-side value.
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
}
```

### 响应类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1886-1894)

```rust
pub struct ExperimentalFeatureListResponse {
    pub data: Vec<ExperimentalFeature>,
    /// Opaque cursor to pass to the next call to continue after the last item.
    /// If None, there are no more items to return.
    pub next_cursor: Option<String>,
}
```

### 客户端请求定义

**文件**: `codex-rs/app-server-protocol/src/protocol/common.rs`

```rust
client_request_definitions! {
    // ...
    ExperimentalFeatureList => "experimentalFeature/list" {
        params: v2::ExperimentalFeatureListParams,
        response: v2::ExperimentalFeatureListResponse,
    }
    // ...
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `ts-rs` | TypeScript 类型生成 |
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **TUI 设置界面**: 获取实验性功能列表
- **VS Code 扩展**: 同步实验性功能状态
- **CLI**: 列出可用功能

## 风险、边界与改进建议

### 已知风险

1. **功能数量**: 实验性功能通常数量不多，分页可能过度设计
2. **游标过期**: 游标可能有有效期，过期后需要重新查询
3. **默认值不明**: `limit` 的默认值未明确说明

### 边界情况

1. **空列表**: 服务器可能返回空列表
2. **无效游标**: 游标可能过期或无效
3. **超大 limit**: 客户端可能请求过大的页面大小

### 改进建议

1. **过滤条件**: 增加按阶段、分类过滤的功能
2. **排序选项**: 支持按名称、阶段排序
3. **搜索功能**: 支持按名称搜索功能
4. **默认值明确**: 在文档中明确 `limit` 的默认值
5. **游标说明**: 说明游标的有效期和格式

### 扩展示例

```typescript
export type ExperimentalFeatureListParams = { 
  cursor?: string | null, 
  limit?: number | null,
  // 新增字段
  filter?: {
    stages?: ExperimentalFeatureStage[],  // 按阶段过滤
    categories?: string[],  // 按分类过滤
    enabled?: boolean,  // 只显示启用/禁用的功能
  },
  sort?: {
    field: 'name' | 'stage' | 'enabled',
    order: 'asc' | 'desc',
  },
  search?: string,  // 搜索关键词
};
```
