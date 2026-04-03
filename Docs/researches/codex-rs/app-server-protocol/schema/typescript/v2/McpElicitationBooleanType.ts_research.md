# McpElicitationBooleanType 研究文档

## 1. 场景与职责

`McpElicitationBooleanType` 是 App-Server Protocol v2 中的枚举类型，定义了 MCP（Model Context Protocol）参数征求中的布尔类型标识。该类型是 MCP 参数征求系统的基础类型标识之一，用于明确标识布尔类型的参数。

**主要使用场景：**
- MCP 服务器参数征求表单中的布尔类型字段
- JSON Schema 类型定义
- 参数验证和序列化
- 客户端表单渲染类型判断

## 2. 功能点目的

该类型的核心目的是为 MCP 参数征求系统提供类型安全的布尔类型标识：

1. **类型标识**：明确标识字段为布尔类型
2. **Schema 定义**：用于构建 JSON Schema 的 `type` 字段
3. **序列化控制**：确保类型信息正确序列化为 `"boolean"`

这个设计使得：
- 客户端可以正确渲染布尔输入控件（复选框、开关）
- 参数验证可以检查布尔类型
- 类型信息在序列化过程中保持一致

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type McpElicitationBooleanType = "boolean";
```

### Rust 源定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "lowercase")]
#[ts(export_to = "v2/")]
pub enum McpElicitationBooleanType {
    Boolean,
}
```

### 枚举值说明

| 枚举值 | 字符串表示 | 说明 |
|--------|-----------|------|
| `Boolean` | `"boolean"` | 布尔类型 |

### 特性注解

- `#[serde(rename_all = "lowercase")]`：序列化为小写字符串 `"boolean"`
- `#[ts(export_to = "v2/")]`：TypeScript 类型导出到 `v2/` 目录
- 单值枚举，用于类型安全

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 5318-5323 行

### 相关类型

- `McpElicitationBooleanSchema`：布尔类型 Schema（第 5300-5316 行）
- `McpElicitationObjectType`：对象类型标识（第 5207-5212 行）
- `McpElicitationStringType`：字符串类型标识（第 5251-5256 行）
- `McpElicitationNumberType`：数字类型标识（第 5292-5298 行）
- `McpElicitationArrayType`：数组类型标识（第 5466-5471 行）

### 使用场景

该类型通常用于：
- `McpElicitationBooleanSchema` 中的 `type_` 字段
- 布尔类型参数的 Schema 定义

## 5. 依赖与外部交互

### 序列化行为

- 使用 `serde` 序列化为小写字符串 `"boolean"`
- TypeScript 中表示为字符串字面量类型
- 支持 JSON Schema 生成

### 与 JSON Schema 的关系

该类型对应 JSON Schema 中的 `"boolean"` 类型，用于：
- 定义布尔类型的参数
- 构建表单 Schema
- 参数验证

## 6. 风险、边界与改进建议

### 潜在风险

1. **单值枚举开销**：虽然是单值枚举，但 Rust 类型系统开销仍然存在
2. **扩展性有限**：如果未来需要更多布尔类型变体，需要修改枚举定义
3. **序列化一致性**：必须确保始终序列化为 `"boolean"`

### 边界情况

- 布尔值与字符串 `"true"`/`"false"` 的区分
- 非布尔值（如 `1`/`0`）的转换
- 三态布尔（`true`/`false`/`null`）的支持

### 改进建议

1. **合并类型枚举**：
   - 考虑将所有类型标识合并为一个 `McpElicitationType` 枚举
   - 减少类型数量，简化 API

2. **添加元数据**：
   - 考虑添加类型相关的元数据
   - 支持类型转换规则

3. **验证增强**：
   - 添加严格的类型验证
   - 支持类型转换错误处理

### 与相关类型的对比

| 类型 | 用途 | 序列化值 |
|------|------|----------|
| `McpElicitationBooleanType` | 布尔类型 | `"boolean"` |
| `McpElicitationObjectType` | 对象类型 | `"object"` |
| `McpElicitationStringType` | 字符串类型 | `"string"` |
| `McpElicitationNumberType` | 数字类型 | `"number"` / `"integer"` |
| `McpElicitationArrayType` | 数组类型 | `"array"` |

### 使用示例

```rust
// 在 Boolean Schema 中使用
pub struct McpElicitationBooleanSchema {
    pub type_: McpElicitationBooleanType,  // 始终为 Boolean
    pub title: Option<String>,
    pub description: Option<String>,
    pub default: Option<bool>,
}
```

### 设计说明

使用单值枚举而非直接使用字符串有以下原因：
1. **类型安全**：编译时检查类型正确性
2. **可扩展性**：未来可以添加更多变体（如 `TriState`）
3. **一致性**：与其他类型标识保持一致的 API 风格
4. **自动生成**：支持 `ts-rs` 自动生成 TypeScript 类型

### JSON Schema 对应

在 JSON Schema 中对应：
```json
{
  "type": "boolean"
}
```
