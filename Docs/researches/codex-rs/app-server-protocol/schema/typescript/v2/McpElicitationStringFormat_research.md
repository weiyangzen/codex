# McpElicitationStringFormat 研究文档

## 场景与职责

`McpElicitationStringFormat` 是 MCP Elicitation 系统中用于定义字符串字段格式的枚举类型。它基于 JSON Schema 的 `format` 关键字，为字符串字段提供语义化验证提示，帮助客户端渲染合适的输入控件（如日期选择器、邮箱验证等）。

该类型用于增强字符串字段的类型信息，让 UI 能够提供更友好的输入体验。

## 功能点目的

1. **格式语义化**: 为字符串字段提供标准格式定义（邮箱、URI、日期等）
2. **UI 适配**: 指导客户端渲染合适的输入控件
3. **验证提示**: 提供用户输入的格式验证依据
4. **JSON Schema 兼容**: 遵循 JSON Schema 标准格式关键字

## 具体技术实现

### 数据结构定义

```typescript
export type McpElicitationStringFormat = "email" | "uri" | "date" | "date-time";
```

### 支持的格式

| 格式值 | 说明 | 典型 UI 控件 |
|--------|------|-------------|
| `email` | 电子邮箱地址 | 邮箱输入框，带 @ 验证 |
| `uri` | URI/URL 格式 | URL 输入框，带协议验证 |
| `date` | ISO 8601 日期格式 (YYYY-MM-DD) | 日期选择器 |
| `date-time` | ISO 8601 日期时间格式 | 日期时间选择器 |

### Rust 源码定义

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

### 在字符串 Schema 中的使用

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationStringSchema {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationStringType,
    // ... 其他字段
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub format: Option<McpElicitationStringFormat>,
    // ...
}
```

## 关键代码路径与文件引用

### TypeScript 生成文件
- **文件路径**: `codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationStringFormat.ts`

### Rust 源文件
- **文件路径**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**: 5258-5266

### 使用场景

1. **字符串 Schema 定义** (`codex-rs/app-server-protocol/src/protocol/v2.rs:5245`)
   - 作为 `McpElicitationStringSchema` 的可选字段

2. **测试用例** (`codex-rs/app-server-protocol/src/protocol/v2.rs:7288`)
   ```rust
   format: Some(McpElicitationStringFormat::Email),
   ```

### 序列化示例

```json
{
  "type": "string",
  "title": "Contact Email",
  "format": "email",
  "description": "Your primary email address"
}
```

```json
{
  "type": "string",
  "title": "Event Date",
  "format": "date-time",
  "description": "When the event starts"
}
```

## 依赖与外部交互

### 上游依赖
- 无直接依赖，为基础枚举类型

### 下游消费者
- `McpElicitationStringSchema`: 作为可选的 `format` 字段
- TUI 字符串输入组件：根据 format 渲染不同的输入控件

### JSON Schema 标准对应

| MCP Format | JSON Schema Format |
|-----------|-------------------|
| `email` | `email` |
| `uri` | `uri` |
| `date` | `date` |
| `date-time` | `date-time` |

## 风险、边界与改进建议

### 已知限制
1. **格式有限**: 仅支持 4 种常见格式，缺少 `hostname`, `ipv4`, `ipv6`, `uuid` 等
2. **无验证逻辑**: 类型本身不包含验证实现，仅作为提示
3. **kebab-case 序列化**: Rust 使用 `rename_all = "kebab-case"`，确保与 JSON Schema 标准一致

### 边界情况
- 客户端可能不支持某些格式，应优雅降级为普通文本输入
- 格式与 `pattern` 约束同时存在时，需要协调验证逻辑

### 改进建议
1. **扩展格式支持**:
   - `hostname`: 主机名验证
   - `ipv4`/`ipv6`: IP 地址验证
   - `uuid`: UUID 格式
   - `regex`: 正则表达式（用于代码生成场景）
   - `json-pointer`: JSON Pointer 格式

2. **添加验证工具函数**:
   ```rust
   impl McpElicitationStringFormat {
       pub fn validate(&self, value: &str) -> Result<(), ValidationError> {
           // 格式验证逻辑
       }
   }
   ```

3. **UI 提示增强**:
   - 添加 `placeholder` 生成函数
   - 提供格式说明文本

4. **国际化支持**:
   - 日期格式考虑本地化（`date`  vs `date-time` 的显示格式）

### 测试覆盖
- 序列化/反序列化测试在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 的测试模块中
- TUI 输入控件测试（根据 format 渲染不同控件）
