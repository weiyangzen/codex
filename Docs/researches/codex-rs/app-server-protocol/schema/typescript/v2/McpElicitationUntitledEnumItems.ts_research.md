# McpElicitationUntitledEnumItems.ts 研究文档

## 场景与职责

`McpElicitationUntitledEnumItems.ts` 定义了 MCP (Model Context Protocol) 征求表单中**无标题枚举选项**的项目类型。该类型用于定义多选枚举中的选项值列表，选项值本身就是可读的字符串，不需要额外的标题。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **简单枚举定义**: 提供简单的字符串枚举定义，选项值直接作为显示文本
2. **多选支持**: 作为数组类型的 `items` 字段，支持多选场景
3. **轻量级**: 不需要为每个选项定义标题和描述，简化定义
4. **快速实现**: 适用于选项值本身就是人类可读的场景

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationUntitledEnumItems = { 
  type: McpElicitationStringType,  // 必须是 "string"
  enum: Array<string>,             // 选项值列表
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | `McpElicitationStringType` | 是 | 固定为 `"string"`，表示数组项为字符串 |
| `enum` | `string[]` | 是 | 允许的选项值列表 |

### 使用场景

该类型通常作为 `McpElicitationUntitledMultiSelectEnumSchema` 的 `items` 字段：

```typescript
const multiSelectSchema: McpElicitationUntitledMultiSelectEnumSchema = {
  type: "array",
  title: "选择标签",
  items: {
    type: "string",
    enum: ["bug", "feature", "docs", "test"]
  },
  default: ["feature"]
};
```

### 生成来源

该文件由 Rust 结构体通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpElicitationUntitledEnumItems {
    pub r#type: McpElicitationStringType,
    pub r#enum: Vec<String>,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义相关 Rust 类型 |
| `codex-rs/core/src/mcp_tool_call.rs` | 处理 MCP 工具调用 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的多选表单组件
- TUI 的多选提示界面
- 表单验证逻辑

### 相关类型

| 类型 | 说明 |
|------|------|
| `McpElicitationStringType.ts` | 字符串类型枚举 |
| `McpElicitationUntitledMultiSelectEnumSchema.ts` | 无标题多选枚举（使用此类型作为 items） |
| `McpElicitationTitledEnumItems.ts` | 带标题的选项定义（对比类型） |

### 相关测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs` | MCP 征求功能测试 |

## 依赖与外部交互

### 直接依赖类型

- `McpElicitationStringType.ts`: 字符串类型定义

### 被依赖类型

- `McpElicitationUntitledMultiSelectEnumSchema.ts`: 使用此类型作为 `items` 字段

### MCP 协议集成

该类型实现了 MCP 规范中的简单多选枚举功能：
1. MCP 服务器定义征求表单，包含无标题的多选字段
2. 客户端根据 `enum` 列表渲染多选 UI
3. 用户选择一个或多个选项
4. 客户端将选中的值数组发送回 MCP 服务器

### 与带标题选项的对比

| 特性 | 无标题 (`Untitled`) | 带标题 (`Titled`) |
|------|-------------------|------------------|
| 选项定义 | `enum` 数组 | `oneOf` 对象数组 |
| 显示值 | 选项值本身 | `title` 字段 |
| 描述支持 | 无 | 每个选项可有描述 |
| 适用场景 | 选项值可读 | 选项值为技术标识符 |
| 复杂度 | 简单 | 较复杂 |

## 风险、边界与改进建议

### 风险点

1. **选项值可读性**: 需要确保 `enum` 中的值对人类可读
2. **国际化限制**: 直接使用值作为显示文本，不利于国际化
3. **特殊字符**: 选项值中的特殊字符可能影响 UI 显示

### 边界情况

1. **空枚举列表**: `enum: []` 会导致无选项可选
2. **重复值**: `enum` 中不应有重复值
3. **空字符串**: `""` 作为选项值可能需要特殊处理
4. **长选项值**: 过长的选项值可能影响 UI 布局

### 改进建议

1. **添加描述支持**: 即使是简单枚举，也可以考虑添加整体描述
   ```typescript
   {
     type: "string",
     enum: ["bug", "feature"],
     description: "选择问题类型"  // 整体描述
   }
   ```

2. **排序支持**: 添加 `sorted` 字段指示选项是否已排序
   ```typescript
   {
     type: "string",
     enum: ["a", "b", "c"],
     sorted: true
   }
   ```

3. **值映射**: 支持值到显示文本的简单映射
   ```typescript
   {
     type: "string",
     enum: ["bug", "feature"],
     labels: {
       "bug": "Bug 修复",
       "feature": "新功能"
     }
   }
   ```

### UI 建议

1. **复选框布局**: 对于少量选项，使用复选框组垂直排列
2. **标签样式**: 对于大量选项或需要紧凑布局的场景，使用标签/芯片样式
3. **搜索支持**: 当选项数量超过 20 个时，添加搜索功能

### 示例使用场景

```typescript
// 标签选择示例
const labelSchema = {
  type: "array",
  title: "选择标签",
  description: "为此问题添加标签",
  items: {
    type: "string",
    enum: ["bug", "feature", "docs", "test", "refactor", "performance"]
  },
  default: []
};

// 星期选择示例
const weekdaySchema = {
  type: "array",
  title: "选择工作日",
  items: {
    type: "string",
    enum: ["周一", "周二", "周三", "周四", "周五"]
  },
  minItems: 1n,
  maxItems: 5n
};
```
