# ModelListParams.ts 调研文档

## 场景与职责

`ModelListParams` 是 Codex App Server Protocol v2 API 中用于 `model/list` 方法的请求参数类型。它定义了客户端获取可用模型列表时可以提供的过滤和分页选项。

主要使用场景包括：
- 客户端请求可用模型列表（如模型选择器 UI）
- 分页获取大量模型数据
- 过滤隐藏模型以显示完整列表

## 功能点目的

该类型的核心目的是提供标准化的模型列表查询参数：

1. **分页支持**：通过 `cursor` 和 `limit` 实现游标分页，处理大量模型数据
2. **可见性控制**：通过 `includeHidden` 控制是否返回隐藏模型
3. **灵活查询**：所有字段均为可选，支持无参数查询（使用服务器默认值）

TypeScript 定义：
```typescript
export type ModelListParams = { 
    cursor?: string | null, 
    limit?: number | null, 
    includeHidden?: boolean | null 
}
```

## 具体技术实现

### Rust 端实现

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ModelListParams {
    /// Opaque pagination cursor returned by a previous call.
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    /// Optional page size; defaults to a reasonable server-side value.
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
    /// When true, include models that are hidden from the default picker list.
    #[ts(optional = nullable)]
    pub include_hidden: Option<bool>,
}
```

### API 方法定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中注册为 RPC 方法：

```rust
ModelList => "model/list" {
    params: v2::ModelListParams,
    response: v2::ModelListResponse,
}
```

### 序列化行为

所有可选字段使用 `#[ts(optional = nullable)]` 注解，确保 TypeScript 端可以省略字段或传递 `null`。

序列化示例：
```json
{
    "cursor": null,
    "limit": null,
    "includeHidden": null
}
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 协议定义，第 1717-1730 行 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ModelListParams.ts` | 生成的 TypeScript 类型定义 |

### 引用文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 在 RPC 方法定义中引用（第 390 行） |

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 序列化测试（第 1408-1427 行） |

## 依赖与外部交互

### 内部依赖

1. **序列化框架**：`serde`
   - `#[serde(rename_all = "camelCase")]` 确保字段名符合 JSON 规范

2. **TypeScript 生成**：`ts-rs` crate
   - `#[ts(export_to = "v2/")]` 指定输出目录
   - `#[ts(optional = nullable)]` 标记可选字段

3. **JSON Schema 生成**：`schemars` crate
   - 用于 API 文档生成

### 外部交互

- **客户端应用**：调用 `model/list` 方法时传递此参数
- **App Server**：解析参数并返回 `ModelListResponse`

### 相关类型

```
ModelListParams
    └── model/list RPC 方法请求参数
        └── ModelListResponse (响应类型)
```

## 风险、边界与改进建议

### 潜在风险

1. **limit 值过大**：如果客户端传递过大的 `limit` 值，可能导致服务器负载过高
   - 建议：服务器端应设置最大 `limit` 上限并做截断处理

2. **游标失效**：`cursor` 可能在分页过程中失效（如模型列表更新）
   - 建议：定义游标失效时的错误处理策略

3. **类型不匹配**：TypeScript 中 `limit` 是 `number`，但 Rust 中是 `u32`
   - 风险：负数或超大值可能导致解析错误
   - 建议：添加输入验证

### 边界情况

1. **空游标**：首次请求时 `cursor` 为 `null` 或省略
2. **零限制**：`limit` 为 0 时的行为
3. **布尔值处理**：`includeHidden` 为 `null` 时的默认行为

### 改进建议

1. **添加排序选项**：
   ```rust
   pub sort_by: Option<ModelSortField>,  // name, created_at, etc.
   pub sort_order: Option<SortOrder>,    // asc, desc
   ```

2. **添加过滤选项**：
   ```rust
   pub supports_reasoning: Option<bool>,
   pub provider: Option<String>,
   ```

3. **游标过期提示**：在响应中添加 `cursor_expires_at` 字段

4. **分页元数据**：在响应中添加总数量信息 `total_count`

5. **默认值文档化**：明确 `limit` 的服务器端默认值

6. **测试增强**：
   - 添加边界值测试（limit=0, limit=最大值）
   - 测试游标分页的连续性
   - 验证 `includeHidden` 的过滤效果
