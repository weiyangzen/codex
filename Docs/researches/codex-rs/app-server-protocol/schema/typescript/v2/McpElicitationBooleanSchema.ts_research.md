# McpElicitationBooleanSchema 研究文档

## 1. 场景与职责

`McpElicitationBooleanSchema` 是 App-Server Protocol v2 中的结构体类型，定义了 MCP（Model Context Protocol）参数征求中的布尔类型字段的 JSON Schema。该类型用于描述布尔类型参数的元数据，支持表单渲染和验证。

**主要使用场景：**
- MCP 服务器参数征求表单中的布尔类型字段（复选框、开关）
- 生成 JSON Schema 用于客户端表单验证
- 提供字段的标题、描述和默认值
- 客户端动态表单渲染

## 2. 功能点目的

该类型的核心目的是为布尔类型参数提供完整的 Schema 描述：

1. **类型标识**：明确标识字段为布尔类型
2. **元数据**：提供标题、描述等展示信息
3. **默认值**：支持设置默认值
4. **验证**：支持基于 Schema 的验证

这个设计使得：
- 客户端可以正确渲染布尔输入控件（复选框、开关）
- 用户可以理解参数的用途
- 表单可以预填充默认值
- 参数值可以被正确验证

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type McpElicitationBooleanSchema = { 
  type: McpElicitationBooleanType, 
  title: string | null, 
  description: string | null, 
  default: boolean | null, 
};
```

### Rust 源定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationBooleanSchema {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationBooleanType,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<bool>,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `McpElicitationBooleanType` | 类型标识，始终为 `"boolean"` |
| `title` | `string \| null` | 字段标题，用于表单标签 |
| `description` | `string \| null` | 字段描述，用于帮助文本 |
| `default` | `boolean \| null` | 默认值 |

### 特性注解

- `#[serde(rename_all = "camelCase")]`：字段序列化为 camelCase 格式
- `#[serde(deny_unknown_fields)]`：拒绝未知字段，严格模式
- `#[serde(skip_serializing_if = "Option::is_none")]`：值为 null 时不序列化
- `#[ts(optional)]`：TypeScript 中标记为可选
- `#[ts(export_to = "v2/")]`：TypeScript 类型导出到 `v2/` 目录

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 5300-5316 行

### 相关类型

- `McpElicitationBooleanType`：布尔类型标识（第 5318-5323 行）
- `McpElicitationStringSchema`：字符串类型 Schema（第 5224-5249 行）
- `McpElicitationNumberSchema`：数字类型 Schema（第 5268-5290 行）
- `McpElicitationPrimitiveSchema`：原始类型联合（第 5214-5222 行）

### 使用场景

该类型是 `McpElicitationPrimitiveSchema` 联合类型的变体之一，用于：
- 布尔类型参数的 Schema 定义
- 表单字段的元数据描述

## 5. 依赖与外部交互

### 导入类型

| 类型 | 来源 | 说明 |
|------|------|------|
| `McpElicitationBooleanType` | 同文件定义 | 布尔类型标识枚举 |

### 序列化行为

- 使用 `serde` 进行 JSON 序列化/反序列化
- 字段名自动转换为 camelCase
- 可选字段在值为 null 时不包含在 JSON 中
- TypeScript 中可选字段表示为 `T | null`

## 6. 风险、边界与改进建议

### 潜在风险

1. **严格模式**：`deny_unknown_fields` 可能导致向前兼容性问题
2. **默认值处理**：客户端需要正确处理 `null` 默认值
3. **布尔语义**：需要明确 `true`/`false` 的具体含义

### 边界情况

- 所有字段都为 `null` 时的最小化 Schema
- 默认值为 `false` 与无默认值的区别
- 长描述文本的截断和展示

### 改进建议

1. **添加更多属性**：
   - `readOnly`：只读字段
   - `writeOnly`：只写字段（如密码确认）
   - `deprecated`：标记为弃用

2. **UI 提示**：
   - `ui:widget`：指定 UI 控件类型（复选框、开关）
   - `ui:help`：额外的帮助信息
   - `ui:placeholder`：占位符文本

3. **验证增强**：
   - `const`：固定值约束
   - `enum`：枚举值约束（对于布尔类型可能多余）

4. **国际化**：
   - 支持多语言标题和描述
   - 添加 `titleKey` 和 `descriptionKey` 用于 i18n

### 与相关类型的对比

| 类型 | 用途 | 特有字段 |
|------|------|----------|
| `McpElicitationBooleanSchema` | 布尔类型 | `default: boolean` |
| `McpElicitationStringSchema` | 字符串类型 | `minLength`, `maxLength`, `format` |
| `McpElicitationNumberSchema` | 数字类型 | `minimum`, `maximum` |

### 使用示例

```json
{
  "type": "boolean",
  "title": "启用调试模式",
  "description": "开启后将输出详细的调试信息",
  "default": false
}
```

### JSON Schema 兼容性

该类型遵循 JSON Schema 规范：
- `type`: 类型标识
- `title`: 短标题
- `description`: 详细描述
- `default`: 默认值

这些字段都是标准的 JSON Schema 属性，可以被标准 JSON Schema 验证器识别。
