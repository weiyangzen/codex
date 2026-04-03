# McpElicitationPrimitiveSchema 研究文档

## 1. 场景与职责

`McpElicitationPrimitiveSchema` 是 App-Server Protocol v2 中的联合类型（untagged enum），定义了 MCP（Model Context Protocol）参数征求中的原始类型 Schema。该类型是对象属性的基础类型，支持字符串、数字、布尔和枚举四种原始类型。

**主要使用场景：**
- MCP 服务器参数征求表单中的对象属性定义
- 构建复杂的嵌套参数结构
- 动态表单 Schema 生成
- 客户端表单渲染类型分发

## 2. 功能点目的

该类型的核心目的是为对象属性提供统一的原始类型 Schema：

1. **枚举类型** (`Enum`)：单选或多选枚举
2. **字符串类型** (`String`)：文本输入
3. **数字类型** (`Number`)：数值输入
4. **布尔类型** (`Boolean`)：开关/复选框

这个设计使得：
- 对象可以包含多种类型的属性
- 客户端可以根据类型渲染不同的输入控件
- Schema 可以灵活地描述复杂的参数结构
- 类型系统保证属性类型的正确性

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type McpElicitationPrimitiveSchema = 
  | { type: "enum", ...McpElicitationEnumSchema }
  | { type: "string", ...McpElicitationStringSchema }
  | { type: "number", ...McpElicitationNumberSchema }
  | { type: "boolean", ...McpElicitationBooleanSchema };
```

### Rust 源定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(untagged)]
#[ts(export_to = "v2/")]
pub enum McpElicitationPrimitiveSchema {
    Enum(McpElicitationEnumSchema),
    String(McpElicitationStringSchema),
    Number(McpElicitationNumberSchema),
    Boolean(McpElicitationBooleanSchema),
}
```

### 变体说明

| 变体 | 包装类型 | 说明 |
|------|----------|------|
| `Enum` | `McpElicitationEnumSchema` | 枚举类型（单选/多选） |
| `String` | `McpElicitationStringSchema` | 字符串类型 |
| `Number` | `McpElicitationNumberSchema` | 数字类型 |
| `Boolean` | `McpElicitationBooleanSchema` | 布尔类型 |

### 特性注解

- `#[serde(untagged)]`：无标签联合类型，根据内容自动反序列化
- `#[ts(export_to = "v2/")]`：TypeScript 类型导出到 `v2/` 目录
- 联合类型在 TypeScript 中表示为联合类型

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 5214-5222 行

### 相关类型

- `McpElicitationEnumSchema`：枚举类型 Schema（第 5325-5332 行）
- `McpElicitationStringSchema`：字符串类型 Schema（第 5224-5249 行）
- `McpElicitationNumberSchema`：数字类型 Schema（第 5268-5290 行）
- `McpElicitationBooleanSchema`：布尔类型 Schema（第 5300-5316 行）
- `McpElicitationObjectSchema`：对象类型 Schema（第 5188-5205 行）

### 使用场景

该类型通常用于：
- `McpElicitationObjectSchema.properties`：对象的属性定义
- 构建复杂的参数表单

## 5. 依赖与外部交互

### 导入类型

| 类型 | 来源 | 说明 |
|------|------|------|
| `McpElicitationEnumSchema` | 同文件定义 | 枚举类型 Schema 联合 |
| `McpElicitationStringSchema` | 同文件定义 | 字符串类型 Schema |
| `McpElicitationNumberSchema` | 同文件定义 | 数字类型 Schema |
| `McpElicitationBooleanSchema` | 同文件定义 | 布尔类型 Schema |

### 序列化行为

- 使用 `serde(untagged)` 进行无标签序列化
- 根据变体内容自动确定类型
- TypeScript 中表示为联合类型

### 无标签联合的序列化

由于使用 `untagged`，序列化后的 JSON 不包含类型标签：
```json
// Enum 变体
{ "type": "string", "oneOf": [...] }

// String 变体
{ "type": "string", "title": "..." }

// Number 变体
{ "type": "integer", "minimum": 0 }

// Boolean 变体
{ "type": "boolean", "default": true }
```

反序列化时根据 JSON 内容推断类型。

## 6. 风险、边界与改进建议

### 潜在风险

1. **反序列化歧义**：无标签联合在某些情况下可能产生歧义
2. **类型推断失败**：如果 JSON 内容不符合任何变体，反序列化会失败
3. **向前兼容性**：添加新变体可能影响现有反序列化逻辑
4. **性能开销**：类型推断需要尝试所有变体

### 边界情况

- 空对象 `{}` 的处理
- 同时匹配多个变体的歧义情况
- 未知字段的处理（依赖子类型的 `deny_unknown_fields`）
- 嵌套联合类型的复杂性

### 改进建议

1. **添加类型标签**：
   - 考虑改为 tagged union（如 `#[serde(tag = "type")]`）
   - 提高反序列化的可靠性和性能
   - 更好的错误信息

2. **扩展类型支持**：
   - 添加 `Array` 变体支持数组属性
   - 添加 `Null` 变体支持可空属性
   - 添加 `Any` 变体支持任意类型

3. **验证增强**：
   - 添加跨属性的验证规则
   - 支持条件验证
   - 实现自定义验证器

4. **UI 优化**：
   - 添加 UI 元数据支持
   - 支持动态控件切换
   - 实现属性分组

### 与相关类型的关系

```
McpElicitationSchema
├── McpElicitationObjectSchema
│   └── properties: BTreeMap<String, McpElicitationPrimitiveSchema>
│       ├── Enum (McpElicitationEnumSchema)
│       │   ├── SingleSelect
│       │   └── MultiSelect
│       ├── String (McpElicitationStringSchema)
│       ├── Number (McpElicitationNumberSchema)
│       └── Boolean (McpElicitationBooleanSchema)
└── ...
```

### 使用示例

```rust
// 构建对象属性
let mut properties = BTreeMap::new();

// 字符串属性
properties.insert(
    "name".to_string(),
    McpElicitationPrimitiveSchema::String(McpElicitationStringSchema {
        type_: McpElicitationStringType::String,
        title: Some("名称".to_string()),
        ..Default::default()
    })
);

// 数字属性
properties.insert(
    "port".to_string(),
    McpElicitationPrimitiveSchema::Number(McpElicitationNumberSchema {
        type_: McpElicitationNumberType::Integer,
        minimum: Some(1.0),
        maximum: Some(65535.0),
        ..Default::default()
    })
);

// 布尔属性
properties.insert(
    "enabled".to_string(),
    McpElicitationPrimitiveSchema::Boolean(McpElicitationBooleanSchema {
        type_: McpElicitationBooleanType::Boolean,
        default: Some(true),
        ..Default::default()
    })
);
```

### 设计说明

使用无标签联合（untagged）的原因：
1. **简洁性**：序列化后的 JSON 更简洁
2. **JSON Schema 兼容**：直接对应 JSON Schema 的结构
3. **灵活性**：允许子类型定义自己的类型标识

潜在问题：
- 反序列化性能较低（需要尝试所有变体）
- 错误信息不够明确
- 类型歧义时需要额外处理

### 替代方案

考虑改为 tagged union：
```rust
#[serde(tag = "primitiveType")]
pub enum McpElicitationPrimitiveSchema {
    Enum { schema: McpElicitationEnumSchema },
    String { schema: McpElicitationStringSchema },
    // ...
}
```

这样可以提高反序列化的可靠性，但会增加序列化后的 JSON 大小。
