# McpElicitationUntitledEnumItems 研究文档

## 场景与职责

`McpElicitationUntitledEnumItems` 是 MCP Elicitation 表单中用于定义**无标题枚举选项列表**的类型。它是 `McpElicitationUntitledMultiSelectEnumSchema` 的 `items` 字段类型，定义了多选枚举中每个选项的值类型。

该类型用于多选枚举场景，其中选项值本身就是描述，不需要额外的显示标题，如：
- 选择多个标签（标签名即值）
- 选择多个类别（类别名即值）
- 选择多个权限标识符

## 功能点目的

1. **定义数组元素类型**：指定多选枚举数组中每个元素的类型
2. **值即描述**：选项值直接显示，无需额外的标题映射
3. **类型安全**：确保数组元素符合预期的字符串枚举类型
4. **简化结构**：相比 Titled 版本，结构更简单直接

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationUntitledEnumItems = { 
  type: McpElicitationStringType,  // "string"
  enum: Array<string>,             // 可选值列表
};
```

### 在 MultiSelect Schema 中的使用

```typescript
export type McpElicitationUntitledMultiSelectEnumSchema = { 
  type: McpElicitationArrayType,      // "array"
  title?: string,
  description?: string,
  minItems?: bigint,
  maxItems?: bigint,
  items: McpElicitationUntitledEnumItems,  // <-- 本类型
  default?: Array<string>,
};
```

### Rust 定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationUntitledEnumItems {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationStringType,  // String
    #[serde(rename = "enum")]
    #[ts(rename = "enum")]
    pub enum_: Vec<String>,
}
```

### 完整序列化示例

```json
{
  "type": "array",
  "title": "Select Tags",
  "description": "Choose tags for this item",
  "minItems": 1,
  "maxItems": 5,
  "items": {
    "type": "string",
    "enum": ["bug", "feature", "docs", "test", "refactor"]
  },
  "default": ["feature"]
}
```

### 与 Titled 版本的对比

| 特性 | Untitled（本类型） | Titled |
|------|-------------------|--------|
| 结构 | `{type, enum}` | `{anyOf: [...]}` |
| 选项定义 | 字符串数组 | 对象数组 `{const, title}` |
| 显示方式 | 显示值本身 | 显示 `title` |
| 适用场景 | 值即描述 | 需要友好显示名 |
| 复杂度 | 简单 | 较复杂 |

## 关键代码路径与文件引用

### TypeScript 类型定义
- **文件**：`codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationUntitledEnumItems.ts`
- **生成来源**：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### Rust 源码定义
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- **位置**：行 5473-5483

### 相关类型定义
- `McpElicitationStringType`（行 5251-5256）：字符串类型枚举
- `McpElicitationUntitledMultiSelectEnumSchema`（行 5416-5439）：使用本类型作为 `items`
- `McpElicitationArrayType`（行 5466-5471）：数组类型标记

### 在类型体系中的位置
```
McpElicitationPrimitiveSchema
  └── Enum
        └── McpElicitationEnumSchema
              └── MultiSelect
                    ├── Untitled
                    │     └── items: McpElicitationUntitledEnumItems  <-- 本类型
                    └── Titled
                          └── items: McpElicitationTitledEnumItems
```

## 依赖与外部交互

### 依赖类型
- `McpElicitationStringType`：字符串类型标记（值为 `"string"`）

### 与 JSON Schema 的对应

该类型遵循 JSON Schema 对数组元素类型的定义：
- `items` 字段定义数组中每个元素的 schema
- `type: "string"` 指定元素为字符串类型
- `enum` 限制字符串的允许值

### 验证语义

```json
{
  "items": {
    "type": "string",
    "enum": ["a", "b", "c"]
  }
}
```

表示：
- 数组的每个元素必须是字符串
- 每个字符串值必须是 `"a"`、`"b"` 或 `"c"` 之一

## 风险、边界与改进建议

### 当前限制

1. **仅支持字符串**：`type` 固定为 `McpElicitationStringType::String`，不支持其他类型
2. **无描述支持**：选项值直接显示，无法提供额外说明
3. **无禁用支持**：不能禁用特定选项
4. **值即显示**：当值不够友好时，用户体验较差

### 边界情况

1. **空 enum 数组**：`enum: []` 表示不允许任何值，实际意义不大
2. **重复值**：`enum` 数组中有重复值时的处理
3. **大小写敏感**：字符串匹配是大小写敏感的
4. **空字符串**：`enum` 包含空字符串 `""` 的合法性

### 与 TitledEnumItems 的详细对比

| 方面 | UntitledEnumItems | TitledEnumItems |
|------|-------------------|-----------------|
| **结构** | `{"type": "string", "enum": [...]}` | `{"anyOf": [{"const": ..., "title": ...}]}` |
| **选项数量** | 容易统计 | 需要数数组长度 |
| **查找选项** | 直接在数组中查找 | 遍历对象数组 |
| **默认值验证** | 检查是否在 enum 中 | 检查是否匹配某个 const |
| **显示文本** | 值本身 | title 字段 |
| **国际化** | 困难（值通常是英文） | 容易（title 可翻译） |

### 改进建议

1. **添加选项描述**（需要结构变更）：
   当前结构较简单，如需添加描述，建议使用 Titled 版本

2. **支持正则匹配**：
   ```rust
   pub struct McpElicitationUntitledEnumItems {
       pub type_: McpElicitationStringType,
       pub enum_: Option<Vec<String>>,  // 变为可选
       pub pattern: Option<String>,     // 新增：正则模式
   }
   ```

3. **支持动态选项**：
   添加 `dynamic: bool` 标记，表示选项列表由服务器动态提供

4. **弃用建议**：
   对于需要友好显示的场景，建议优先使用 Titled 版本，Untitled 版本仅用于内部标识符选择

### 使用示例

```rust
use codex_app_server_protocol::{
    McpElicitationUntitledEnumItems, McpElicitationStringType,
    McpElicitationUntitledMultiSelectEnumSchema, McpElicitationArrayType,
};

// 定义 items
let items = McpElicitationUntitledEnumItems {
    type_: McpElicitationStringType::String,
    enum_: vec![
        "rust".to_string(),
        "python".to_string(),
        "typescript".to_string(),
        "go".to_string(),
    ],
};

// 在 MultiSelect schema 中使用
let schema = McpElicitationUntitledMultiSelectEnumSchema {
    type_: McpElicitationArrayType::Array,
    title: Some("Programming Languages".to_string()),
    description: Some("Select languages you know".to_string()),
    min_items: Some(1),
    max_items: Some(3),
    items,
    default: Some(vec!["rust".to_string()]),
};
```

### 客户端处理逻辑

对于使用 `McpElicitationUntitledEnumItems` 的多选字段，客户端应：

1. **渲染复选框组**：
   ```
   [x] rust
   [ ] python
   [x] typescript
   [ ] go
   ```

2. **验证选择数量**：
   - 检查选中的数量 >= `minItems`
   - 检查选中的数量 <= `maxItems`

3. **验证值合法性**：
   - 确保每个选中的值都在 `enum` 列表中

4. **序列化返回值**：
   ```json
   ["rust", "typescript"]
   ```

### 何时使用 Untitled vs Titled

| 场景 | 推荐类型 | 原因 |
|------|---------|------|
| 技术标识符选择 | Untitled | 值本身就是准确的描述 |
| 用户可见选项 | Titled | 需要友好的显示文本 |
| 内部状态码 | Untitled | 简洁，无需额外映射 |
| 多语言应用 | Titled | title 可翻译 |
| API 参数选择 | Untitled | 参数名即值 |
