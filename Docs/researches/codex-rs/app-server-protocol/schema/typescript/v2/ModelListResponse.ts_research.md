# ModelListResponse.ts 调研文档

## 场景与职责

`ModelListResponse` 是 Codex App Server Protocol v2 API 中用于 `model/list` 方法的响应类型。它封装了模型列表查询的结果，包括模型数据数组和分页游标。

主要使用场景包括：
- 响应客户端的模型列表查询请求
- 提供分页数据以支持大型模型列表
- 返回完整的模型元数据供客户端展示

## 功能点目的

该类型的核心目的是提供标准化的模型列表响应格式：

1. **数据承载**：通过 `data` 字段返回 `Model` 对象数组
2. **分页支持**：通过 `nextCursor` 支持游标分页，处理大量模型数据
3. **完成指示**：`nextCursor` 为 `null` 时表示没有更多数据

TypeScript 定义：
```typescript
export type ModelListResponse = { 
    data: Array<Model>, 
    nextCursor: string | null 
}
```

## 具体技术实现

### Rust 端实现

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ModelListResponse {
    pub data: Vec<Model>,
    /// Opaque cursor to pass to the next call to continue after the last item.
    /// If None, there are no more items to return.
    pub next_cursor: Option<String>,
}
```

### 嵌套类型 Model

`Model` 结构定义了单个模型的完整元数据：

```rust
pub struct Model {
    pub id: String,
    pub model: String,
    pub upgrade: Option<String>,
    pub upgrade_info: Option<ModelUpgradeInfo>,
    pub availability_nux: Option<ModelAvailabilityNux>,
    pub display_name: String,
    pub description: String,
    pub hidden: bool,
    pub supported_reasoning_efforts: Vec<ReasoningEffortOption>,
    pub default_reasoning_effort: ReasoningEffort,
    pub input_modalities: Vec<InputModality>,
    pub supports_personality: bool,
    pub is_default: bool,
}
```

### API 方法定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
ModelList => "model/list" {
    params: v2::ModelListParams,
    response: v2::ModelListResponse,
}
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 协议定义，第 1787-1795 行 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ModelListResponse.ts` | 生成的 TypeScript 类型定义 |

### 引用文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 在 RPC 方法定义中引用（第 391 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/Model.ts` | 导入 Model 类型 |

### 类型依赖图

```
ModelListResponse
├── data: Vec<Model>
│   ├── ModelAvailabilityNux
│   ├── ModelUpgradeInfo
│   ├── ReasoningEffortOption
│   ├── ReasoningEffort
│   └── InputModality
└── next_cursor: Option<String>
```

## 依赖与外部交互

### 内部依赖

1. **Model 类型**：响应的核心数据类型
2. **序列化框架**：`serde` 用于 JSON 序列化
3. **TypeScript 生成**：`ts-rs` crate
4. **JSON Schema 生成**：`schemars` crate

### 外部交互

- **App Server**：构建并返回此响应
- **客户端应用**：解析响应并展示模型列表

### 分页流程

```
客户端                                    服务器
   |                                        |
   |---- ModelListParams {cursor: null} --->|
   |                                        |
   |<--- ModelListResponse {data, nextCursor} |
   |                                        |
   |---- ModelListParams {cursor: "xxx"} -->|
   |                                        |
   |<--- ModelListResponse {data, nextCursor: null} |
   |                                        |
```

## 风险、边界与改进建议

### 潜在风险

1. **响应体过大**：如果 `data` 数组包含大量完整 Model 对象，响应可能过大
   - 建议：考虑添加字段选择机制或压缩

2. **游标安全性**：`nextCursor` 可能包含敏感信息如果被编码
   - 建议：使用加密或签名保护游标内容

3. **数据一致性**：分页过程中模型数据可能变化
   - 风险：可能出现重复或遗漏
   - 建议：考虑使用快照或版本机制

### 边界情况

1. **空列表**：`data` 为空数组时 `nextCursor` 应为 `null`
2. **单页完成**：所有数据在一页内返回时 `nextCursor` 为 `null`
3. **错误处理**：查询失败时的错误响应格式

### 改进建议

1. **添加元数据字段**：
   ```rust
   pub struct ModelListResponse {
       pub data: Vec<Model>,
       pub next_cursor: Option<String>,
       pub total_count: Option<u32>,  // 总模型数
       pub has_more: bool,            // 是否有更多数据
   }
   ```

2. **支持字段选择**：
   ```rust
   // 在 ModelListParams 中添加
   pub fields: Option<Vec<String>>,  // 只返回指定字段
   ```

3. **添加缓存控制**：
   ```rust
   pub cache_key: Option<String>,    // 用于客户端缓存
   pub expires_at: Option<i64>,      // 响应过期时间
   ```

4. **游标改进**：
   - 添加游标过期时间
   - 支持双向分页（previous_cursor）

5. **测试增强**：
   - 测试空列表响应
   - 测试分页边界
   - 验证游标连续性
   - 测试大数据量性能
