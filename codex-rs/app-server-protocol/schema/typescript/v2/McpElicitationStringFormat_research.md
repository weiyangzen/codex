# McpElicitationStringFormat 研究文档

## 1. 场景与职责

`McpElicitationStringFormat` 是 MCP (Model Context Protocol) 表单中字符串字段的格式验证枚举。该类型在系统中承担以下职责：

- **格式约束定义**：定义字符串字段应遵循的特定格式标准
- **数据验证**：为客户端和服务器提供标准化的格式验证规则
- **UI优化**：指导客户端根据格式类型提供适当的输入控件（如日期选择器、邮箱验证等）
- **协议兼容**：遵循 JSON Schema 格式验证规范

典型使用场景包括：
- 邮箱地址输入字段
- URL/URI 输入字段
- 日期或日期时间选择字段
- 需要特定格式验证的文本输入

## 2. 功能点目的

该类型存在的具体目的：

1. **标准化格式**：提供一组预定义的、广泛认可的字符串格式
2. **跨平台验证**：确保客户端和服务器使用相同的验证规则
3. **用户体验优化**：允许客户端根据格式类型提供专门的输入控件和验证反馈
4. **类型安全**：在编译时确保只使用支持的格式值

## 3. 具体技术实现

### 数据结构

```typescript
export type McpElicitationStringFormat = "email" | "uri" | "date" | "date-time";
```

### 格式值说明

| 格式值 | 说明 | 验证规则示例 | 典型UI控件 |
|--------|------|-------------|-----------|
| `"email"` | 电子邮箱地址 | RFC 5322 兼容的邮箱格式 | 邮箱输入框，@符号提示 |
| `"uri"` | URI/URL | RFC 3986 兼容的URI格式 | URL输入框，协议前缀提示 |
| `"date"` | ISO 8601 日期 | `YYYY-MM-DD` 格式 | 日期选择器 |
| `"date-time"` | ISO 8601 日期时间 | `YYYY-MM-DDTHH:mm:ssZ` 格式 | 日期时间选择器 |

### Rust 实现细节

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[ts(rename_all = "kebab-case", export_to = "v2/")]
pub enum McpElicitationStringFormat {
    Email,
    Uri,
    Date,
    DateTime,
}
```

**特性注解说明**：
- `rename_all = "kebab-case"`: 将Rust的PascalCase枚举值序列化为kebab-case格式
  - `Email` → `"email"`
  - `DateTime` → `"date-time"`
- `Copy` trait: 作为小尺寸枚举，支持按值复制而非移动

## 4. 关键代码路径与文件引用

### 主要源文件
- **Rust定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` 行5258-5266
- **TypeScript生成**: `codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationStringFormat.ts`

### 相关类型定义
- `McpElicitationStringSchema`: 使用该类型作为可选的 `format` 字段

### 使用场景
- 在 `McpElicitationStringSchema` 中作为 `format` 字段的类型
- 用于表单中字符串字段的格式约束定义

## 5. 依赖与外部交互

### 导入的类型

无直接导入，这是一个独立的字符串字面量联合类型。

### 依赖关系图

```
McpElicitationStringFormat (enum)
└── (被依赖)
    └── McpElicitationStringSchema.format
        └── McpElicitationPrimitiveSchema::String
            └── McpElicitationSchema.properties
```

### 与JSON Schema的关系

该枚举值直接对应 JSON Schema 的 `format` 关键字支持的标准格式：
- 参考: [JSON Schema Validation - Format](https://json-schema.org/draft/2020-12/json-schema-validation.html#name-defined-formats)

### 外部验证库

在实际应用中，这些格式通常需要配合验证库使用：
- **JavaScript/TypeScript**: `ajv-format`, `validator.js`
- **Rust**: `regex`, `chrono` (用于日期格式)

## 6. 风险、边界与改进建议

### 潜在风险

1. **验证不一致**：不同平台的格式验证实现可能存在差异
2. **时区处理**：`date-time` 格式的时区处理可能在不同系统间不一致
3. **国际化**：`email` 格式的国际化域名(IDN)支持可能不完整

### 边界情况

1. **空字符串**：空字符串是否通过格式验证取决于具体实现
2. **部分匹配**：某些验证器可能只检查格式模式，不验证实际值的有效性（如2月30日）
3. **大小写敏感**：URI格式对大小写的敏感性处理

### 改进建议

1. **扩展格式支持**：考虑添加更多常用格式：
   - `"ipv4"`, `"ipv6"` - IP地址
   - `"hostname"` - 主机名
   - `"uuid"` - UUID
   - `"regex"` - 正则表达式

2. **添加验证示例**：在文档中提供每个格式的有效和无效示例

3. **自定义格式支持**：考虑支持自定义格式模式：
   ```typescript
   format?: McpElicitationStringFormat | { pattern: string; description: string };
   ```

4. **严格模式**：添加严格模式选项，要求格式验证必须在服务器端执行

5. **本地化支持**：对于日期格式，考虑添加本地化显示选项

### 测试建议

- 测试每个格式的有效值和无效值
- 测试边界值（空字符串、极长字符串、特殊字符）
- 验证不同平台间的一致性
- 测试日期时间的时区处理

### 使用示例

```typescript
// 邮箱字段定义
const emailField: McpElicitationStringSchema = {
  type: "string",
  title: "Email Address",
  format: "email",
  description: "Please enter a valid email address"
};

// 日期字段定义
const dateField: McpElicitationStringSchema = {
  type: "string",
  title: "Birth Date",
  format: "date",
  default: "2000-01-01"
};
```
