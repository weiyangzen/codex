# McpElicitationTitledMultiSelectEnumSchema 研究文档

## 场景与职责

`McpElicitationTitledMultiSelectEnumSchema` 是 MCP Elicitation 系统中用于定义带标题的多选枚举字段的 schema 类型。它允许用户从预定义选项中选择多个值，每个选项包含常量值和显示标题。

与无标题的多选枚举相比，该类型提供了更丰富的选项描述，适用于需要向用户展示友好选项名称的场景。

## 功能点目的

1. **多选枚举支持**: 为 MCP 表单提供多选字段的类型定义
2. **带标题选项**: 每个选项包含 `const`（值）和 `title`（显示标题）
3. **数组类型**: 使用 JSON Schema 数组类型表示多选结果
4. **约束支持**: 支持 `minItems` 和 `maxItems` 限制选择数量

## 具体技术实现

### 数据结构定义

```typescript
export type McpElicitationTitledMultiSelectEnumSchema = { 
  type: McpElicitationArrayType,      // "array"
  title?: string, 
  description?: string, 
  minItems?: bigint, 
  maxItems?: bigint, 
  items: McpElicitationTitledEnumItems, 
  default?: Array<string>, 
};
```

### 带标题的枚举项定义

```typescript
export type McpElicitationTitledEnumItems = { 
  anyOf: Array<McpElicitationConstOption>, 
};

export type McpElicitationConstOption = { 
  const: string,  // 选项值
  title: string,  // 显示标题
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationTitledMultiSelectEnumSchema {
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
    pub items: McpElicitationTitledEnumItems,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<Vec<String>>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationTitledEnumItems {
    #[serde(rename = "anyOf", alias = "oneOf")]
    #[ts(rename = "anyOf")]
    pub any_of: Vec<McpElicitationConstOption>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationConstOption {
    #[serde(rename = "const")]
    #[ts(rename = "const")]
    pub const_: String,
    pub title: String,
}
```

## 关键代码路径与文件引用

### TypeScript 生成文件
- **文件路径**: `codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationTitledMultiSelectEnumSchema.ts`

### Rust 源文件
- **文件路径**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**: 5441-5464

### 相关类型定义
- `McpElicitationTitledEnumItems`: 行 5488-5492
- `McpElicitationConstOption`: 行 5494-5502

### 使用场景

1. **McpElicitationMultiSelectEnumSchema** (`codex-rs/app-server-protocol/src/protocol/v2.rs:5411-5414`)
   - 作为多选枚举的带标题变体

2. **McpElicitationEnumSchema** (`codex-rs/app-server-protocol/src/protocol/v2.rs:5330`)
   - 包含在枚举 schema 联合类型中

### 序列化示例

```json
{
  "type": "array",
  "title": "Select Features",
  "description": "Choose the features you want to enable",
  "minItems": 1,
  "maxItems": 3,
  "items": {
    "anyOf": [
      { "const": "feature_a", "title": "Feature A - Auto-completion" },
      { "const": "feature_b", "title": "Feature B - Syntax Highlighting" },
      { "const": "feature_c", "title": "Feature C - Code Formatting" },
      { "const": "feature_d", "title": "Feature D - Linting" }
    ]
  },
  "default": ["feature_a", "feature_b"]
}
```

## 依赖与外部交互

### 上游依赖
- `McpElicitationArrayType`: 字面量类型 `"array"`
- `McpElicitationTitledEnumItems`: 带标题的枚举项容器
- `McpElicitationConstOption`: 常量选项定义

### 下游消费者
- `McpElicitationMultiSelectEnumSchema`: 包含此类型作为变体
- `McpElicitationEnumSchema`: 作为枚举 schema 的一部分
- TUI 多选渲染组件

### 与无标题多选枚举的对比

| 特性 | Titled (带标题) | Untitled (无标题) |
|------|----------------|------------------|
| 选项定义 | `anyOf` + `const/title` | `enum` 数组 |
| 显示友好 | ✅ 有标题 | ❌ 仅原始值 |
| 适用场景 | 用户-facing 选项 | 内部/技术选项 |
| 默认值 | `string[]` | `string[]` |

## 风险、边界与改进建议

### 已知限制
1. **anyOf/oneOf 别名**: Rust 端使用 `alias = "oneOf"` 支持两种序列化形式，但 TypeScript 仅暴露 `anyOf`
2. **默认值验证**: 没有强制验证 `default` 中的值是否在 `anyOf` 中
3. **空数组**: `anyOf` 为空时，用户无法选择任何选项

### 边界情况
- `minItems` > `maxItems` 时，schema 逻辑矛盾
- `default` 长度不在 `[minItems, maxItems]` 范围内
- 重复的 `const` 值可能导致选择歧义

### 改进建议
1. **添加运行时验证**:
   ```rust
   impl McpElicitationTitledMultiSelectEnumSchema {
       pub fn validate(&self) -> Result<(), ValidationError> {
           // 验证 minItems <= maxItems
           // 验证 default 值有效
           // 验证 anyOf 不为空
       }
   }
   ```

2. **支持选项描述**:
   ```rust
   pub struct McpElicitationConstOption {
       pub const_: String,
       pub title: String,
       pub description: Option<String>,  // 新增
   }
   ```

3. **支持选项禁用状态**:
   ```rust
   pub struct McpElicitationConstOption {
       pub const_: String,
       pub title: String,
       pub disabled: Option<bool>,  // 新增
   }
   ```

4. **支持选项分组**:
   ```rust
   pub struct McpElicitationOptionGroup {
       pub title: String,
       pub options: Vec<McpElicitationConstOption>,
   }
   ```

### 测试覆盖
- 序列化/反序列化测试在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 的测试模块中
- 建议添加边界情况测试（空 anyOf、无效默认值等）
