# McpElicitationTitledSingleSelectEnumSchema 研究文档

## 场景与职责

`McpElicitationTitledSingleSelectEnumSchema` 是 MCP Elicitation 表单中用于定义**带标题的单选枚举字段**的类型。它使用 `oneOf` 结构定义选项，每个选项都有独立的标题（显示文本）和常量值（实际值）。

该类型用于 MCP 服务器需要用户从多个选项中选择**单个值**的场景，且选项需要有友好的显示标题，如：
- 选择操作类型（显示"创建新文件"，值为"create"）
- 选择优先级（显示"高优先级"，值为"high"）
- 选择状态（显示"已完成"，值为"completed"）

## 功能点目的

1. **单选枚举支持**：定义单选下拉框/列表框的数据结构
2. **友好展示**：每个选项有独立的标题，提升用户体验
3. **值与显示分离**：内部值（const）与显示文本（title）分离
4. **默认值支持**：允许指定默认选中项

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationTitledSingleSelectEnumSchema = { 
  type: McpElicitationStringType,     // "string"
  title?: string,                     // 字段标题
  description?: string,               // 字段描述
  oneOf: Array<McpElicitationConstOption>,  // 选项列表
  default?: string,                   // 默认值（对应 const 值）
};
```

### 选项定义

```typescript
export type McpElicitationConstOption = { 
  const: string,   // 选项值（实际提交的值）
  title: string,   // 显示标题（用户看到的文本）
};
```

### 与 Untitled 版本的核心区别

| 特性 | Titled（本类型） | Untitled |
|------|-----------------|----------|
| 选项定义 | `oneOf` 数组 | `enum` 数组 |
| 选项结构 | `{const, title}` 对象 | 字符串值 |
| 显示方式 | 显示 `title` | 显示值本身 |
| 适用场景 | 值与显示文本不同 | 值本身就是描述 |

### Rust 定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationTitledSingleSelectEnumSchema {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationStringType,  // String
    pub title: Option<String>,
    pub description: Option<String>,
    #[serde(rename = "oneOf")]
    #[ts(rename = "oneOf")]
    pub one_of: Vec<McpElicitationConstOption>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<String>,
}
```

### 序列化格式示例

```json
{
  "type": "string",
  "title": "Action",
  "description": "Choose an action to perform",
  "oneOf": [
    { "const": "create", "title": "Create New File" },
    { "const": "update", "title": "Update Existing File" },
    { "const": "delete", "title": "Delete File" }
  ],
  "default": "create"
}
```

### 客户端解析逻辑

```rust
fn parse_single_select_field(
    id: &str,
    schema: McpElicitationSingleSelectEnumSchema,
    required: bool,
) -> Option<McpServerElicitationField> {
    match schema {
        McpElicitationSingleSelectEnumSchema::Titled(schema) => {
            let label = schema.title.unwrap_or_else(|| id.to_string());
            let prompt = schema.description.unwrap_or_else(|| label.clone());
            
            // 查找默认选项索引
            let default_idx = schema.default.as_ref().and_then(|value| {
                schema.one_of.iter().position(|entry| entry.const_.as_str() == value)
            });
            
            // 构建选项列表，使用 title 作为显示标签
            let options = schema.one_of.into_iter().map(|entry| McpServerElicitationOption {
                label: entry.title,
                description: None,
                value: Value::String(entry.const_),
            }).collect();
            
            Some(McpServerElicitationField {
                id: id.to_string(),
                label,
                prompt,
                required,
                input: McpServerElicitationFieldInput::Select { options, default_idx },
            })
        }
        // ...
    }
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- **文件**：`codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationTitledSingleSelectEnumSchema.ts`
- **生成来源**：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### Rust 源码定义
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- **位置**：行 5387-5406

### 相关类型定义
- `McpElicitationStringType`（行 5251-5256）：字符串类型枚举
- `McpElicitationConstOption`（行 5494-5505）：选项定义
- `McpElicitationSingleSelectEnumSchema`（行 5358-5364）：联合类型包装

### 客户端解析实现
- **文件**：`codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs`
- **函数**：`parse_single_select_field`（行 645-674）

### 在类型体系中的位置
```
McpElicitationPrimitiveSchema
  └── Enum
        └── McpElicitationEnumSchema
              ├── SingleSelect
              │     └── McpElicitationSingleSelectEnumSchema
              │           ├── Untitled
              │           └── Titled  <-- 本类型
              ├── MultiSelect
              └── Legacy
```

## 依赖与外部交互

### 依赖类型
- `McpElicitationStringType`：字符串类型标记（值为 `"string"`）
- `McpElicitationConstOption`：选项定义结构

### 与 JSON Schema 的对应

该类型遵循 JSON Schema 的 `oneOf` 模式：
- `oneOf` 表示"匹配其中之一"
- 每个选项是一个包含 `const`（常量）和 `title`（标题）的对象
- `const` 是实际值，`title` 是显示文本

### 与 MultiSelect 的对比

| 特性 | SingleSelect（本类型） | MultiSelect |
|------|----------------------|-------------|
| `type` | `"string"` | `"array"` |
| 返回值 | 单个字符串 | 字符串数组 |
| `default` | `string` | `Array<string>` |
| UI 控件 | 单选下拉框/列表 | 多选复选框/列表 |

## 风险、边界与改进建议

### 当前限制

1. **选项无描述**：`McpElicitationConstOption` 只有 `title` 和 `const`，缺少详细描述字段
2. **无选项禁用**：不支持禁用特定选项
3. **无选项图标**：不支持为选项添加图标
4. **字符串值限制**：`const` 只能是字符串，不支持数字或其他类型

### 边界情况

1. **默认值不存在**：`default` 值不在 `oneOf` 列表中时，客户端应忽略或选择第一个
2. **空选项列表**：`oneOf` 为空数组时的处理
3. **重复 const 值**：多个选项有相同 `const` 值时的处理
4. **空 title**：`title` 为空字符串时的显示回退

### 改进建议

1. **添加选项描述**：
   ```rust
   pub struct McpElicitationConstOption {
       pub const_: String,
       pub title: String,
       pub description: Option<String>,  // 新增：选项详细描述
   }
   ```

2. **支持选项禁用**：
   ```rust
   pub struct McpElicitationConstOption {
       pub const_: String,
       pub title: String,
       pub disabled: Option<bool>,  // 新增：禁用标记
   }
   ```

3. **支持选项图标**：
   ```rust
   pub struct McpElicitationConstOption {
       pub const_: String,
       pub title: String,
       pub icon: Option<String>,  // 新增：图标 URL 或标识符
   }
   ```

4. **支持 optgroup 分组**：
   ```rust
   pub struct McpElicitationOptionGroup {
       pub label: String,
       pub options: Vec<McpElicitationConstOption>,
   }
   ```

### 使用示例

```rust
use codex_app_server_protocol::{
    McpElicitationTitledSingleSelectEnumSchema, McpElicitationStringType,
    McpElicitationConstOption,
};

let schema = McpElicitationTitledSingleSelectEnumSchema {
    type_: McpElicitationStringType::String,
    title: Some("Priority".to_string()),
    description: Some("Select the task priority level".to_string()),
    one_of: vec![
        McpElicitationConstOption {
            const_: "high".to_string(),
            title: "🔴 High Priority".to_string(),
        },
        McpElicitationConstOption {
            const_: "medium".to_string(),
            title: "🟡 Medium Priority".to_string(),
        },
        McpElicitationConstOption {
            const_: "low".to_string(),
            title: "🟢 Low Priority".to_string(),
        },
    ],
    default: Some("medium".to_string()),
};
```

### 客户端渲染建议

对于 Titled SingleSelect，客户端可以：

1. **单选下拉框**：标准 HTML `<select>` 元素，显示 `title`
2. **单选按钮组**：每个选项显示为一个单选按钮，标签为 `title`
3. **卡片选择**：以卡片形式展示选项，显示 `title` 和可选描述
4. **搜索选择**：选项较多时，支持搜索过滤

### 与 Legacy 枚举的对比

| 特性 | Titled（本类型） | Legacy |
|------|-----------------|--------|
| 结构 | `oneOf` | `enum` + `enumNames` |
| 标准性 | 符合 JSON Schema | 自定义扩展 |
| 灵活性 | 高 | 中 |
| 推荐使用 | ✅ 是 | ⚠️ 向后兼容 |

Legacy 类型使用 `enum` 存储值，`enumNames` 存储标题，是旧的实现方式。Titled 类型使用标准的 JSON Schema `oneOf` 结构，是推荐的新实现方式。
