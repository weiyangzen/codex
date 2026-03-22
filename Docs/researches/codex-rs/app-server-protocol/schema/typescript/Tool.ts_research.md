# Tool.ts 研究文档

## 1. 场景与职责

Tool 类型在 Codex 系统中用于表示 MCP (Model Context Protocol) 客户端可调用的工具定义。它在以下场景中发挥作用：

- **工具发现**: 客户端发现 MCP 服务器提供的可用工具
- **工具调用**: 定义工具的输入参数和输出格式
- **工具元数据**: 提供工具的描述、标题、图标等辅助信息
- **工具分类**: 通过注解对工具进行分类和标记

## 2. 功能点目的

Tool 结构包含工具的完整定义：

1. **标识**: `name` 字段唯一标识工具
2. **描述**: `title` 和 `description` 提供人类可读的描述
3. **输入模式**: `inputSchema` 定义工具接受的参数（JSON Schema）
4. **输出模式**: `outputSchema` 可选地定义工具返回的数据结构
5. **注解**: `annotations` 提供额外的工具元数据
6. **图标**: `icons` 支持工具的可视化表示
7. **元数据**: `_meta` 支持扩展的自定义元数据

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type Tool = { 
  name: string, 
  title?: string, 
  description?: string, 
  inputSchema: JsonValue, 
  outputSchema?: JsonValue, 
  annotations?: JsonValue, 
  icons?: Array<JsonValue>, 
  _meta?: JsonValue, 
};
```

### Rust 对应实现

位于 `/home/sansha/Github/codex/codex-rs/protocol/src/mcp.rs` (lines 29-53):

```rust
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct Tool {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub description: Option<String>,
    pub input_schema: serde_json::Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub output_schema: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub annotations: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub icons: Option<Vec<serde_json::Value>>,
    #[serde(rename = "_meta", default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub meta: Option<serde_json::Value>,
}
```

### 关键特性

1. **JSON Schema 支持**: `input_schema` 和 `output_schema` 使用 JSON Schema 定义数据结构
2. **灵活元数据**: `annotations` 和 `_meta` 使用 `JsonValue` 提供最大灵活性
3. **可选字段**: 只有 `name` 和 `input_schema` 是必需的
4. **MCP 适配**: 提供从 MCP JSON 值转换的适配器

### MCP 值转换

Rust 实现提供了从 MCP JSON 值转换的适配器 (lines 275-279):

```rust
impl Tool {
    pub fn from_mcp_value(value: serde_json::Value) -> Result<Self, serde_json::Error> {
        Ok(serde_json::from_value::<ToolSerde>(value)?.into())
    }
}
```

辅助结构 `ToolSerde` (lines 145-163) 支持灵活的字段名映射：
- 支持 `inputSchema` 和 `input_schema` 两种字段名
- 支持 `outputSchema` 和 `output_schema` 两种字段名

### CallToolResult

工具调用的结果类型 (lines 105-119):

```rust
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct CallToolResult {
    pub content: Vec<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub structured_content: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub is_error: Option<bool>,
    #[serde(rename = "_meta", default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub meta: Option<serde_json::Value>,
}
```

## 4. 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/protocol/src/mcp.rs` | Tool 定义 (lines 29-53) |
| `/home/sansha/Github/codex/codex-rs/protocol/src/mcp.rs` | ToolSerde 辅助结构 (lines 145-163) |
| `/home/sansha/Github/codex/codex-rs/protocol/src/mcp.rs` | CallToolResult 定义 (lines 105-119) |
| `/home/sansha/Github/codex/codex-rs/protocol/src/mcp.rs` | From 转换实现 (lines 165-188, 275-279) |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/Tool.ts` | 自动生成的 TypeScript 类型 |

## 5. 依赖与外部交互

### 依赖

- **serde_json**: 用于 JSON Schema 和灵活元数据
- **ts-rs**: TypeScript 类型生成
- **schemars**: JSON Schema 生成
- **serde**: 序列化/反序列化框架

### 外部交互

- **MCP 协议**: Tool 是 MCP 协议的核心类型
- **JSON Schema**: input/output schema 遵循 JSON Schema 标准
- **模型调用**: 工具定义传递给模型，模型决定何时调用
- **工具执行**: 客户端根据 Tool 定义执行相应操作

## 6. 风险、边界与改进建议

### 风险

1. **Schema 复杂性**: JSON Schema 可能非常复杂，增加解析开销
2. **版本兼容性**: Schema 变更可能导致兼容性问题
3. **安全风险**: 工具调用可能执行危险操作，需要严格权限控制

### 边界情况

1. **空 Schema**: input_schema 为空对象时的行为
2. **循环引用**: Schema 中可能存在循环引用
3. **大 Schema**: 复杂的 Schema 可能非常大
4. **无效 Schema**: 不符合 JSON Schema 规范的 Schema

### 改进建议

1. **Schema 验证**: 添加 JSON Schema 验证确保有效性
2. **Schema 版本**: 添加 Schema 版本字段支持演进
3. **权限注解**: 在 annotations 中标准化权限信息
4. **工具分类**: 添加标准化的工具分类系统
5. **示例值**: 添加 input/output 示例帮助理解
6. **弃用标记**: 支持标记弃用的工具
7. **工具依赖**: 声明工具之间的依赖关系
