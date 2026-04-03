# McpElicitationSingleSelectEnumSchema 研究文档

## 场景与职责

`McpElicitationSingleSelectEnumSchema` 是 MCP Elicitation 系统中用于定义单选枚举字段的 schema 类型。它支持两种变体：

1. **Untitled（无标题）**: 简单的字符串枚举列表
2. **Titled（带标题）**: 每个选项包含常量值和显示标题

该类型用于在 MCP 表单中呈现单选下拉框或单选按钮组，让用户从预定义选项中选择一个值。

## 功能点目的

1. **单选枚举支持**: 为 MCP 表单提供单选字段的类型定义
2. **双模式设计**: 支持简单枚举（无标题）和带描述的枚举（有标题）
3. **类型安全**: 通过 TypeScript 联合类型确保 schema 的正确使用
4. **UI 适配**: 为 TUI/GUI 渲染提供足够的元数据

## 具体技术实现

### 数据结构定义

```typescript
export type McpElicitationSingleSelectEnumSchema = 
  | McpElicitationUntitledSingleSelectEnumSchema 
  | McpElicitationTitledSingleSelectEnumSchema;
```

### 无标题单选枚举 (Untitled)

```typescript
export type McpElicitationUntitledSingleSelectEnumSchema = { 
  type: McpElicitationStringType,  // "string"
  title?: string, 
  description?: string, 
  enum: Array<string>, 
  default?: string, 
};
```

### 带标题单选枚举 (Titled)

```typescript
export type McpElicitationTitledSingleSelectEnumSchema = { 
  type: McpElicitationStringType,  // "string"
  title?: string, 
  description?: string, 
  oneOf: Array<McpElicitationConstOption>, 
  default?: string, 
};
```

### 常量选项定义

```typescript
export type McpElicitationConstOption = { 
  const: string,  // 选项值
  title: string,  // 显示标题
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(untagged)]
#[ts(export_to = "v2/")]
pub enum McpElicitationSingleSelectEnumSchema {
    Untitled(McpElicitationUntitledSingleSelectEnumSchema),
    Titled(McpElicitationTitledSingleSelectEnumSchema),
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationUntitledSingleSelectEnumSchema {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationStringType,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub description: Option<String>,
    #[serde(rename = "enum")]
    #[ts(rename = "enum")]
    pub enum_: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationTitledSingleSelectEnumSchema {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationStringType,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub description: Option<String>,
    #[serde(rename = "oneOf")]
    #[ts(rename = "oneOf")]
    pub one_of: Vec<McpElicitationConstOption>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<String>,
}
```

## 关键代码路径与文件引用

### TypeScript 生成文件
- **文件路径**: `codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationSingleSelectEnumSchema.ts`

### Rust 源文件
- **文件路径**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**: 5358-5406

### 使用场景

1. **TUI 渲染** (`codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs:614-695`)
   - 根据 schema 类型渲染不同的单选 UI
   - Untitled: 显示原始枚举值
   - Titled: 显示标题和描述

2. **McpElicitationEnumSchema** (`codex-rs/app-server-protocol/src/protocol/v2.rs:5325-5332`)
   - 作为枚举 schema 的单选变体

### 序列化示例

**Untitled 变体**:
```json
{
  "type": "string",
  "title": "Priority",
  "enum": ["low", "medium", "high"],
  "default": "medium"
}
```

**Titled 变体**:
```json
{
  "type": "string",
  "title": "Priority",
  "oneOf": [
    { "const": "low", "title": "Low Priority" },
    { "const": "medium", "title": "Medium Priority" },
    { "const": "high", "title": "High Priority" }
  ],
  "default": "medium"
}
```

## 依赖与外部交互

### 上游依赖
- `McpElicitationStringType`: 字面量类型 `"string"`
- `McpElicitationConstOption`: 常量选项定义（`const` + `title`）

### 下游消费者
- `McpElicitationEnumSchema`: 包含单选和多选两种枚举类型
- `McpElicitationPrimitiveSchema`: 作为基础 schema 类型之一
- TUI 单选渲染组件

### 相关类型
- `McpElicitationMultiSelectEnumSchema`: 多选枚举的对应类型

## 风险、边界与改进建议

### 已知限制
1. **无标签联合类型**: TypeScript 中使用 `untagged` 联合，运行时无法直接区分变体类型
2. **默认值验证**: 没有强制验证 `default` 值是否在 `enum` 或 `oneOf` 中
3. **空枚举**: `enum` 或 `oneOf` 为空数组时，表单将无可选值

### 边界情况
- `enum` 和 `oneOf` 同时存在时，由于 `untagged` 反序列化，可能产生意外行为
- 重复的 `const` 值在 `oneOf` 中可能导致选择歧义

### 改进建议
1. 添加运行时验证确保 `default` 值有效
2. 考虑添加 `description` 支持到 `McpElicitationConstOption` 以提供更详细的选项说明
3. 考虑支持选项分组（optgroups）
4. 添加对禁用选项（disabled options）的支持

### 测试覆盖
- TUI 集成测试覆盖两种变体的渲染
- 序列化/反序列化测试在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 的测试模块中
