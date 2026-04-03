# ListMcpServerStatusParams 研究文档

## 1. 场景与职责

`ListMcpServerStatusParams` 是 App-Server Protocol v2 中的参数类型，用于 `mcpServer/list` RPC 方法的请求参数。该类型支持分页查询 MCP（Model Context Protocol）服务器的状态列表。

**主要使用场景：**
- 客户端获取已配置的 MCP 服务器列表
- 管理界面展示 MCP 服务器状态
- 分页加载大量 MCP 服务器信息
- 刷新 MCP 服务器状态

## 2. 功能点目的

该类型的核心目的是提供分页查询 MCP 服务器状态的能力：

1. **分页控制**：通过 `cursor` 和 `limit` 实现游标分页
2. **性能优化**：避免一次性返回大量数据
3. **状态同步**：支持增量获取服务器状态变更

这个设计使得客户端能够：
- 高效管理大量 MCP 服务器
- 实现流畅的分页加载体验
- 按需获取服务器状态信息

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type ListMcpServerStatusParams = { 
  cursor: string | null, 
  limit: number | null, 
};
```

### Rust 源定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ListMcpServerStatusParams {
    /// Opaque pagination cursor returned by a previous call.
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    /// Optional page size; defaults to a server-defined value.
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `cursor` | `string \| null` | 分页游标，由上一次调用返回；首次调用为 `null` |
| `limit` | `number \| null` | 可选的页面大小；默认使用服务器定义的值 |

### 特性注解

- `#[serde(rename_all = "camelCase")]`：字段序列化为 camelCase 格式
- `#[ts(export_to = "v2/")]`：TypeScript 类型导出到 `v2/` 目录
- `#[ts(optional = nullable)]`：TypeScript 中标记为可选且可为 null
- 支持 JSON Schema 生成

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 1896-1906 行

### 相关类型

- `McpServerStatus`：MCP 服务器状态（第 1908-1917 行）
- `ListMcpServerStatusResponse`：列表响应类型（包含 `data` 和 `next_cursor`）

### 相关 RPC 方法

- `mcpServer/list`：列出 MCP 服务器状态

## 5. 依赖与外部交互

### 序列化行为

- 使用 `serde` 进行 JSON 序列化/反序列化
- 字段名自动转换为 camelCase
- 可选字段在 TypeScript 中表示为 `T | null`

### 分页模式

遵循 v2 API 的标准游标分页模式：
- 请求：`cursor`（可选）、`limit`（可选）
- 响应：`data`（数据列表）、`next_cursor`（下一页游标，无更多数据时为 null）

## 6. 风险、边界与改进建议

### 潜在风险

1. **游标过期**：游标可能在一段时间后失效
2. **数据一致性**：分页过程中数据变更可能导致重复或遗漏
3. **默认限制**：未指定 `limit` 时的默认行为可能不符合预期
4. **并发修改**：列表在分页过程中被修改可能导致异常

### 边界情况

- 首次调用时 `cursor` 为 `null`
- `limit` 为 `null` 时使用服务器默认值
- 返回空列表时表示无更多数据
- 无效的游标值的处理

### 改进建议

1. **添加过滤条件**：
   - 支持按名称过滤
   - 支持按状态过滤（如只返回在线的服务器）
   - 支持按类型过滤

2. **排序选项**：
   - 支持按名称排序
   - 支持按状态排序
   - 支持按最后更新时间排序

3. **一致性保证**：
   - 添加快照版本号
   - 支持一致性读取
   - 处理并发修改的冲突

4. **性能优化**：
   - 支持字段选择（只返回需要的字段）
   - 实现缓存机制
   - 支持增量同步

### 使用示例

```typescript
// 首次调用
const params1: ListMcpServerStatusParams = {
  cursor: null,
  limit: 10
};

// 使用返回的游标获取下一页
const params2: ListMcpServerStatusParams = {
  cursor: response.next_cursor,
  limit: 10
};
```

### 与其他列表参数的对比

| 参数类型 | 用途 | 字段 |
|----------|------|------|
| `ListMcpServerStatusParams` | 列出 MCP 服务器 | `cursor`, `limit` |
| `ModelListParams` | 列出模型 | `cursor`, `limit`, `include_hidden` |
| `ExperimentalFeatureListParams` | 列出实验性功能 | `cursor`, `limit` |

### 最佳实践

- 首次调用时 `cursor` 设为 `null`
- 根据 UI 需求设置合适的 `limit`
- 处理 `next_cursor` 为 `null` 的情况（无更多数据）
- 实现错误重试机制
