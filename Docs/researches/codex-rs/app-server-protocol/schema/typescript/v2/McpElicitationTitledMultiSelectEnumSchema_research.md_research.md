# McpElicitationTitledMultiSelectEnumSchema 研究文档

## 场景与职责

`McpElicitationTitledMultiSelectEnumSchema` 是 MCP Elicitation 表单中用于定义**带标题的多选枚举字段**的类型。与无标题版本不同，它使用 `oneOf` 结构定义选项，每个选项都有独立的标题和常量值。

该类型用于 MCP 服务器需要用户从多个选项中选择**多个值**的场景，且每个选项需要有友好的显示标题，如：
- 选择多个权限
- 选择多个标签
- 选择多个功能特性

## 功能点目的

1. **多选枚举支持**：定义多选复选框/多选列表的数据结构
2. **友好展示**：每个选项有独立的标题，提升用户体验
3. **数量限制**：支持设置最小/最大选择数量
4. **默认值支持**：允许指定默认选中的项

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationTitledMultiSelectEnumSchema = { 
  type: McpElicitationArrayType,      // "array"
  title?: string,                     // 字段标题
  description?: string,               // 字段描述
  minItems?: bigint,                  // 最少选择数量
  maxItems?: bigint,                  // 最多选择数量
  items: McpElicitationTitledEnumItems,  // 选项定义（使用 oneOf）
  default?: Array<string>,            // 默认选中值列表
};
```

### 选项定义

```typescript
export type McpElicitationTitledEnumItems = { 
  anyOf: Array<McpElicitationConstOption>,  // 选项列表
};

export type McpElicitationConstOption = { 
  const: string,   // 选项值
  title: string,   // 显示标题
};
```

### 与 Untitled 版本的区别

| 特性 | Titled（本类型） | Untitled |
|------|-----------------|----------|
| 选项定义 | `items.anyOf` | `items.enum` |
| 选项结构 | `{const, title}` | 字符串值 |
| 显示方式 | 显示标题 | 显示值本身 |
| 适用场景 | 需要友好显示名 | 值本身就是描述 |

### Rust 定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationTitledMultiSelectEnumSchema {
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
    pub items: McpElicitationTitledEnumItems,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<Vec<String>>,
}
```

### 序列化格式示例

```json
{
  "type": "array",
  "title": "Select Permissions",
  "description": "Choose the permissions to grant",
  "minItems": 1,
  "maxItems": 3,
  "items": {
    "anyOf": [
      { "const": "read", "title": "Read Access" },
      { "const": "write", "title": "Write Access" },
      { "const": "delete", "title": "Delete Access" },
      { "const": "admin", "title": "Admin Access" }
    ]
  },
  "default": ["read"]
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- **文件**：`codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationTitledMultiSelectEnumSchema.ts`
- **生成来源**：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### Rust 源码定义
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- **位置**：行 5441-5464

### 相关类型定义
- `McpElicitationArrayType`（行 5466-5471）：数组类型枚举
- `McpElicitationTitledEnumItems`（行 5485-5492）：带标题选项列表
- `McpElicitationConstOption`（行 5494-5505）：单个选项定义

### 在枚举体系中的位置
```
McpElicitationPrimitiveSchema
  └── Enum
        └── McpElicitationEnumSchema
              ├── SingleSelect
              │     ├── Untitled
              │     └── Titled
              └── MultiSelect
                    ├── Untitled
                    └── Titled  <-- 本类型
```

## 依赖与外部交互

### 依赖类型
- `McpElicitationArrayType`：数组类型标记（值为 `"array"`）
- `McpElicitationTitledEnumItems`：选项列表容器
- `McpElicitationConstOption`：单个选项定义

### 与 SingleSelect 的对比

| 特性 | MultiSelect（本类型） | SingleSelect |
|------|----------------------|--------------|
| `type` | `"array"` | `"string"` |
| `items` | 有（定义数组元素） | 无 |
| `default` | `Array<string>` | `string` |
| 返回值 | 字符串数组 | 单个字符串 |
| UI 控件 | 多选复选框/列表 | 单选下拉框/列表 |

### 验证规则

1. **minItems**：选中的选项数量不能少于该值
2. **maxItems**：选中的选项数量不能超过该值
3. **default**：所有默认值必须在选项列表中存在

## 风险、边界与改进建议

### 当前限制

1. **选项无描述**：`McpElicitationConstOption` 只有 `title` 和 `const`，缺少详细描述
2. **无选项禁用**：不支持禁用特定选项
3. **无分组支持**：不支持选项分组（如 `<optgroup>`）
4. **anyOf/oneOf 混用**：序列化使用 `anyOf`，但语义上更接近 `oneOf`

### 边界情况

1. **空默认值**：`default: []` 与 `default: null` 的区别
2. **minItems = 0**：是否允许不选任何项
3. **重复值**：默认值列表中有重复值时的处理
4. **选项数量限制**：大量选项时的性能考虑

### 改进建议

1. **添加选项描述**：
   ```rust
   pub struct McpElicitationConstOption {
       pub const_: String,
       pub title: String,
       pub description: Option<String>,  // 新增
   }
   ```

2. **支持选项禁用**：
   ```rust
   pub struct McpElicitationConstOption {
       pub const_: String,
       pub title: String,
       pub disabled: Option<bool>,  // 新增
   }
   ```

3. **支持选项分组**：
   ```rust
   pub struct McpElicitationOptionGroup {
       pub label: String,
       pub options: Vec<McpElicitationConstOption>,
   }
   ```

4. **统一 anyOf/oneOf**：
   当前代码中 `McpElicitationTitledEnumItems` 使用 `anyOf`，但 `McpElicitationTitledSingleSelectEnumSchema` 使用 `oneOf`。建议统一语义。

### 使用示例

```rust
use codex_app_server_protocol::{
    McpElicitationTitledMultiSelectEnumSchema, McpElicitationArrayType,
    McpElicitationTitledEnumItems, McpElicitationConstOption,
};

let schema = McpElicitationTitledMultiSelectEnumSchema {
    type_: McpElicitationArrayType::Array,
    title: Some("Notification Preferences".to_string()),
    description: Some("Select how you want to be notified".to_string()),
    min_items: Some(1),
    max_items: Some(3),
    items: McpElicitationTitledEnumItems {
        any_of: vec![
            McpElicitationConstOption {
                const_: "email".to_string(),
                title: "Email Notifications".to_string(),
            },
            McpElicitationConstOption {
                const_: "sms".to_string(),
                title: "SMS Notifications".to_string(),
            },
            McpElicitationConstOption {
                const_: "push".to_string(),
                title: "Push Notifications".to_string(),
            },
            McpElicitationConstOption {
                const_: "slack".to_string(),
                title: "Slack Notifications".to_string(),
            },
        ],
    },
    default: Some(vec!["email".to_string()]),
};
```

### 客户端渲染建议

对于 Titled MultiSelect，客户端可以：

1. **复选框组**：每个选项显示为一个复选框，标签显示 `title`
2. **多选下拉框**：支持下拉多选，显示选中的 `title` 列表
3. **标签选择器**：类似邮件收件人的标签输入体验
4. **验证提示**：显示 `minItems`/`maxItems` 约束，如 "请选择 1-3 项"
