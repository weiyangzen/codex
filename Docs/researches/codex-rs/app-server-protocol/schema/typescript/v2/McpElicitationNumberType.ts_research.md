# McpElicitationNumberType 研究文档

## 1. 场景与职责

`McpElicitationNumberType` 是 App-Server Protocol v2 中的枚举类型，定义了 MCP（Model Context Protocol）参数征求中的数字类型标识。该类型区分整数和浮点数两种数值类型，用于精确的参数类型定义。

**主要使用场景：**
- MCP 服务器参数征求表单中的数字类型字段
- JSON Schema 类型定义
- 参数验证和序列化
- 客户端表单渲染类型判断

## 2. 功能点目的

该类型的核心目的是为 MCP 参数征求系统提供精确的数字类型标识：

1. **整数类型** (`integer`)：表示没有小数部分的数字
2. **浮点数类型** (`number`)：表示可能包含小数部分的数字

这个设计使得：
- 客户端可以根据类型选择合适的输入控件
- 验证可以区分整数和浮点数
- 类型信息在序列化过程中保持一致
- 符合 JSON Schema 的数值类型定义

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type McpElicitationNumberType = "number" | "integer";
```

### Rust 源定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "lowercase")]
#[ts(export_to = "v2/")]
pub enum McpElicitationNumberType {
    Number,
    Integer,
}
```

### 枚举值说明

| 枚举值 | 字符串表示 | 说明 |
|--------|-----------|------|
| `Number` | `"number"` | 浮点数类型（JSON Schema 标准） |
| `Integer` | `"integer"` | 整数类型（JSON Schema 标准） |

### 特性注解

- `#[serde(rename_all = "lowercase")]`：序列化为小写字符串
- `#[ts(export_to = "v2/")]`：TypeScript 类型导出到 `v2/` 目录
- 双值枚举，覆盖 JSON Schema 的数值类型

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 5292-5298 行

### 相关类型

- `McpElicitationNumberSchema`：数字类型 Schema（第 5268-5290 行）
- `McpElicitationObjectType`：对象类型标识（第 5207-5212 行）
- `McpElicitationStringType`：字符串类型标识（第 5251-5256 行）
- `McpElicitationBooleanType`：布尔类型标识（第 5318-5323 行）
- `McpElicitationArrayType`：数组类型标识（第 5466-5471 行）

### 使用场景

该类型通常用于：
- `McpElicitationNumberSchema` 中的 `type_` 字段
- 数字类型参数的 Schema 定义

## 5. 依赖与外部交互

### 序列化行为

- 使用 `serde` 序列化为小写字符串（`"number"` 或 `"integer"`）
- TypeScript 中表示为字符串字面量联合类型
- 支持 JSON Schema 生成

### 与 JSON Schema 的关系

该类型对应 JSON Schema 中的数值类型：
- `"number"`：任何数值，包括整数和浮点数
- `"integer"`：没有小数部分的数值

注意：在 JSON Schema 中，`"integer"` 是 `"number"` 的子类型。

## 6. 风险、边界与改进建议

### 潜在风险

1. **类型混淆**：客户端可能不区分 `number` 和 `integer`
2. **浮点精度**：`number` 类型的精度问题
3. **大整数**：JavaScript 的整数精度限制（2^53 - 1）
4. **序列化一致性**：必须确保正确映射到 JSON Schema 类型

### 边界情况

- 整数值但类型为 `number`
- 小数值但类型为 `integer`（验证失败）
- 极大或极小的数值
- NaN 和 Infinity 的处理

### 改进建议

1. **添加更多数值类型**：
   - `positiveInteger`：正整数
   - `nonNegativeInteger`：非负整数
   - `double`：双精度浮点数
   - `float`：单精度浮点数

2. **精度控制**：
   - 添加 `precision` 字段指定小数位数
   - 支持大整数类型（BigInt）
   - 支持十进制类型（Decimal）

3. **验证增强**：
   - 严格的类型验证
   - 数值范围验证
   - 格式验证（如货币、百分比）

4. **UI 提示**：
   - 根据类型选择合适的输入控件
   - 显示类型提示给用户
   - 自动格式化输入

### 与相关类型的对比

| 类型 | 用途 | 序列化值 |
|------|------|----------|
| `McpElicitationNumberType` | 数字类型 | `"number"`, `"integer"` |
| `McpElicitationObjectType` | 对象类型 | `"object"` |
| `McpElicitationStringType` | 字符串类型 | `"string"` |
| `McpElicitationBooleanType` | 布尔类型 | `"boolean"` |
| `McpElicitationArrayType` | 数组类型 | `"array"` |

### 使用示例

```rust
// 端口号（整数）
let port_schema = McpElicitationNumberSchema {
    type_: McpElicitationNumberType::Integer,
    title: Some("端口号".to_string()),
    minimum: Some(1.0),
    maximum: Some(65535.0),
    default: Some(8080.0),
    description: None,
};

// 温度参数（浮点数）
let temperature_schema = McpElicitationNumberSchema {
    type_: McpElicitationNumberType::Number,
    title: Some("温度".to_string()),
    minimum: Some(0.0),
    maximum: Some(2.0),
    default: Some(1.0),
    description: Some("控制输出的随机性".to_string()),
};
```

### JSON Schema 对应

在 JSON Schema 中对应：
```json
// 整数
{
  "type": "integer"
}

// 浮点数
{
  "type": "number"
}
```

### 设计说明

使用双值枚举而非直接使用字符串有以下原因：
1. **类型安全**：编译时检查类型正确性
2. **可扩展性**：未来可以添加更多数值类型变体
3. **一致性**：与其他类型标识保持一致的 API 风格
4. **自动生成**：支持 `ts-rs` 自动生成 TypeScript 类型
5. **JSON Schema 兼容**：直接对应 JSON Schema 的数值类型
