# McpElicitationUntitledMultiSelectEnumSchema 研究文档

## 场景与职责

`McpElicitationUntitledMultiSelectEnumSchema` 是 MCP Elicitation 系统中用于定义无标题多选枚举字段的 schema 类型。它允许用户从预定义选项中选择多个值，使用简单的字符串枚举数组来定义可选值。

与带标题的多选枚举相比，该类型结构更简单，适用于选项值本身就具有足够描述性的技术场景。

## 功能点目的

1. **多选枚举支持**: 为 MCP 表单提供多选字段的类型定义
2. **简化选项定义**: 使用简单的字符串数组定义选项，无需额外的标题
3. **数组类型**: 使用 JSON Schema 数组类型表示多选结果
4. **约束支持**: 支持 `minItems` 和 `maxItems` 限制选择数量

## 具体技术实现

### 数据结构定义

```typescript
export type McpElicitationUntitledMultiSelectEnumSchema = { 
  type: McpElicitationArrayType,      // "array"
  title?: string, 
  description?: string, 
  minItems?: bigint, 
  maxItems?: bigint, 
  items: McpElicitationUntitledEnumItems, 
  default?: Array<string>, 
};
```

### 无标题枚举项定义

```typescript
export type McpElicitationUntitledEnumItems = { 
  type: McpElicitationStringType,  // "string"
  enum: Array<string>, 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationUntitledMultiSelectEnumSchema {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationArrayType,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub min_items: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub max_items: Option<u64>,
    pub items: McpElicitationUntitledEnumItems,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<Vec<String>>,
}
```

### 与带标题多选枚举的对比

| 特性 | Untitled (无标题) | Titled (带标题) |
|------|------------------|----------------|
| 选项定义 | `enum: string[]` | `anyOf: {const, title}[]` |
| 结构复杂度 | 简单 | 较复杂 |
| 显示值 | 原始枚举值 | 标题（title） |
| 适用场景 | 技术标识符 | 用户-facing 选项 |
| 序列化大小 | 较小 | 较大 |

## 关键代码路径与文件引用

### TypeScript 生成文件
- **文件路径**: `codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationUntitledMultiSelectEnumSchema.ts`

### Rust 源文件
- **文件路径**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**: 5416-5439

### 相关类型定义
- `McpElicitationUntitledEnumItems`: 行 5473-5483
- `McpElicitationArrayType`: 字面量 `"array"`

### 使用场景

1. **McpElicitationMultiSelectEnumSchema** (`codex-rs/app-server-protocol/src/protocol/v2.rs:5411-5414`)
   ```rust
   pub enum McpElicitationMultiSelectEnumSchema {
       Untitled(McpElicitationUntitledMultiSelectEnumSchema),
       Titled(McpElicitationTitledMultiSelectEnumSchema),
   }
   ```

2. **McpElicitationEnumSchema** (`codex-rs/app-server-protocol/src/protocol/v2.rs:5330`)
   - 作为枚举 schema 的多选变体之一

3. **McpElicitationPrimitiveSchema** (`codex-rs/app-server-protocol/src/protocol/v2.rs:5217`)
   - 通过枚举 schema 链式包含

### 序列化示例

```json
{
  "type": "array",
  "title": "Select Categories",
  "description": "Choose one or more categories",
  "minItems": 1,
  "maxItems": 5,
  "items": {
    "type": "string",
    "enum": ["frontend", "backend", "database", "devops", "testing"]
  },
  "default": ["frontend", "backend"]
}
```

## 依赖与外部交互

### 上游依赖
- `McpElicitationArrayType`: 字面量类型 `"array"`
- `McpElicitationUntitledEnumItems`: 无标题枚举项定义
- `McpElicitationStringType`: 用于枚举项类型定义

### 下游消费者
- `McpElicitationMultiSelectEnumSchema`: 包含此类型作为变体
- `McpElicitationEnumSchema`: 作为枚举 schema 的一部分
- `McpElicitationPrimitiveSchema`: 作为基础 schema 类型之一
- TUI 多选渲染组件

### 类型关系图

```
McpElicitationPrimitiveSchema
└── McpElicitationEnumSchema
    └── McpElicitationMultiSelectEnumSchema
        └── McpElicitationUntitledMultiSelectEnumSchema
            └── items: McpElicitationUntitledEnumItems
                └── enum: string[]
```

## 风险、边界与改进建议

### 已知限制
1. **无标签联合**: TypeScript 中使用 `untagged` 联合类型，需要运行时检查来区分 Titled/Untitled
2. **默认值验证**: 没有强制验证 `default` 中的值是否在 `items.enum` 中
3. **空枚举**: `items.enum` 为空数组时，用户无法选择任何选项

### 边界情况
- `minItems` > `maxItems` 时，schema 逻辑矛盾
- `default` 长度不在 `[minItems, maxItems]` 范围内
- `default` 包含不在 `items.enum` 中的值
- `items.enum` 包含重复值

### 改进建议

1. **添加运行时验证**:
   ```rust
   impl McpElicitationUntitledMultiSelectEnumSchema {
       pub fn validate(&self) -> Result<(), ValidationError> {
           // 验证 minItems <= maxItems
           // 验证 default 值都在 items.enum 中
           // 验证 items.enum 不为空
           // 验证 items.enum 无重复值
       }
   }
   ```

2. **支持唯一性约束**:
   ```rust
   pub struct McpElicitationUntitledMultiSelectEnumSchema {
       // ... 现有字段
       #[serde(skip_serializing_if = "Option::is_none")]
       pub unique_items: Option<bool>,  // 新增：是否要求选项唯一（默认 true）
   }
   ```

3. **支持选项排序**:
   ```rust
   pub struct McpElicitationUntitledEnumItems {
       pub type_: McpElicitationStringType,
       pub enum_: Vec<String>,
       pub sort_order: Option<SortOrder>,  // 新增：alphabetical, original, frequency
   }
   ```

4. **支持搜索/过滤提示**:
   ```rust
   pub struct McpElicitationUntitledMultiSelectEnumSchema {
       // ... 现有字段
       pub searchable: Option<bool>,  // 新增：是否启用选项搜索
       pub search_placeholder: Option<String>,  // 新增：搜索框占位符
   }
   ```

### 测试覆盖
- 序列化/反序列化测试在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 的测试模块中
- 建议添加边界情况测试（空 enum、无效默认值、约束冲突等）

### 使用建议
- 适用于选项值为自描述的技术标识符
- 适用于选项数量较少且值本身清晰的场景
- 当需要向非技术用户展示时，优先考虑使用带标题的多选枚举
