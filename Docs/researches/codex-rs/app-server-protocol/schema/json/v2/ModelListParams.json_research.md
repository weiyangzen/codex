# ModelListParams.json 研究文档

## 场景与职责

`ModelListParams.json` 是 Codex 应用服务器协议 v2 的 JSON Schema 定义文件，用于描述模型列表查询请求的参数结构。

该参数结构用于 `model/list` 方法，支持分页查询和隐藏模型过滤，使客户端能够获取可用的 AI 模型列表。

## 功能点目的

1. **分页查询**: 支持游标分页，处理大量模型数据的高效加载
2. **隐藏模型控制**: 允许客户端选择是否包含隐藏的模型
3. **模型发现**: 支持客户端展示模型选择器、模型对比等功能
4. **配置支持**: 为模型配置和切换提供数据基础

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "cursor": {
      "description": "Opaque pagination cursor returned by a previous call.",
      "type": ["string", "null"]
    },
    "includeHidden": {
      "description": "When true, include models that are hidden from the default picker list.",
      "type": ["boolean", "null"]
    },
    "limit": {
      "description": "Optional page size; defaults to a reasonable server-side value.",
      "format": "uint32",
      "minimum": 0.0,
      "type": ["integer", "null"]
    }
  },
  "title": "ModelListParams",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string \| null | 否 | 分页游标，由上一次调用返回，用于获取下一页数据 |
| `includeHidden` | boolean \| null | 否 | 是否包含隐藏模型，默认为 false |
| `limit` | integer \| null | 否 | 分页大小，服务器有默认值 |

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:1717
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

### 方法映射

```rust
// common.rs 行 389-392
ModelList => "model/list" {
    params: v2::ModelListParams,
    response: v2::ModelListResponse,
}
```

## 关键代码路径与文件引用

### 协议定义
- **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1717-1730)
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ModelListParams.json`
- **方法注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 389-392)

### 调用方
- **客户端**: VSCode 扩展、CLI、TUI 等需要展示模型列表的界面
- **配置系统**: 模型选择配置验证

### 响应结构
- **对应响应**: `ModelListResponse` - 包含模型数据数组和下一页游标

## 依赖与外部交互

### 上游依赖
1. **模型注册表**: 服务器需要维护可用的模型列表
2. **分页存储**: 支持游标分页的数据存储机制
3. **模型元数据**: 包含模型能力、特性等描述信息

### 下游使用方
1. **模型选择器 UI**: 展示可用模型列表
2. **配置验证**: 验证用户配置的模型是否有效
3. **模型升级提示**: 根据模型元数据展示升级建议

### 相关数据结构
- **Model**: 模型详情结构，包含 ID、名称、描述、能力等
- **ModelListResponse**: 列表查询响应结构
- **ReasoningEffort**: 模型推理能力配置

## 风险、边界与改进建议

### 潜在风险
1. **游标过期**: 分页游标可能有过期时间，客户端需要处理过期情况
2. **并发修改**: 模型列表可能在分页查询过程中发生变化
3. **缓存一致性**: 客户端缓存的模型列表可能与服务器不一致

### 边界情况
1. **空结果**: 当没有可用模型时返回空数组
2. **无效游标**: 使用过期或无效游标查询时的错误处理
3. **超大 limit**: 客户端请求过大的 limit 值时的服务器处理策略

### 改进建议

#### 1. 添加过滤条件
```json
{
  "cursor": "...",
  "limit": 20,
  "includeHidden": false,
  "provider": "openai",
  "capabilities": ["image", "reasoning"],
  "search": "gpt-4"
}
```

#### 2. 添加排序选项
```json
{
  "cursor": "...",
  "limit": 20,
  "sortBy": "popularity",
  "sortOrder": "desc"
}
```

#### 3. 响应优化
- 添加 `totalCount` 字段，让客户端知道总模型数量
- 添加 `hasMore` 布尔字段，简化客户端分页逻辑

#### 4. 缓存支持
```json
{
  "cursor": "...",
  "limit": 20,
  "ifModifiedSince": 1712345678
}
```

### 最佳实践
1. **默认分页**: 客户端首次调用时不传 cursor，获取第一页
2. **增量加载**: 实现滚动加载或分页按钮，按需获取更多模型
3. **本地缓存**: 缓存模型列表，减少重复请求
4. **错误重试**: 实现游标过期后的回退机制（重新从第一页加载）

### 相关 API
- `ModelListResponse` - 模型列表响应
- `ThreadStartParams` - 创建线程时可指定模型
- `ThreadResumeParams` - 恢复线程时可切换模型
