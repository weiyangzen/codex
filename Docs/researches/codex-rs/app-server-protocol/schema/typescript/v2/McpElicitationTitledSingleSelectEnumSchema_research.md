# McpElicitationTitledSingleSelectEnumSchema 研究文档

## 场景与职责

`McpElicitationTitledSingleSelectEnumSchema` 是 MCP Elicitation 系统中用于定义带标题的单选枚举字段的 schema 类型。它允许用户从预定义选项中选择一个值，每个选项包含常量值和显示标题。

该类型是 `McpElicitationSingleSelectEnumSchema` 的两个变体之一（另一个是 `McpElicitationUntitledSingleSelectEnumSchema`），适用于需要向用户展示友好选项名称的单选场景。

## 功能点目的

1. **单选枚举支持**: 为 MCP 表单提供单选字段的类型定义
2. **带标题选项**: 使用 `oneOf` + `const/title` 模式提供友好的选项显示
3. **类型安全**: 确保选项值和显示标题的强类型约束
4. **JSON Schema 兼容**: 遵循 JSON Schema 的 `oneOf` 和 `const` 关键字

## 具体技术实现

### 数据结构定义

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

### 与无标题单选枚举的区别

| 特性 | Titled (带标题) | Untitled (无标题) |
|------|----------------|------------------|
| 选项定义 | `oneOf` + `const/title` | `enum` 数组 |
| 字段名 | `oneOf` | `enum` |
| 显示友好 | ✅ 有标题 | ❌ 仅原始值 |
| 适用场景 | 用户-facing 选项 | 内部/技术选项 |

## 关键代码路径与文件引用

### TypeScript 生成文件
- **文件路径**: `codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationTitledSingleSelectEnumSchema.ts`

### Rust 源文件
- **文件路径**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**: 5387-5406

### 使用场景

1. **McpElicitationSingleSelectEnumSchema** (`codex-rs/app-server-protocol/src/protocol/v2.rs:5361-5364`)
   ```rust
   pub enum McpElicitationSingleSelectEnumSchema {
       Untitled(McpElicitationUntitledSingleSelectEnumSchema),
       Titled(McpElicitationTitledSingleSelectEnumSchema),
   }
   ```

2. **TUI 渲染** (`codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs:695`)
   ```rust
   McpElicitationSingleSelectEnumSchema::Titled(schema) => {
       // 渲染带标题的单选 UI
   }
   ```

3. **McpElicitationEnumSchema** (`codex-rs/app-server-protocol/src/protocol/v2.rs:5329`)
   - 作为枚举 schema 的单选变体之一

### 序列化示例

```json
{
  "type": "string",
  "title": "Priority Level",
  "description": "Select the priority for this task",
  "oneOf": [
    { "const": "low", "title": "Low Priority" },
    { "const": "medium", "title": "Medium Priority" },
    { "const": "high", "title": "High Priority" },
    { "const": "urgent", "title": "Urgent - Immediate Attention" }
  ],
  "default": "medium"
}
```

## 依赖与外部交互

### 上游依赖
- `McpElicitationStringType`: 字面量类型 `"string"`
- `McpElicitationConstOption`: 常量选项定义（`const` + `title`）

### 下游消费者
- `McpElicitationSingleSelectEnumSchema`: 包含此类型作为变体
- `McpElicitationEnumSchema`: 作为枚举 schema 的一部分
- `McpElicitationPrimitiveSchema`: 作为基础 schema 类型之一
- TUI 单选渲染组件

### 相关类型关系

```
McpElicitationPrimitiveSchema
└── McpElicitationEnumSchema
    └── McpElicitationSingleSelectEnumSchema
        └── McpElicitationTitledSingleSelectEnumSchema
```

## 风险、边界与改进建议

### 已知限制
1. **无标签联合**: TypeScript 中使用 `untagged` 联合类型，需要运行时检查来区分 Titled/Untitled
2. **默认值验证**: 没有强制验证 `default` 值是否在 `oneOf` 中
3. **空选项**: `oneOf` 为空数组时，用户无法选择任何值

### 边界情况
- `default` 值不在 `oneOf` 中时，反序列化会成功但逻辑上无效
- 重复的 `const` 值可能导致选择歧义
- `oneOf` 中只有一个选项时，UI 应该自动选择或显示为只读

### 改进建议
1. **添加运行时验证**:
   ```rust
   impl McpElicitationTitledSingleSelectEnumSchema {
       pub fn validate(&self) -> Result<(), ValidationError> {
           // 验证 default 值在 oneOf 中
           // 验证 oneOf 不为空
           // 验证 const 值唯一
       }
   }
   ```

2. **支持选项描述**:
   ```rust
   pub struct McpElicitationConstOption {
       pub const_: String,
       pub title: String,
       pub description: Option<String>,  // 新增：选项详细描述
   }
   ```

3. **支持选项禁用**:
   ```rust
   pub struct McpElicitationConstOption {
       pub const_: String,
       pub title: String,
       pub disabled: Option<bool>,  // 新增：禁用特定选项
   }
   ```

4. **支持选项图标**:
   ```rust
   pub struct McpElicitationConstOption {
       pub const_: String,
       pub title: String,
       pub icon: Option<String>,  // 新增：选项图标 URL 或 emoji
   }
   ```

### 测试覆盖
- TUI 集成测试覆盖带标题单选的渲染 (`codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs`)
- 序列化/反序列化测试在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 的测试模块中
