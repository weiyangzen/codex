# ExperimentalFeatureListResponse.ts 研究文档

## 场景与职责

`ExperimentalFeatureListResponse.ts` 定义了实验性功能列表查询的响应类型，用于向客户端返回实验性功能列表及分页信息。这是 `experimentalFeature/list` RPC 方法的响应结构。

该类型在实验性功能发现、设置界面展示、功能状态同步等场景中发挥作用。

## 功能点目的

1. **功能列表返回**: 提供实验性功能对象数组
2. **分页支持**: 通过游标支持分页查询
3. **增量加载**: 支持客户端按需加载更多功能

## 具体技术实现

### 数据结构定义

```typescript
export type ExperimentalFeatureListResponse = { 
  data: Array<ExperimentalFeature>, 
  /**
   * Opaque cursor to pass to the next call to continue after the last item.
   * If None, there are no more items to return.
   */
  nextCursor: string | null, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `data` | `ExperimentalFeature[]` | 实验性功能对象数组 |
| `nextCursor` | `string \| null` | 下一页游标，为 `null` 表示没有更多数据 |

### 使用示例

```typescript
// 处理响应
const response: ExperimentalFeatureListResponse = await client.listExperimentalFeatures(params);

// 显示功能列表
for (const feature of response.data) {
  console.log(`${feature.displayName}: ${feature.enabled ? '已启用' : '已禁用'}`);
}

// 检查是否有更多数据
if (response.nextCursor) {
  // 加载下一页
  const nextParams = { cursor: response.nextCursor, limit: 20 };
  const nextResponse = await client.listExperimentalFeatures(nextParams);
}
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1886-1894)

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ExperimentalFeatureListResponse {
    pub data: Vec<ExperimentalFeature>,
    /// Opaque cursor to pass to the next call to continue after the last item.
    /// If None, there are no more items to return.
    pub next_cursor: Option<String>,
}
```

### 依赖类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1863-1884)

```rust
pub struct ExperimentalFeature {
    pub name: String,
    pub stage: ExperimentalFeatureStage,
    pub display_name: Option<String>,
    pub description: Option<String>,
    pub announcement: Option<String>,
    pub enabled: bool,
    pub default_enabled: bool,
}
```

### 请求类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1835-1845)

```rust
pub struct ExperimentalFeatureListParams {
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
}
```

### 客户端请求定义

**文件**: `codex-rs/app-server-protocol/src/protocol/common.rs`

```rust
client_request_definitions! {
    ExperimentalFeatureList => "experimentalFeature/list" {
        params: v2::ExperimentalFeatureListParams,
        response: v2::ExperimentalFeatureListResponse,
    }
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `ExperimentalFeature` | 实验性功能详情类型 |
| `ts-rs` | TypeScript 类型生成 |
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **TUI 设置界面**: 展示实验性功能列表
- **VS Code 扩展**: 同步实验性功能状态
- **CLI**: 列出可用功能

## 风险、边界与改进建议

### 已知风险

1. **空数据**: `data` 可能为空数组
2. **游标格式**: 游标为不透明字符串，客户端不应解析其内容
3. **数据一致性**: 分页过程中数据可能变化

### 边界情况

1. **最后一页**: `nextCursor` 为 `null` 表示已到末尾
2. **部分数据**: 实际返回数量可能少于请求的 `limit`
3. **重复数据**: 数据变化可能导致分页中出现重复或遗漏

### 改进建议

1. **总数信息**: 增加总功能数量字段
2. **元数据**: 增加响应元数据（如生成时间）
3. **过滤统计**: 如果有过滤条件，返回匹配数量
4. **缓存控制**: 增加缓存相关头部信息

### 扩展示例

```typescript
export type ExperimentalFeatureListResponse = { 
  data: Array<ExperimentalFeature>, 
  nextCursor: string | null,
  // 新增字段
  meta: {
    total: number,  // 总数量
    returned: number,  // 本次返回数量
    generatedAt: string,  // ISO 8601 时间戳
  },
};
```
