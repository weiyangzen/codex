# McpElicitationTitledSingleSelectEnumSchema 研究文档

## 1. 场景与职责

`McpElicitationTitledSingleSelectEnumSchema` 是 MCP (Model Context Protocol) 表单中单选枚举字段的Schema定义，支持带标题的选项。该类型在系统中承担以下职责：

- **单选枚举定义**：定义表单中单选下拉框或单选按钮组的结构
- **带标签选项支持**：支持选项具有显示标签（title）和内部值（const）的区分
- **UI渲染指导**：为客户端提供足够的信息来渲染带标签的单选控件
- **数据验证**：确保用户选择的值在预定义的有效选项范围内

典型使用场景包括：
- 表单中需要用户从多个选项中选择一个的场景
- 选项需要有友好的显示标签（如显示"启用"，实际值为"enabled"）
- 选项需要额外描述信息的场景

## 2. 功能点目的

该类型存在的具体目的：

1. **用户体验优化**：通过 `oneOf` 和 `title` 提供人类可读的选项标签
2. **值标签分离**：允许内部值（如"en"）和显示标签（如"English"）分离
3. **JSON Schema兼容**：使用标准的 `oneOf` 和 `const` 关键字
4. **单选语义明确**：专门用于单选场景，区别于多选枚举

## 3. 具体技术实现

### 数据结构

```typescript
export type McpElicitationTitledSingleSelectEnumSchema = {
  type: McpElicitationStringType,      // 固定为 "string"
  title?: string,                      // 字段标题
  description?: string,                // 字段描述
  oneOf: Array<McpElicitationConstOption>, // 带标签的选项数组
  default?: string,                    // 默认值
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | `McpElicitationStringType` | 是 | 固定值为 `"string"`，表示这是一个字符串类型的字段 |
| `title` | `string` | 否 | 字段的显示标题 |
| `description` | `string` | 否 | 字段的详细描述 |
| `oneOf` | `McpElicitationConstOption[]` | 是 | 选项数组，每个选项包含 `const`（值）和 `title`（标签） |
| `default` | `string` | 否 | 默认选中的选项值 |

### Rust 实现细节

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationTitledSingleSelectEnumSchema {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationStringType,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub description: Option<String>,
    #[serde(rename = "oneOf")]
    #[ts(rename = "oneOf")]
    pub one_of: Vec<McpElicitationConstOption>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<String>,
}
```

**特性注解说明**：
- `deny_unknown_fields`: 拒绝未知字段，确保严格的Schema验证
- `skip_serializing_if = "Option::is_none"`: 可选字段在值为None时不序列化
- `rename = "oneOf"`: 将Rust的snake_case字段名映射为camelCase

### McpElicitationConstOption 结构

```rust
pub struct McpElicitationConstOption {
    pub const_: String,  // 实际的选项值
    pub title: String,   // 显示的选项标签
}
```

## 4. 关键代码路径与文件引用

### 主要源文件
- **Rust定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` 行5387-5406
- **TypeScript生成**: `codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationTitledSingleSelectEnumSchema.ts`

### 相关类型定义
- `McpElicitationStringType`: 字符串类型枚举（固定值为 `String`）
- `McpElicitationConstOption`: 带常量的选项定义
- `McpElicitationSingleSelectEnumSchema`: 单选枚举的联合类型

### 使用场景
- 在 `McpElicitationEnumSchema` 中作为 `SingleSelect` 变体的 `Titled` 变体
- 用于表单中需要单选且选项带标签的字段

## 5. 依赖与外部交互

### 导入的类型

```typescript
import type { McpElicitationConstOption } from "./McpElicitationConstOption";
import type { McpElicitationStringType } from "./McpElicitationStringType";
```

### 依赖关系图

```
McpElicitationTitledSingleSelectEnumSchema
├── McpElicitationStringType (enum: String)
└── McpElicitationConstOption[]
    ├── const: string (值)
    └── title: string (标签)

(被依赖)
└── McpElicitationSingleSelectEnumSchema::Titled
    └── McpElicitationEnumSchema::SingleSelect
```

### 与JSON Schema的关系

该类型遵循 JSON Schema 的 `oneOf` 和 `const` 规范：
- `oneOf` - 表示值必须是其中一个选项
- `const` - 表示固定的常量值
- 这种模式是 JSON Schema 中实现带标签枚举的标准方式

参考: [JSON Schema - const](https://json-schema.org/understanding-json-schema/reference/generic.html#constant-values)

## 6. 风险、边界与改进建议

### 潜在风险

1. **空选项数组**：`oneOf` 为空数组时，表单将无法选择任何值
2. **重复选项值**：`oneOf` 中可能存在重复的 `const` 值
3. **默认值验证**：`default` 值应该存在于 `oneOf` 选项中，但当前没有运行时验证
4. **标签缺失**：`McpElicitationConstOption` 的 `title` 字段是必填的，但可能为空字符串

### 边界情况

1. **单个选项**：`oneOf` 只有一个选项时，实际上用户没有选择余地
2. **空默认值**：`default` 为 `undefined` 表示没有默认选择
3. **无效默认值**：`default` 值不在 `oneOf` 中，可能导致验证失败

### 改进建议

1. **添加验证逻辑**：在Rust端添加运行时验证，确保：
   - `oneOf` 不为空
   - `oneOf` 中的 `const` 值不重复
   - `default` 值存在于 `oneOf` 中（如果设置了默认值）
   - 每个选项都有非空的 `title`

2. **TypeScript类型优化**：
   ```typescript
   // 建议：添加类型守卫
   export function isValidTitledSingleSelect(
     schema: McpElicitationTitledSingleSelectEnumSchema
   ): boolean {
     return schema.oneOf.length > 0 && 
            schema.oneOf.every(opt => opt.const && opt.title) &&
            (schema.default === undefined || 
             schema.oneOf.some(opt => opt.const === schema.default));
   }
   ```

3. **文档完善**：提供更多使用示例，包括：
   - 基本单选场景
   - 带默认值的场景
   - 选项分组（如果支持）

4. **考虑添加**：
   - `description` 到 `McpElicitationConstOption`，为每个选项提供额外描述
   - `disabled` 标记，允许某些选项默认禁用

5. **与Untitled变体的选择指南**：
   - 当选项值本身就是人类可读时，使用 Untitled 变体
   - 当需要值标签分离时，使用 Titled 变体

### 测试建议

- 测试选项数组的各种长度（0、1、多个）
- 测试默认值与选项的匹配
- 测试重复选项值的处理
- 验证序列化/反序列化的一致性

### 使用示例

```typescript
// 带标题的单选字段
const languageField: McpElicitationTitledSingleSelectEnumSchema = {
  type: "string",
  title: "Preferred Language",
  description: "Select your preferred language",
  oneOf: [
    { const: "en", title: "English" },
    { const: "zh", title: "中文" },
    { const: "ja", title: "日本語" },
    { const: "es", title: "Español" }
  ],
  default: "en"
};

// 无默认值的单选字段
const themeField: McpElicitationTitledSingleSelectEnumSchema = {
  type: "string",
  title: "Theme",
  oneOf: [
    { const: "light", title: "Light Mode" },
    { const: "dark", title: "Dark Mode" },
    { const: "auto", title: "Auto (System)" }
  ]
};
```
