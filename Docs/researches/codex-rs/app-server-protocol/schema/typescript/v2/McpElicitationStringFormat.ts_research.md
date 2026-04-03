# McpElicitationStringFormat.ts 研究文档

## 场景与职责

`McpElicitationStringFormat.ts` 定义了 MCP (Model Context Protocol) 征求表单中字符串字段的格式验证类型。该类型指定了字符串值应遵循的特定格式，如电子邮件、URI、日期等。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **格式验证**: 定义字符串字段的有效格式，用于客户端和服务器端验证
2. **UI 优化**: 为客户端提供提示，可以使用特定的输入控件（如日期选择器、电子邮件输入框）
3. **数据标准化**: 确保用户输入的数据符合预期的格式规范
4. **类型安全**: 在编译时验证格式字符串的有效性

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationStringFormat = 
  | "email"      // 电子邮件地址
  | "uri"        // URI/URL
  | "date"       // 日期 (YYYY-MM-DD)
  | "date-time"; // 日期时间 (ISO 8601)
```

### 格式说明

| 格式值 | JSON Schema 对应 | 说明 | 示例 |
|--------|-----------------|------|------|
| `"email"` | `format: "email"` | 有效的电子邮件地址 | `user@example.com` |
| `"uri"` | `format: "uri"` | 有效的 URI/URL | `https://example.com` |
| `"date"` | `format: "date"` | ISO 8601 日期格式 | `2024-01-15` |
| `"date-time"` | `format: "date-time"` | ISO 8601 日期时间格式 | `2024-01-15T10:30:00Z` |

### 生成来源

该文件由 Rust 枚举通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum McpElicitationStringFormat {
    Email,
    Uri,
    Date,
    DateTime,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义 `McpElicitationStringFormat` Rust 枚举 |
| `codex-rs/core/src/mcp_tool_call.rs` | 处理 MCP 工具调用中的字符串验证 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的表单输入组件
- TUI 的文本输入界面
- 表单验证库

### 相关类型

| 类型 | 说明 |
|------|------|
| `McpElicitationPrimitiveSchema.ts` | 包含 `format` 字段使用此类型 |
| `McpElicitationStringType.ts` | 字符串类型定义 |

## 依赖与外部交互

### 直接依赖

无直接依赖类型，这是一个基础枚举类型。

### 被依赖类型

- `McpElicitationPrimitiveSchema.ts`: 字符串类型的 `format` 字段

### MCP 协议集成

该类型实现了 MCP 规范中的字符串格式验证功能：
1. MCP 服务器定义征求表单，包含带格式的字符串字段
2. 客户端根据 `format` 值选择合适的输入控件和验证规则
3. 用户输入数据时进行实时格式验证
4. 提交前进行最终验证，确保数据符合格式要求

### JSON Schema 对应

这些格式值直接对应 JSON Schema 的 `format` 关键字：
```json
{
  "type": "string",
  "format": "email"
}
```

## 风险、边界与改进建议

### 风险点

1. **客户端验证不一致**: 不同客户端对格式的验证可能不一致
2. **国际化问题**: 日期格式可能因地区而异（虽然 ISO 8601 是标准）
3. **URI 范围过广**: `uri` 格式包括所有 URI 方案，可能需要更具体的限制

### 边界情况

1. **空字符串**: 空字符串是否通过格式验证需要明确定义
2. **大小写敏感**: 电子邮件地址通常不区分大小写，但 URI 路径可能区分
3. **时区处理**: `date-time` 格式涉及时区，需要明确处理规则
4. **部分输入**: 用户输入过程中的部分数据不应触发验证错误

### 改进建议

1. **添加更多格式**:
   - `"hostname"`: 主机名验证
   - `"ipv4"` / `"ipv6"`: IP 地址验证
   - `"uuid"`: UUID 验证
   - `"regex"`: 正则表达式验证
   - `"json-pointer"`: JSON Pointer 验证

2. **自定义格式支持**:
   ```typescript
   export type McpElicitationStringFormat = 
     | "email" 
     | "uri" 
     | "date" 
     | "date-time"
     | { "pattern": string };  // 自定义正则表达式
   ```

3. **验证模式增强**:
   - 支持 `minLength` 和 `maxLength` 与格式一起使用
   - 支持格式特定的选项（如 URI 的 allowedSchemes）

4. **UI 集成**:
   - `"date"` 和 `"date-time"` 应触发日期选择器
   - `"email"` 应使用 `type="email"` 输入框
   - `"uri"` 应使用 `type="url"` 输入框

### 客户端实现建议

```typescript
function getInputType(format: McpElicitationStringFormat): string {
  switch (format) {
    case "email": return "email";
    case "uri": return "url";
    case "date": return "date";
    case "date-time": return "datetime-local";
    default: return "text";
  }
}

function validateFormat(value: string, format: McpElicitationStringFormat): boolean {
  switch (format) {
    case "email":
      return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
    case "uri":
      try { new URL(value); return true; } catch { return false; }
    case "date":
      return /^\d{4}-\d{2}-\d{2}$/.test(value) && !isNaN(Date.parse(value));
    case "date-time":
      return !isNaN(Date.parse(value));
    default:
      return true;
  }
}
```
