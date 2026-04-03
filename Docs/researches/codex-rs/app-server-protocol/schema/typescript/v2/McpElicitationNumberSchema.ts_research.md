# McpElicitationNumberSchema 研究文档

## 1. 场景与职责

`McpElicitationNumberSchema` 是 App-Server Protocol v2 中的结构体类型，定义了 MCP（Model Context Protocol）参数征求中的数字类型字段的 JSON Schema。该类型用于描述数字类型参数（包括整数和浮点数）的元数据，支持表单渲染、验证和约束。

**主要使用场景：**
- MCP 服务器参数征求表单中的数字输入字段
- 生成 JSON Schema 用于客户端表单验证
- 提供数值范围约束（最小值、最大值）
- 提供字段的标题、描述和默认值
- 客户端动态表单渲染

## 2. 功能点目的

该类型的核心目的是为数字类型参数提供完整的 Schema 描述：

1. **类型标识**：明确标识字段为数字类型（`number` 或 `integer`）
2. **元数据**：提供标题、描述等展示信息
3. **范围约束**：支持设置最小值和最大值
4. **默认值**：支持设置默认值
5. **验证**：支持基于 Schema 的数值验证

这个设计使得：
- 客户端可以正确渲染数字输入控件
- 用户可以理解参数的用途和有效范围
- 表单可以预填充默认值
- 输入值可以被正确验证

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type McpElicitationNumberSchema = { 
  type: McpElicitationNumberType, 
  title: string | null, 
  description: string | null, 
  minimum: number | null, 
  maximum: number | null, 
  default: number | null, 
};
```

### Rust 源定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationNumberSchema {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationNumberType,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub minimum: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub maximum: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<f64>,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `McpElicitationNumberType` | 类型标识，`"number"` 或 `"integer"` |
| `title` | `string \| null` | 字段标题，用于表单标签 |
| `description` | `string \| null` | 字段描述，用于帮助文本 |
| `minimum` | `number \| null` | 最小值约束（包含） |
| `maximum` | `number \| null` | 最大值约束（包含） |
| `default` | `number \| null` | 默认值 |

### 特性注解

- `#[serde(rename_all = "camelCase")]`：字段序列化为 camelCase 格式
- `#[serde(deny_unknown_fields)]`：拒绝未知字段，严格模式
- `#[serde(skip_serializing_if = "Option::is_none")]`：值为 null 时不序列化
- `#[ts(optional)]`：TypeScript 中标记为可选
- `#[ts(export_to = "v2/")]`：TypeScript 类型导出到 `v2/` 目录

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 5268-5290 行

### 相关类型

- `McpElicitationNumberType`：数字类型标识（第 5292-5298 行）
- `McpElicitationStringSchema`：字符串类型 Schema（第 5224-5249 行）
- `McpElicitationBooleanSchema`：布尔类型 Schema（第 5300-5316 行）
- `McpElicitationPrimitiveSchema`：原始类型联合（第 5214-5222 行）

### 使用场景

该类型是 `McpElicitationPrimitiveSchema` 联合类型的变体之一，用于：
- 数字类型参数的 Schema 定义
- 表单字段的元数据描述
- 数值范围约束

## 5. 依赖与外部交互

### 导入类型

| 类型 | 来源 | 说明 |
|------|------|------|
| `McpElicitationNumberType` | 同文件定义 | 数字类型标识枚举 |

### 序列化行为

- 使用 `serde` 进行 JSON 序列化/反序列化
- 字段名自动转换为 camelCase
- 可选字段在值为 null 时不包含在 JSON 中
- TypeScript 中可选字段表示为 `T | null`

## 6. 风险、边界与改进建议

### 潜在风险

1. **严格模式**：`deny_unknown_fields` 可能导致向前兼容性问题
2. **浮点精度**：`f64` 类型可能存在精度问题
3. **范围验证**：客户端和服务端的验证逻辑可能不一致
4. **整数溢出**：大整数可能超出 `f64` 精确表示范围

### 边界情况

- `minimum` > `maximum` 的无效范围
- 默认值超出范围约束
- 负数的处理
- 零值和空值的区分
- 极大或极小的数值

### 改进建议

1. **添加更多约束**：
   - `exclusiveMinimum`：不包含的最小值
   - `exclusiveMaximum`：不包含的最大值
   - `multipleOf`：倍数约束
   - `precision`：小数位数限制

2. **UI 增强**：
   - `ui:widget`：指定 UI 控件类型（数字输入框、滑块、步进器）
   - `ui:step`：步进值
   - `ui:unit`：单位显示

3. **验证增强**：
   - 客户端和服务端验证逻辑统一
   - 添加自定义验证规则
   - 支持验证错误消息定制

4. **类型细化**：
   - 区分 `i32`、`i64`、`f32`、`f64` 等不同数值类型
   - 支持大整数（BigInt）
   - 支持十进制数（Decimal）

### 与相关类型的对比

| 类型 | 用途 | 特有字段 |
|------|------|----------|
| `McpElicitationNumberSchema` | 数字类型 | `minimum`, `maximum` |
| `McpElicitationStringSchema` | 字符串类型 | `minLength`, `maxLength`, `format` |
| `McpElicitationBooleanSchema` | 布尔类型 | `default: boolean` |

### 使用示例

```json
{
  "type": "integer",
  "title": "端口号",
  "description": "服务器监听的端口号",
  "minimum": 1,
  "maximum": 65535,
  "default": 8080
}
```

### JSON Schema 兼容性

该类型遵循 JSON Schema 规范：
- `type`: 类型标识（`"number"` 或 `"integer"`）
- `title`: 短标题
- `description`: 详细描述
- `minimum`/`maximum`: 数值范围（包含边界）
- `default`: 默认值

这些字段都是标准的 JSON Schema 属性，可以被标准 JSON Schema 验证器识别。
