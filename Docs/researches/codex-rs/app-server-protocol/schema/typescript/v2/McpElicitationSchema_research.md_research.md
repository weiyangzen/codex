# McpElicitationSchema 研究文档

## 场景与职责

`McpElicitationSchema` 是 MCP (Model Context Protocol) 服务器向客户端请求用户输入时的表单结构定义。它用于 MCP 服务器在工具调用过程中需要向用户展示表单以收集额外信息或确认的场景。

该类型对应 MCP 2025-11-25 规范中的 `ElicitRequestFormParams` 的 `requestedSchema` 字段，用于描述表单的结构、字段类型和验证规则。

## 功能点目的

1. **表单结构定义**：定义表单的整体结构，包括字段集合和必填字段
2. **类型安全**：通过 JSON Schema 风格的类型定义，确保客户端能够正确渲染表单
3. **MCP 协议兼容**：与 MCP 规范的 `elicitation/create` 请求格式保持一致
4. **动态表单生成**：支持服务器动态生成表单结构，客户端根据 schema 渲染对应 UI

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationSchema = { 
  $schema?: string,           // 可选的 JSON Schema URI
  type: McpElicitationObjectType,  // 固定为 "object"
  properties: { [key in string]?: McpElicitationPrimitiveSchema },  // 字段定义
  required?: Array<string>,   // 必填字段名称列表
};
```

### 关键流程

1. **表单请求触发**：
   - MCP 服务器在 `call_tool` 过程中调用 `create_elicitation`
   - 服务器提供 `requested_schema` 定义表单结构

2. **客户端渲染流程**（以 TUI 为例）：
   - 接收 `McpServerElicitationRequest` 服务器请求
   - 解析 `requested_schema` 为 `McpElicitationSchema`
   - 通过 `parse_fields_from_schema` 函数转换为内部字段表示
   - 根据字段类型渲染对应的 UI 组件（文本输入、选择框等）

3. **字段解析逻辑**（`tui/src/bottom_pane/mcp_server_elicitation.rs`）：
   ```rust
   fn parse_fields_from_schema(requested_schema: &Value) -> Option<Vec<McpServerElicitationField>> {
       // 验证 type 为 "object"
       // 解析 properties 中的每个字段
       // 根据字段类型创建对应的输入控件
   }
   ```

### 支持的字段类型

通过 `McpElicitationPrimitiveSchema` 支持以下类型：
- `String`：文本输入（支持 email、uri、date、date-time 格式）
- `Number`：数字输入（整数或浮点数）
- `Boolean`：布尔选择（True/False）
- `Enum`：枚举选择（单选或多选）

## 关键代码路径与文件引用

### TypeScript 类型定义
- **文件**：`codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationSchema.ts`
- **生成来源**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 中的 `McpElicitationSchema` 结构体

### Rust 源码定义
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 5191-5205)
- **相关类型**：
  - `McpElicitationObjectType` (行 5207-5212)
  - `McpElicitationPrimitiveSchema` (行 5214-5222)

### 客户端实现
- **TUI 实现**：`codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs`
  - `parse_fields_from_schema` 函数（行 502-527）
  - `parse_field` 函数（行 529-609）

### 测试
- **集成测试**：`codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs`
  - 测试表单请求和响应的完整流程

### 使用示例
```rust
// 构建表单 schema 示例
let requested_schema = McpElicitationSchema {
    schema_uri: None,
    type_: McpElicitationObjectType::Object,
    properties: BTreeMap::from([
        ("confirmed".to_string(), McpElicitationPrimitiveSchema::Boolean(
            McpElicitationBooleanSchema {
                type_: McpElicitationBooleanType::Boolean,
                title: Some("Confirm".to_string()),
                description: Some("Please confirm this action".to_string()),
                default: Some(false),
            }
        )),
    ]),
    required: Some(vec!["confirmed".to_string()]),
};
```

## 依赖与外部交互

### 依赖类型
- `McpElicitationObjectType`：对象类型枚举
- `McpElicitationPrimitiveSchema`：基本字段类型联合类型

### 协议交互
- **服务器→客户端**：通过 `McpServerElicitationRequest` 发送表单请求
- **客户端→服务器**：通过 `McpServerElicitationRequestResponse` 返回用户输入

### MCP 协议对应
- 对应 `rmcp::model::ElicitationSchema`
- 通过 `TryFrom` trait 在 core 类型和 v2 API 类型之间转换

## 风险、边界与改进建议

### 当前限制
1. **仅支持 Object 类型**：`type` 字段固定为 `McpElicitationObjectType::Object`，不支持其他 JSON Schema 类型
2. **字段类型有限**：仅支持 String/Number/Boolean/Enum，不支持复杂嵌套对象或数组
3. **无嵌套对象支持**：`properties` 中的字段不能是另一个对象类型

### 边界情况
1. **空表单处理**：当 `properties` 为空对象时，TUI 会将其视为无需用户输入的确认对话框
2. **必填字段验证**：客户端需要自行验证 `required` 字段，服务器会再次校验
3. **默认值处理**：各字段类型的 `default` 值需要客户端正确解析和应用

### 改进建议
1. **扩展类型支持**：考虑支持数组类型、嵌套对象等更复杂的表单结构
2. **添加条件字段**：支持基于其他字段值的动态显示/隐藏（JSON Schema 的 `if/then/else`）
3. **增强验证**：在 schema 中添加更多验证规则（min/max、pattern 等）的客户端支持
4. **文档完善**：添加更多使用示例和最佳实践指南

### 相关 Issue 风险
- 该类型与 MCP 规范紧密耦合，规范变更时需要同步更新
- TypeScript 类型由 `ts-rs` 自动生成，手动修改会被覆盖
