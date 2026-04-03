# McpElicitationUntitledMultiSelectEnumSchema 研究文档

## 场景与职责

`McpElicitationUntitledMultiSelectEnumSchema` 是 MCP Elicitation 表单中用于定义**无标题多选枚举字段**的类型。与带标题版本不同，它使用简单的字符串数组定义选项，选项值直接作为显示文本。

该类型用于 MCP 服务器需要用户从多个选项中选择**多个值**的场景，且选项值本身就是清晰的描述，如：
- 选择多个编程语言（"rust", "python", "go"）
- 选择多个标签（"bug", "feature", "docs"）
- 选择多个环境（"dev", "staging", "prod"）

## 功能点目的

1. **多选枚举支持**：定义多选复选框/多选列表的数据结构
2. **简洁结构**：使用字符串数组定义选项，无需额外的标题映射
3. **数量限制**：支持设置最小/最大选择数量
4. **默认值支持**：允许指定默认选中的项

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationUntitledMultiSelectEnumSchema = { 
  type: McpElicitationArrayType,      // "array"
  title?: string,                     // 字段标题
  description?: string,               // 字段描述
  minItems?: bigint,                  // 最少选择数量
  maxItems?: bigint,                  // 最多选择数量
  items: McpElicitationUntitledEnumItems,  // 选项定义（字符串枚举）
  default?: Array<string>,            // 默认选中值列表
};
```

### items 字段定义

```typescript
export type McpElicitationUntitledEnumItems = { 
  type: McpElicitationStringType,  // "string"
  enum: Array<string>,             // 可选值列表
};
```

### Rust 定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationUntitledMultiSelectEnumSchema {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationArrayType,  // Array
    pub title: Option<String>,
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

### 序列化格式示例

```json
{
  "type": "array",
  "title": "Programming Languages",
  "description": "Select languages you are proficient in",
  "minItems": 1,
  "maxItems": 3,
  "items": {
    "type": "string",
    "enum": ["rust", "python", "typescript", "go", "java"]
  },
  "default": ["rust"]
}
```

### 与 Titled 版本的核心区别

| 特性 | Untitled（本类型） | Titled |
|------|-------------------|--------|
| 选项定义 | `items.enum` 字符串数组 | `items.anyOf` 对象数组 |
| 选项结构 | 字符串值 | `{const, title}` 对象 |
| 显示方式 | 显示值本身 | 显示 `title` |
| 适用场景 | 值即描述 | 需要友好显示名 |
| 结构复杂度 | 简单 | 较复杂 |

## 关键代码路径与文件引用

### TypeScript 类型定义
- **文件**：`codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationUntitledMultiSelectEnumSchema.ts`
- **生成来源**：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### Rust 源码定义
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- **位置**：行 5416-5439

### 相关类型定义
- `McpElicitationArrayType`（行 5466-5471）：数组类型枚举
- `McpElicitationUntitledEnumItems`（行 5473-5483）：选项定义
- `McpElicitationMultiSelectEnumSchema`（行 5408-5414）：联合类型包装

### 在类型体系中的位置
```
McpElicitationPrimitiveSchema
  └── Enum
        └── McpElicitationEnumSchema
              └── MultiSelect
                    ├── Untitled  <-- 本类型
                    └── Titled
```

## 依赖与外部交互

### 依赖类型
- `McpElicitationArrayType`：数组类型标记（值为 `"array"`）
- `McpElicitationUntitledEnumItems`：选项列表定义

### 与 JSON Schema 的对应

该类型遵循 JSON Schema 的数组类型定义：
- `type: "array"` 表示数组类型
- `items` 定义数组元素的 schema
- `minItems`/`maxItems` 限制数组长度
- `default` 提供默认值

### 验证规则

1. **类型验证**：返回值必须是数组
2. **元素验证**：每个元素必须是字符串且在 `enum` 列表中
3. **数量验证**：数组长度必须在 `minItems` 和 `maxItems` 之间
4. **默认值验证**：`default` 中的每个值必须在 `enum` 列表中

## 风险、边界与改进建议

### 当前限制

1. **仅支持字符串元素**：`items.type` 固定为 `"string"`
2. **无选项描述**：选项值直接显示，无法提供额外说明
3. **无选项禁用**：不能禁用特定选项
4. **国际化困难**：值通常是英文标识符，不易翻译

### 边界情况

1. **minItems > maxItems**：约束冲突时的处理
2. **default 包含无效值**：默认值不在 enum 列表中时的处理
3. **空 enum 列表**：`items.enum: []` 表示无可用选项
4. **重复选择**：是否允许同一个值被选择多次（通常不允许）

### 与 SingleSelect 的对比

| 特性 | MultiSelect（本类型） | SingleSelect |
|------|----------------------|-------------|
| `type` | `"array"` | `"string"` |
| `items` | 有（定义数组元素） | 无 |
| `default` | `Array<string>` | `string` |
| 返回值 | 字符串数组 | 单个字符串 |
| UI 控件 | 多选复选框 | 单选下拉框 |

### 与 Titled 版本的详细对比

| 方面 | Untitled | Titled |
|------|----------|--------|
| **序列化大小** | 较小 | 较大（每个选项是对象）|
| **可读性** | 好（值即描述）| 更好（有友好标题）|
| **灵活性** | 低 | 高 |
| **国际化** | 困难 | 容易 |
| **适用场景** | 技术标识符 | 用户可见选项 |

### 改进建议

1. **添加选项描述**（需要结构变更）：
   如需描述支持，建议使用 Titled 版本

2. **支持选项排序**：
   ```rust
   pub struct McpElicitationUntitledEnumItems {
       pub type_: McpElicitationStringType,
       pub enum_: Vec<String>,
       pub sorted: Option<bool>,  // 新增：是否按字母排序显示
   }
   ```

3. **支持搜索过滤**：
   添加 `searchable: bool` 标记，指示客户端是否应提供搜索功能

4. **弃用路径**：
   对于用户可见的多选，建议优先使用 Titled 版本，Untitled 版本主要用于内部/技术场景

### 使用示例

```rust
use codex_app_server_protocol::{
    McpElicitationUntitledMultiSelectEnumSchema, McpElicitationArrayType,
    McpElicitationUntitledEnumItems, McpElicitationStringType,
};

let schema = McpElicitationUntitledMultiSelectEnumSchema {
    type_: McpElicitationArrayType::Array,
    title: Some("Deployment Environments".to_string()),
    description: Some("Select environments to deploy to".to_string()),
    min_items: Some(1),
    max_items: Some(3),
    items: McpElicitationUntitledEnumItems {
        type_: McpElicitationStringType::String,
        enum_: vec![
            "development".to_string(),
            "staging".to_string(),
            "production".to_string(),
        ],
    },
    default: Some(vec!["development".to_string()]),
};
```

### 客户端渲染建议

对于 Untitled MultiSelect，客户端可以：

1. **复选框组**：
   ```
   [x] development
   [x] staging
   [ ] production
   ```

2. **多选下拉框**：
   - 支持下拉多选
   - 显示选中的值列表

3. **标签输入器**：
   - 类似邮件收件人的标签输入
   - 输入时自动匹配 enum 值

4. **验证提示**：
   - 显示 `minItems`/`maxItems` 约束
   - 如 "请选择 1-3 项"

### 返回值示例

```json
["development", "staging"]
```

### 何时使用

| 场景 | 推荐 | 原因 |
|------|------|------|
| 技术标识符多选 | ✅ Untitled | 简洁，值即描述 |
| 用户可见选项 | ❌ Titled | 需要友好显示名 |
| 内部配置选择 | ✅ Untitled | 简洁高效 |
| 需要国际化 | ❌ Titled | title 可翻译 |
