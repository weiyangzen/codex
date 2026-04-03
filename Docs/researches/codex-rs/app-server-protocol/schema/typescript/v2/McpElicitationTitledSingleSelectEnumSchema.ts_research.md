# McpElicitationTitledSingleSelectEnumSchema.ts 研究文档

## 场景与职责

`McpElicitationTitledSingleSelectEnumSchema.ts` 定义了 MCP (Model Context Protocol) 征求表单中**带标题的单选枚举**字段的模式类型。该类型允许用户从预定义选项中选择一个值，每个选项都有友好的标题和可选的描述。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **单选枚举定义**: 提供类型化的单选枚举模式，支持选择单个选项
2. **带标题选项**: 每个选项都有 `const`（值）、`title`（标题）和可选的 `description`（描述）
3. **默认值支持**: 可以指定默认选中的选项
4. **UI 友好**: 选项的技术值与用户显示的标题分离

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationTitledSingleSelectEnumSchema = { 
  type: McpElicitationStringType,     // 必须是 "string"
  title?: string,                     // 字段标题
  description?: string,               // 字段描述
  oneOf: Array<McpElicitationConstOption>,  // 选项列表
  default?: string,                   // 默认选中的值
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | `McpElicitationStringType` | 是 | 固定为 `"string"`，表示单选返回字符串值 |
| `title` | `string` | 否 | 字段的显示标题 |
| `description` | `string` | 否 | 字段的详细描述 |
| `oneOf` | `McpElicitationConstOption[]` | 是 | 选项列表，每个选项包含值、标题和描述 |
| `default` | `string` | 否 | 默认选中的选项值 |

### 选项结构 (`McpElicitationConstOption`)

```typescript
{
  const: string,        // 选项的实际值（提交时使用）
  title: string,        // 显示给用户的标题
  description?: string  // 选项的详细描述（可选）
}
```

### 生成来源

该文件由 Rust 结构体通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpElicitationTitledSingleSelectEnumSchema {
    pub r#type: McpElicitationStringType,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub description: Option<String>,
    pub one_of: Vec<McpElicitationConstOption>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<String>,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义相关 Rust 类型 |
| `codex-rs/core/src/mcp_tool_call.rs` | 处理 MCP 工具调用 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的单选表单组件（单选按钮组或下拉选择器）
- TUI 的单选提示界面
- 表单验证逻辑

### 相关类型

| 类型 | 说明 |
|------|------|
| `McpElicitationStringType.ts` | 字符串类型枚举 |
| `McpElicitationConstOption.ts` | 带标题的选项定义 |
| `McpElicitationUntitledSingleSelectEnumSchema.ts` | 无标题单选枚举 |
| `McpElicitationSingleSelectEnumSchema.ts` | 单选枚举联合类型 |

### 相关测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs` | MCP 征求功能测试 |

## 依赖与外部交互

### 直接依赖类型

- `McpElicitationStringType.ts`: 字符串类型定义
- `McpElicitationConstOption.ts`: 带标题的选项定义

### 被依赖类型

- `McpElicitationSingleSelectEnumSchema.ts`: 包含此类型作为联合类型的变体

### MCP 协议集成

该类型实现了 MCP 规范中的单选征求功能：
1. MCP 服务器定义征求表单，包含带标题的单选字段
2. 客户端根据模式渲染单选 UI（单选按钮组或下拉选择器）
3. 用户选择一个选项
4. 客户端提交选项的 `const` 值（而非 `title`）回 MCP 服务器

### 与无标题单选枚举的区别

| 特性 | 带标题 (`Titled`) | 无标题 (`Untitled`) |
|------|------------------|-------------------|
| 选项定义 | `oneOf` 数组 | `enum` 数组 |
| 显示值 | `title` 字段 | 选项值本身 |
| 适用场景 | 技术值不友好时 | 选项值本身可读时 |
| 描述支持 | 每个选项可有描述 | 无单独描述 |

## 风险、边界与改进建议

### 风险点

1. **值与显示分离**: 需要确保提交的是 `const` 值而非 `title`
2. **默认值有效性**: `default` 值必须在 `oneOf` 中存在
3. **选项值唯一性**: `oneOf` 中的 `const` 值必须唯一

### 边界情况

1. **空选项列表**: `oneOf: []` 会导致无选项可选
2. **重复选项值**: `oneOf` 中不应有重复的 `const` 值
3. **空标题**: `title` 为空字符串时可能影响 UI 显示
4. **长描述**: 选项描述过长时需要适当的 UI 处理（如工具提示）

### 改进建议

1. **选项分组**: 支持选项分组（如 `optgroup`）
   ```typescript
   oneOf: Array<{
     group: string;
     options: Array<McpElicitationConstOption>;
   }>
   ```

2. **条件选项**: 支持基于其他字段值的动态选项

3. **搜索功能**: 对于大量选项，添加搜索/过滤功能

4. **图标支持**: 为选项添加图标支持
   ```typescript
   {
     const: string;
     title: string;
     description?: string;
     icon?: string;
   }
   ```

### UI 建议

1. **选项数量阈值**:
   - 少于 5 个选项：使用单选按钮组（Radio Group）
   - 5-10 个选项：使用下拉选择器（Select）
   - 超过 10 个选项：使用带搜索的下拉选择器

2. **描述显示**:
   - 短描述：直接显示在选项下方
   - 长描述：使用工具提示（Tooltip）或信息图标

3. **默认值处理**:
   - 明确标记默认选项
   - 提供"重置为默认"按钮

### 示例使用场景

```typescript
// 主题选择示例
const themeSchema: McpElicitationTitledSingleSelectEnumSchema = {
  type: "string",
  title: "选择主题",
  description: "请选择您喜欢的界面主题",
  oneOf: [
    { 
      const: "light", 
      title: "浅色主题", 
      description: "明亮的界面风格，适合白天使用" 
    },
    { 
      const: "dark", 
      title: "深色主题", 
      description: "暗色界面风格，适合夜间使用" 
    },
    { 
      const: "auto", 
      title: "自动切换", 
      description: "根据系统设置自动切换主题" 
    }
  ],
  default: "auto"
};
```
