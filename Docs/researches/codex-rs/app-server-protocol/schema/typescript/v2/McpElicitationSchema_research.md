# McpElicitationSchema 研究文档

## 场景与职责

`McpElicitationSchema` 是 Codex App-Server Protocol v2 中用于 MCP (Model Context Protocol) 服务器请求用户输入的表单结构定义。它实现了 MCP 2025-11-25 规范中的 `ElicitRequestFormParams` 的 `requestedSchema` 形状，用于在工具调用过程中向用户展示交互式表单以收集额外信息。

该类型是 MCP Elicitation 系统的核心数据结构，支持服务器在工具执行过程中动态请求用户确认或输入参数。

## 功能点目的

1. **表单结构定义**: 定义了符合 JSON Schema 标准的对象结构，用于描述需要用户填写的表单字段
2. **类型安全**: 通过 TypeScript 类型系统确保表单 schema 的结构正确性
3. **MCP 协议兼容**: 与 MCP 规范的 `elicitation/create` 请求格式保持一致
4. **代码生成**: 由 Rust `ts-rs` 库从 Rust 源码自动生成，确保前后端类型一致性

## 具体技术实现

### 数据结构定义

```typescript
export type McpElicitationSchema = { 
  $schema?: string, 
  type: McpElicitationObjectType, 
  properties: { [key in string]?: McpElicitationPrimitiveSchema }, 
  required?: Array<string>, 
};
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `$schema` | `string?` | 可选的 JSON Schema URI |
| `type` | `McpElicitationObjectType` | 固定为 `"object"` |
| `properties` | `Record<string, McpElicitationPrimitiveSchema>` | 表单字段定义 |
| `required` | `string[]?` | 必填字段列表 |

### 依赖类型

- `McpElicitationObjectType`: 字面量类型 `"object"`
- `McpElicitationPrimitiveSchema`: 联合类型，包含枚举、字符串、数字、布尔四种基础 schema 类型

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationSchema {
    #[serde(rename = "$schema", skip_serializing_if = "Option::is_none")]
    #[ts(optional, rename = "$schema")]
    pub schema_uri: Option<String>,
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationObjectType,
    pub properties: BTreeMap<String, McpElicitationPrimitiveSchema>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub required: Option<Vec<String>>,
}
```

## 关键代码路径与文件引用

### TypeScript 生成文件
- **文件路径**: `codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationSchema.ts`
- **生成工具**: [ts-rs](https://github.com/Aleph-Alpha/ts-rs)

### Rust 源文件
- **文件路径**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**: 5194-5205

### 使用场景

1. **MCP 工具调用中的表单请求** (`codex-rs/core/src/mcp_tool_call.rs:928`)
2. **工具建议处理** (`codex-rs/core/src/tools/handlers/tool_suggest.rs:219`)
3. **TUI 交互渲染** (`codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs`)
4. **集成测试** (`codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs:190`)

### 序列化示例

```json
{
  "type": "object",
  "properties": {
    "confirmed": {
      "type": "boolean"
    }
  },
  "required": ["confirmed"]
}
```

## 依赖与外部交互

### 上游依赖
- `McpElicitationObjectType`: 定义对象类型字面量
- `McpElicitationPrimitiveSchema`: 定义基础字段类型（字符串、数字、布尔、枚举）

### 下游消费者
- `McpServerElicitationRequest`: 包含 `requested_schema` 字段
- `McpServerElicitationRequestParams`: 服务器向客户端发送的 elicitation 请求参数
- TUI 组件：渲染表单 UI

### 协议集成
- 通过 `rmcp` crate 与 MCP 协议交互
- 支持 `CreateElicitationRequestParams::FormElicitationParams` 转换

## 风险、边界与改进建议

### 已知限制
1. **代码生成**: 文件为自动生成，手动修改会被覆盖
2. **类型约束**: 仅支持 `properties` 中定义的基础类型，不支持嵌套对象
3. **版本锁定**: 基于 MCP 2025-11-25 规范，未来规范变更需要同步更新

### 边界情况
- `properties` 为空对象时，表单将不显示任何字段
- `required` 字段不在 `properties` 中定义时，序列化/反序列化会失败（`deny_unknown_fields`）

### 改进建议
1. 添加对嵌套对象 schema 的支持
2. 考虑添加字段验证规则（如 `minLength`, `pattern` 等）
3. 增加运行时 schema 验证工具函数
4. 考虑支持条件字段（`if/then/else`）

### 测试覆盖
- 单元测试: `codex-rs/app-server-protocol/src/protocol/common.rs:1188-1242`
- 集成测试: `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs`
