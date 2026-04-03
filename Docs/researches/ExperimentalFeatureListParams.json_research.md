# ExperimentalFeatureListParams.json 研究文档

## 场景与职责

`ExperimentalFeatureListParams.json` 是 Codex app-server-protocol v2 API 的 JSON Schema 文件，定义了获取实验性功能列表时的请求参数结构。该文件位于 `codex-rs/app-server-protocol/schema/json/v2/` 目录下，是 app-server 协议的一部分，用于客户端向服务器请求分页的实验性功能列表。

**使用场景**：
- 客户端需要获取服务器支持的所有实验性功能列表
- 支持分页查询，避免一次性返回大量数据
- 用于实验性功能管理界面，让用户了解和启用/禁用实验性功能

**核心职责**：
- 定义分页参数的数据结构（cursor 和 limit）
- 提供 JSON Schema 验证，确保请求参数符合规范
- 支持 TypeScript 类型生成，供前端客户端使用

## 功能点目的

### 1. 分页参数设计

#### 1.1 Cursor（游标）
```json
{
  "cursor": {
    "description": "Opaque pagination cursor returned by a previous call.",
    "type": ["string", "null"]
  }
}
```

**设计目的**：
- 使用不透明游标（opaque cursor）而非页码，提供更好的抽象
- 游标由服务器生成和解析，客户端只需透传
- 支持更复杂的分页逻辑（如基于时间戳、ID 等）
- 避免传统 offset/limit 分页在大数据量时的性能问题

#### 1.2 Limit（限制）
```json
{
  "limit": {
    "description": "Optional page size; defaults to a reasonable server-side value.",
    "format": "uint32",
    "minimum": 0.0,
    "type": ["integer", "null"]
  }
}
```

**设计目的**：
- 允许客户端指定每页返回的条目数量
- 使用 `uint32` 格式确保非负整数
- 可选参数，服务器提供合理的默认值
- 防止客户端请求过多数据导致性能问题

### 2. API 设计原则

该参数结构遵循 app-server v2 API 的设计规范：

| 原则 | 实现 |
|------|------|
| 可选字段可为 null | `type: ["string", "null"]` 和 `type: ["integer", "null"]` |
| 驼峰命名 | `cursor`, `limit`（Rust 中 snake_case，序列化为 camelCase）|
| 清晰的描述 | 每个字段都有 description |
| 合理的默认值 | limit 由服务器决定默认值 |

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "cursor": {
      "description": "Opaque pagination cursor returned by a previous call.",
      "type": ["string", "null"]
    },
    "limit": {
      "description": "Optional page size; defaults to a reasonable server-side value.",
      "format": "uint32",
      "minimum": 0.0,
      "type": ["integer", "null"]
    }
  },
  "title": "ExperimentalFeatureListParams",
  "type": "object"
}
```

### Rust 数据结构

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

**关键属性说明**：

| 属性 | 说明 |
|------|------|
| `#[serde(rename_all = "camelCase")]` | 序列化时使用驼峰命名 |
| `#[ts(export_to = "v2/")]` | TypeScript 类型导出到 v2/ 目录 |
| `#[ts(optional = nullable)]` | TypeScript 中标记为可选且可为 null |
| `Default` trait | 提供默认值，方便构造空参数 |

### 在 API 中的使用

在 `common.rs` 的 `client_request_definitions!` 宏中注册：

```rust
ExperimentalFeatureList => "experimentalFeature/list" {
    params: v2::ExperimentalFeatureListParams,
    response: v2::ExperimentalFeatureListResponse,
}
```

**API 端点**：`experimentalFeature/list`

**请求方法**：JSON-RPC 风格的客户端请求

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 作用 |
|----------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ExperimentalFeatureListParams.json` | JSON Schema 定义（本文件） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 数据结构定义（第 1835-1845 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求注册（第 393-396 行） |

### 相关数据结构

```rust
// v2.rs 中的定义位置（约 1835-1894 行）
pub struct ExperimentalFeatureListParams { ... }      // 第 1838-1845 行
pub enum ExperimentalFeatureStage { ... }             // 第 1850-1861 行
pub struct ExperimentalFeature { ... }                // 第 1866-1884 行
pub struct ExperimentalFeatureListResponse { ... }    // 第 1889-1894 行
```

### Schema 生成流程

1. **定义**：在 `v2.rs` 中使用 Rust 结构体定义
2. **派生**：使用 `JsonSchema` derive 宏生成 schema
3. **导出**：运行 `just write-app-server-schema` 生成 JSON 文件
4. **验证**：运行 `cargo test -p codex-app-server-protocol` 验证

### 客户端请求定义

在 `common.rs` 中（第 205-541 行）：

```rust
client_request_definitions! {
    // ... 其他请求定义 ...
    ExperimentalFeatureList => "experimentalFeature/list" {
        params: v2::ExperimentalFeatureListParams,
        response: v2::ExperimentalFeatureListResponse,
    },
    // ...
}
```

## 依赖与外部交互

### 内部依赖

| 依赖 | 用途 |
|------|------|
| `serde` | 序列化和反序列化 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `ts_rs::TS` | TypeScript 类型生成 |

### 外部交互

**与客户端的交互**：
```json
// 请求示例
{
  "method": "experimentalFeature/list",
  "id": 1,
  "params": {
    "cursor": null,
    "limit": 50
  }
}

// 或使用游标继续分页
{
  "method": "experimentalFeature/list",
  "id": 2,
  "params": {
    "cursor": "eyJsYXN0X2lkIjogMTAwfQ==",
    "limit": 50
  }
}
```

**与服务器的交互**：
- 服务器解析 `cursor` 确定查询起始位置
- 服务器使用 `limit` 限制返回条目数
- 服务器返回 `ExperimentalFeatureListResponse` 包含数据和下一页游标

### 相关 API

| API | 关系 |
|-----|------|
| `ExperimentalFeatureListResponse` | 对应的响应结构 |
| `ExperimentalFeature` | 列表中的条目类型 |
| `ExperimentalFeatureStage` | 功能生命周期阶段枚举 |

## 风险、边界与改进建议

### 潜在风险

1. **游标过期**
   - 游标可能包含时间敏感信息
   - 如果服务器状态变化，旧游标可能失效
   - 需要定义游标过期策略和错误处理

2. **Limit 边界**
   - 客户端可能请求过大的 limit（虽然 uint32 有限制）
   - 服务器需要实现最大 limit 限制
   - 建议服务器设置上限（如 100 或 1000）

3. **空参数处理**
   - 两个字段都是可选的，服务器需要处理全 null 的情况
   - 需要明确定义默认行为（第一页、默认页大小）

### 边界情况

1. **首次请求**
   ```json
   { "cursor": null, "limit": null }
   ```
   - 应返回第一页数据
   - 使用服务器默认页大小

2. **最后一页**
   - 响应中 `next_cursor` 为 null
   - 客户端不应再发起后续请求

3. **无效游标**
   - 游标格式错误或已过期
   - 服务器应返回适当的错误信息

4. **零限制**
   ```json
   { "limit": 0 }
   ```
   - 语义不明确：返回空列表？还是使用默认值？
   - 建议服务器将 0 视为使用默认值

### 改进建议

1. **添加排序参数**
   ```rust
   pub sort_by: Option<String>,  // "name", "stage", "enabled"
   pub sort_order: Option<String>, // "asc", "desc"
   ```

2. **添加过滤参数**
   ```rust
   pub stage_filter: Option<Vec<ExperimentalFeatureStage>>,
   pub enabled_only: Option<bool>,
   ```

3. **游标格式文档化**
   ```markdown
   ## 游标格式
   游标是 Base64 编码的 JSON 对象，包含：
   - `last_id`: 最后一条记录的 ID
   - `timestamp`: 查询时间戳（用于一致性）
   ```

4. **添加元数据字段**
   ```rust
   pub include_metadata: Option<bool>,  // 是否返回总数等信息
   ```

5. **验证增强**
   ```rust
   impl ExperimentalFeatureListParams {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if let Some(limit) = self.limit {
               if limit > 1000 {
                   return Err(ValidationError::LimitTooLarge);
               }
           }
           Ok(())
       }
   }
   ```

6. **分页信息响应**
   在响应中添加分页元数据：
   ```rust
   pub struct ExperimentalFeatureListResponse {
       pub data: Vec<ExperimentalFeature>,
       pub next_cursor: Option<String>,
       pub total_count: Option<u64>,  // 总条目数
       pub has_more: bool,            // 是否有更多数据
   }
   ```

7. **缓存策略**
   - 实验性功能列表变化不频繁，可考虑缓存
   - 添加 `etag` 或 `version` 字段支持条件请求

### 使用示例

```rust
// 构建请求参数
let params = ExperimentalFeatureListParams {
    cursor: None,
    limit: Some(50),
};

// 或使用默认实现
let params = ExperimentalFeatureListParams::default();

// 序列化为 JSON
let json = serde_json::to_string(&params)?;
// 输出: {"cursor":null,"limit":50}
```

```typescript
// TypeScript 客户端使用
const params: ExperimentalFeatureListParams = {
    cursor: previousResponse.nextCursor,
    limit: 50
};

const response = await client.request('experimentalFeature/list', params);
```
