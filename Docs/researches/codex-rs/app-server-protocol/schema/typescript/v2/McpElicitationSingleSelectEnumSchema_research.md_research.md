# McpElicitationSingleSelectEnumSchema 研究文档

## 场景与职责

`McpElicitationSingleSelectEnumSchema` 是 MCP Elicitation 表单中用于定义单选枚举字段的类型。它支持两种呈现方式：

1. **Untitled（无标题）**：简单的字符串枚举列表，选项值直接显示
2. **Titled（带标题）**：每个选项有独立的标题和常量值，使用 `oneOf` 结构

该类型用于 MCP 服务器需要用户从多个选项中选择单个值的场景，如选择操作类型、确认级别等。

## 功能点目的

1. **单选枚举支持**：定义单选下拉框/列表框的数据结构
2. **灵活展示**：支持简单值列表和带描述的选项卡片两种展示模式
3. **默认值支持**：允许指定默认选中项
4. **MCP 协议兼容**：与 MCP 规范的枚举 schema 格式保持一致

## 具体技术实现

### 数据结构

```typescript
// TypeScript 联合类型
export type McpElicitationSingleSelectEnumSchema = 
  | McpElicitationUntitledSingleSelectEnumSchema 
  | McpElicitationTitledSingleSelectEnumSchema;
```

#### Untitled 变体（简单枚举）
```typescript
export type McpElicitationUntitledSingleSelectEnumSchema = { 
  type: McpElicitationStringType,  // "string"
  title?: string,                  // 字段标题
  description?: string,            // 字段描述
  enum: Array<string>,             // 选项值列表
  default?: string,                // 默认值
};
```

#### Titled 变体（带标题选项）
```typescript
export type McpElicitationTitledSingleSelectEnumSchema = { 
  type: McpElicitationStringType,  // "string"
  title?: string,                  // 字段标题
  description?: string,            // 字段描述
  oneOf: Array<McpElicitationConstOption>,  // 选项列表
  default?: string,                // 默认值（对应 const 值）
};
```

### 选项定义
```typescript
export type McpElicitationConstOption = { 
  const: string,   // 选项值
  title: string,   // 显示标题
};
```

### 关键流程

1. **Schema 解析**（TUI 客户端）：
   ```rust
   fn parse_single_select_field(
       id: &str,
       schema: McpElicitationSingleSelectEnumSchema,
       required: bool,
   ) -> Option<McpServerElicitationField> {
       match schema {
           McpElicitationSingleSelectEnumSchema::Untitled(schema) => {
               // 将 enum 值直接作为选项标签
               let options = schema.enum_.into_iter().map(|value| 
                   McpServerElicitationOption {
                       label: value.clone(),
                       description: None,
                       value: Value::String(value),
                   }
               ).collect();
           }
           McpElicitationSingleSelectEnumSchema::Titled(schema) => {
               // 使用 oneOf 中的 title 作为选项标签
               let options = schema.one_of.into_iter().map(|entry| 
                   McpServerElicitationOption {
                       label: entry.title,
                       description: None,
                       value: Value::String(entry.const_),
                   }
               ).collect();
           }
       }
   }
   ```

2. **默认值处理**：
   - Untitled：在 `enum` 列表中查找 `default` 值的位置
   - Titled：在 `oneOf` 中查找 `const` 等于 `default` 的选项位置

## 关键代码路径与文件引用

### TypeScript 类型定义
- **文件**：`codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationSingleSelectEnumSchema.ts`
- **生成来源**：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### Rust 源码定义
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `McpElicitationSingleSelectEnumSchema` 联合类型（行 5358-5364）
  - `McpElicitationUntitledSingleSelectEnumSchema`（行 5366-5385）
  - `McpElicitationTitledSingleSelectEnumSchema`（行 5387-5406）
  - `McpElicitationConstOption`（行 5494-5505）

### 客户端解析实现
- **文件**：`codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs`
  - `parse_single_select_field` 函数（行 612-675）

### 测试
- **集成测试**：`codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs`

## 依赖与外部交互

### 依赖类型
- `McpElicitationUntitledSingleSelectEnumSchema`：无标题枚举变体
- `McpElicitationTitledSingleSelectEnumSchema`：带标题枚举变体

### 相关类型
- `McpElicitationStringType`：字符串类型标记
- `McpElicitationConstOption`：带标题的选项定义

### 在枚举体系中的位置
```
McpElicitationPrimitiveSchema
  └── Enum
        └── McpElicitationEnumSchema
              ├── SingleSelect
              │     └── McpElicitationSingleSelectEnumSchema
              │           ├── Untitled
              │           └── Titled
              ├── MultiSelect
              └── Legacy
```

## 风险、边界与改进建议

### 当前限制
1. **仅支持字符串值**：枚举值必须是字符串，不支持数字或其他类型
2. **无嵌套选项**：不支持层级结构的选项（如分组选择）
3. **Titled 变体无描述**：`McpElicitationConstOption` 只有 `title` 和 `const`，没有 `description` 字段

### 边界情况
1. **空选项列表**：当 `enum` 或 `oneOf` 为空时，客户端应如何处理
2. **默认值不存在**：`default` 值不在选项列表中时，应忽略还是报错
3. **重复值**：`enum` 列表中有重复值时的处理逻辑

### 与 MultiSelect 的对比
| 特性 | SingleSelect | MultiSelect |
|------|-------------|-------------|
| 值类型 | `string` | `array` |
| 默认值 | `string` | `Array<string>` |
| 返回格式 | 单个字符串 | 字符串数组 |
| items 字段 | 无 | 有（定义数组元素）|

### 改进建议
1. **添加选项描述**：为 `McpElicitationConstOption` 添加可选的 `description` 字段
2. **支持禁用选项**：添加 `disabled` 标记支持禁用特定选项
3. **支持图标**：为选项添加图标支持，提升 UI 表现力
4. **搜索过滤**：对于大量选项，支持客户端搜索过滤功能

### 使用示例

```rust
// Untitled 示例
let untitled_schema = McpElicitationUntitledSingleSelectEnumSchema {
    type_: McpElicitationStringType::String,
    title: Some("Action".to_string()),
    description: Some("Choose an action".to_string()),
    enum_: vec!["create".to_string(), "update".to_string(), "delete".to_string()],
    default: Some("create".to_string()),
};

// Titled 示例
let titled_schema = McpElicitationTitledSingleSelectEnumSchema {
    type_: McpElicitationStringType::String,
    title: Some("Priority".to_string()),
    description: Some("Select task priority".to_string()),
    one_of: vec![
        McpElicitationConstOption { const_: "high".to_string(), title: "High Priority".to_string() },
        McpElicitationConstOption { const_: "medium".to_string(), title: "Medium Priority".to_string() },
        McpElicitationConstOption { const_: "low".to_string(), title: "Low Priority".to_string() },
    ],
    default: Some("medium".to_string()),
};
```
