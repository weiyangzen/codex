# McpElicitationStringFormat 研究文档

## 场景与职责

`McpElicitationStringFormat` 是 MCP Elicitation 表单中用于定义字符串字段格式的枚举类型。它指定了字符串输入应遵循的格式规范，用于客户端进行输入验证和专门的输入控件渲染。

该类型用于需要特定格式输入的场景，如：
- 电子邮件地址输入
- URL/URI 输入
- 日期选择
- 日期时间选择

## 功能点目的

1. **输入验证**：为字符串字段提供格式验证规则
2. **UI 优化**：根据格式类型渲染专门的输入控件（如日期选择器）
3. **数据标准化**：确保用户输入符合预期的格式规范
4. **MCP 协议兼容**：与 JSON Schema 的 `format` 规范保持一致

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationStringFormat = "email" | "uri" | "date" | "date-time";
```

### 支持的格式

| 格式值 | 说明 | 典型 UI 控件 |
|--------|------|-------------|
| `email` | 电子邮件地址 | 邮箱输入框，带 @ 验证 |
| `uri` | URI/URL | URL 输入框，带协议验证 |
| `date` | ISO 8601 日期 (YYYY-MM-DD) | 日期选择器 |
| `date-time` | ISO 8601 日期时间 | 日期时间选择器 |

### 在 String Schema 中的使用

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationStringSchema {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationStringType,  // "string"
    pub title: Option<String>,
    pub description: Option<String>,
    pub min_length: Option<u32>,
    pub max_length: Option<u32>,
    pub format: Option<McpElicitationStringFormat>,  // 格式约束
    pub default: Option<String>,
}
```

### Rust 枚举定义

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

注意：Rust 中使用 PascalCase 枚举名，但通过 `#[serde(rename_all = "kebab-case")]` 序列化为 kebab-case（如 `date-time`）。

## 关键代码路径与文件引用

### TypeScript 类型定义
- **文件**：`codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationStringFormat.ts`
- **内容**：`export type McpElicitationStringFormat = "email" | "uri" | "date" | "date-time";`

### Rust 源码定义
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- **位置**：行 5258-5266

### 关联类型
- `McpElicitationStringSchema`（行 5227-5249）：包含 `format` 字段
- `McpElicitationStringType`（行 5251-5256）：字符串类型标记

### 使用示例位置
- **测试文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 7282-7288
  ```rust
  McpElicitationPrimitiveSchema::String(McpElicitationStringSchema {
      type_: McpElicitationStringType::String,
      title: Some("Email".to_string()),
      description: Some("Your email address".to_string()),
      format: Some(McpElicitationStringFormat::Email),
      default: Some("user@example.com".to_string()),
  })
  ```

## 依赖与外部交互

### 依赖类型
- `McpElicitationStringSchema`：字符串字段定义，包含 format 字段

### 与 JSON Schema 的对应
该类型对应 JSON Schema 的 `format` 关键字，遵循以下规范：
- `email`：RFC 5322 邮箱格式
- `uri`：RFC 3986 URI 格式
- `date`：ISO 8601 日期格式 (YYYY-MM-DD)
- `date-time`：ISO 8601 日期时间格式 (RFC 3339)

### 客户端处理建议
虽然该类型定义了格式规范，但实际的验证和 UI 渲染由客户端实现：
- TUI 客户端可能仅做基本的文本输入
- GUI 客户端可以渲染专门的控件（如日期选择器）
- 服务器应始终对返回值进行验证，不依赖客户端验证

## 风险、边界与改进建议

### 当前限制
1. **格式有限**：仅支持 4 种常见格式，缺少如 `hostname`、`ipv4`、`uuid` 等常用格式
2. **无自定义格式**：不支持自定义格式模式（如正则表达式）
3. **验证依赖客户端**：TypeScript 类型本身不包含验证逻辑

### 边界情况
1. **部分匹配**：客户端可能无法精确验证所有格式（如复杂的 email 规则）
2. **时区处理**：`date-time` 格式涉及时区，客户端需要正确处理
3. **空值处理**：`format` 为可选字段，客户端需要处理无格式的情况

### 与标准 JSON Schema 格式的对比

JSON Schema 定义了更多格式，当前实现是子集：

| JSON Schema 格式 | 当前支持 | 说明 |
|-----------------|---------|------|
| `email` | ✅ | 邮箱地址 |
| `uri` | ✅ | URI |
| `date` | ✅ | 日期 |
| `date-time` | ✅ | 日期时间 |
| `hostname` | ❌ | 主机名 |
| `ipv4` | ❌ | IPv4 地址 |
| `ipv6` | ❌ | IPv6 地址 |
| `uuid` | ❌ | UUID |
| `regex` | ❌ | 正则表达式 |
| `json-pointer` | ❌ | JSON Pointer |

### 改进建议

1. **扩展格式支持**：
   - 添加 `hostname`、`ipv4`、`ipv6` 等网络相关格式
   - 添加 `uuid` 用于标识符输入
   - 添加 `password` 用于密码输入（隐藏显示）

2. **添加自定义格式**：
   ```rust
   pub enum McpElicitationStringFormat {
       // ... 标准格式
       #[serde(rename = "pattern")]
       Pattern(String),  // 自定义正则
   }
   ```

3. **添加格式提示**：
   在 schema 中添加 `format_hint` 字段，提供用户友好的格式说明

4. **国际化支持**：
   日期时间格式考虑本地化显示，但保持 ISO 8601 传输格式

### 使用示例

```rust
use codex_app_server_protocol::{
    McpElicitationStringSchema, McpElicitationStringType, McpElicitationStringFormat,
};

// 邮箱字段
let email_schema = McpElicitationStringSchema {
    type_: McpElicitationStringType::String,
    title: Some("Email".to_string()),
    description: Some("Enter your email address".to_string()),
    format: Some(McpElicitationStringFormat::Email),
    min_length: Some(5),
    max_length: Some(254),
    default: None,
};

// URL 字段
let url_schema = McpElicitationStringSchema {
    type_: McpElicitationStringType::String,
    title: Some("Website".to_string()),
    description: Some("Your company website".to_string()),
    format: Some(McpElicitationStringFormat::Uri),
    min_length: None,
    max_length: Some(2048),
    default: Some("https://".to_string()),
};

// 日期字段
let date_schema = McpElicitationStringSchema {
    type_: McpElicitationStringType::String,
    title: Some("Birth Date".to_string()),
    description: Some("Select your birth date".to_string()),
    format: Some(McpElicitationStringFormat::Date),
    min_length: None,
    max_length: None,
    default: None,
};
```
