# McpElicitationSchema.ts 研究文档

## 场景与职责

`McpElicitationSchema.ts` 定义了 MCP (Model Context Protocol) `elicitation/create` 请求的表单模式类型。该类型用于在 MCP 服务器需要向用户请求额外信息时，定义表单的结构和验证规则。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端（如 VS Code 扩展或 TUI）与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **表单模式定义**: 提供类型化的表单模式定义，匹配 MCP 2025-11-25 规范中的 `ElicitRequestFormParams` 的 `requestedSchema` 形状
2. **属性验证**: 定义表单对象的属性类型（通过 `McpElicitationPrimitiveSchema`）
3. **必填字段标记**: 通过 `required` 数组标记哪些属性是必填的
4. **JSON Schema 支持**: 可选的 `$schema` 字段支持标准 JSON Schema 声明

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationSchema = { 
  $schema?: string,                    // 可选的 JSON Schema URI
  type: McpElicitationObjectType,      // 必须是 "object" 类型
  properties: { 
    [key in string]?: McpElicitationPrimitiveSchema  // 动态属性定义
  }, 
  required?: Array<string>,            // 必填字段名称列表
};
```

### 关键依赖类型

- `McpElicitationObjectType`: 枚举类型，固定为 `"object"`
- `McpElicitationPrimitiveSchema`: 定义单个表单字段的模式（类型、描述、约束等）

### 生成来源

该文件由 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中的 Rust 类型通过 `ts-rs` 宏自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpElicitationSchema {
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub schema: Option<String>,
    pub r#type: McpElicitationObjectType,
    pub properties: HashMap<String, McpElicitationPrimitiveSchema>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub required: Option<Vec<String>>,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义 `McpElicitationSchema` Rust 结构体 |
| `codex-rs/core/src/mcp_tool_call.rs` | 使用 `McpElicitationSchema` 处理 MCP 工具调用 |
| `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs` | TUI 中渲染 MCP 征求界面的实现 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的表单渲染组件
- TUI (Terminal User Interface) 的征求提示界面
- 任何需要处理 MCP 服务器请求的客户端

### 相关测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs` | MCP 征求功能的集成测试 |
| `codex-rs/core/src/mcp_tool_call_tests.rs` | MCP 工具调用的单元测试 |

## 依赖与外部交互

### 直接依赖类型

- `McpElicitationObjectType.ts`: 定义对象类型枚举
- `McpElicitationPrimitiveSchema.ts`: 定义原始类型模式

### 被依赖类型

- `McpServerElicitationRequestParams.ts`: 使用 `McpElicitationSchema` 作为 `requestedSchema` 字段类型

### MCP 协议集成

该类型实现了 MCP 规范中的表单征求功能：
1. MCP 服务器发送 `elicitation/create` 请求
2. 客户端使用 `McpElicitationSchema` 验证和渲染表单
3. 用户填写表单后，客户端发送响应回 MCP 服务器

## 风险、边界与改进建议

### 风险点

1. **自动生成限制**: 作为生成的代码，手动修改会被覆盖，必须通过修改 Rust 源文件来更新
2. **版本兼容性**: 依赖 MCP 2025-11-25 规范，规范更新时需要同步更新
3. **循环依赖风险**: `properties` 中的 `McpElicitationPrimitiveSchema` 可能包含嵌套结构

### 边界情况

1. **空属性对象**: `properties` 为空对象 `{}` 时，表单将没有任何字段
2. **必填字段不存在**: `required` 中列出的字段必须在 `properties` 中存在
3. **可选字段处理**: 所有字段默认都是可选的，除非在 `required` 中明确列出

### 改进建议

1. **添加运行时验证**: 考虑在客户端添加 JSON Schema 运行时验证，而不仅依赖 TypeScript 类型
2. **文档生成**: 可以基于 `McpElicitationSchema` 自动生成表单字段的文档
3. **默认值支持**: 考虑扩展类型以支持字段默认值声明
4. **条件字段**: 未来可考虑支持基于其他字段值的条件字段显示（`if/then/else`）

### 相关规范

- MCP Specification 2025-11-25: `ElicitRequestFormParams` 模式
- JSON Schema Draft 7/2020-12: 用于 `$schema` 字段的验证
