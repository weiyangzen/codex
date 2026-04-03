# McpElicitationStringSchema.ts Research Document

## 场景与职责

`McpElicitationStringSchema` 是 MCP (Model Context Protocol) 表单验证系统中的字符串类型字段定义。它用于描述 MCP 服务器在用户交互过程中需要收集的字符串输入的验证规则和展示属性。

在 Codex 应用服务器与 MCP 服务器的交互中，当 MCP 服务器需要向用户请求额外信息（elicitation）时，会使用表单模式（form mode）来定义所需的输入字段。该类型专门用于定义字符串输入字段的 JSON Schema 约束，确保用户输入符合预期的格式、长度和内容要求。

## 功能点目的

1. **输入验证**：定义字符串字段的验证规则，包括最小/最大长度、格式要求（如 email、URI、日期等）
2. **用户界面渲染**：提供 `title` 和 `description` 字段用于生成用户友好的表单标签和提示文本
3. **默认值支持**：允许设置默认值，提升用户体验
4. **类型安全**：通过 TypeScript 类型系统确保字符串字段定义的完整性

## 具体技术实现

### 数据结构定义

```typescript
import type { McpElicitationStringFormat } from "./McpElicitationStringFormat";
import type { McpElicitationStringType } from "./McpElicitationStringType";

export type McpElicitationStringSchema = { 
  type: McpElicitationStringType, 
  title?: string, 
  description?: string, 
  minLength?: number, 
  maxLength?: number, 
  format?: McpElicitationStringFormat, 
  default?: string, 
};
```

### 关键字段说明

| 字段 | 类型 | 可选 | 说明 |
|------|------|------|------|
| `type` | `McpElicitationStringType` | 否 | 固定为 `"string"`，标识这是一个字符串类型字段 |
| `title` | `string` | 是 | 字段的显示标题，用于表单标签 |
| `description` | `string` | 是 | 字段的详细描述，用于表单提示或帮助文本 |
| `minLength` | `number` | 是 | 字符串最小长度约束（JSON Schema 标准） |
| `maxLength` | `number` | 是 | 字符串最大长度约束（JSON Schema 标准） |
| `format` | `McpElicitationStringFormat` | 是 | 字符串格式验证，支持 `"email"`、`"uri"`、`"date"`、`"date-time"` |
| `default` | `string` | 是 | 字段的默认值 |

### Rust 源定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationStringSchema {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationStringType,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub min_length: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub max_length: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub format: Option<McpElicitationStringFormat>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<String>,
}
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationStringSchema.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 5227-5249)
- **相关类型**:
  - `McpElicitationStringType.ts` - 字符串类型标识（值为 `"string"`）
  - `McpElicitationStringFormat.ts` - 字符串格式枚举
  - `McpElicitationPrimitiveSchema.ts` - 原始类型联合类型，包含本类型

## 依赖与外部交互

### 上游依赖

1. **McpElicitationPrimitiveSchema**: 本类型是 `McpElicitationPrimitiveSchema` 联合类型的成员之一，与布尔、数字、枚举类型并列
2. **McpElicitationSchema**: 作为 `properties` 字典的值类型，构成完整的表单 Schema

### 下游使用

1. **表单渲染**: 前端根据此 Schema 生成对应的字符串输入控件（文本框、邮箱输入框等）
2. **输入验证**: 客户端和服务器端使用这些约束验证用户输入
3. **MCP 协议兼容**: 与 MCP 2025-11-25 规范的 `ElicitRequestFormParams` 保持一致

## 风险、边界与改进建议

### 潜在风险

1. **长度约束溢出**: `minLength` 和 `maxLength` 使用 `number` 类型，在 JavaScript 中可能存在精度问题（虽然对长度值影响不大）
2. **格式验证一致性**: `format` 字段的验证逻辑需要在客户端和服务器端保持一致，否则可能导致验证通过但服务器拒绝的情况

### 边界情况

1. **空字符串处理**: 当 `minLength` 为 0 或未设置时，空字符串是否被接受需要明确定义
2. **Unicode 长度计算**: 不同环境对 Unicode 字符的长度计算可能不同（如 emoji 算作 1 个还是 2 个字符）
3. **默认值与必填字段**: 如果字段在 `required` 列表中且有 `default`，应明确行为（通常默认值可满足必填要求）

### 改进建议

1. **添加 pattern 支持**: 考虑添加正则表达式 `pattern` 字段，支持更灵活的字符串验证
2. **多行文本支持**: 添加 `multiline` 或 `textarea` 提示，区分单行和多行文本输入
3. **敏感信息标记**: 添加 `sensitive` 或 `secret` 标记，用于密码、API Key 等敏感字段的掩码显示
4. **占位符文本**: 添加 `placeholder` 字段，提供输入提示而非默认值
