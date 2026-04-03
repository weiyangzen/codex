# McpElicitationUntitledMultiSelectEnumSchema.ts 研究文档

## 场景与职责

`McpElicitationUntitledMultiSelectEnumSchema.ts` 定义了 MCP (Model Context Protocol) 征求表单中**无标题的多选枚举**字段的模式类型。该类型允许用户从预定义的字符串选项列表中选择多个值，选项值本身就是显示文本。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **简单多选枚举**: 提供轻量级的多选枚举模式，选项值直接作为显示文本
2. **选择数量限制**: 支持 `minItems` 和 `maxItems` 限制选择的数量
3. **默认值支持**: 可以指定默认选中的选项列表
4. **快速实现**: 适用于选项值本身就是人类可读字符串的场景

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationUntitledMultiSelectEnumSchema = { 
  type: McpElicitationArrayType,      // 必须是 "array"
  title?: string,                     // 字段标题
  description?: string,               // 字段描述
  minItems?: bigint,                  // 最少选择数量
  maxItems?: bigint,                  // 最多选择数量
  items: McpElicitationUntitledEnumItems,  // 选项定义（使用 enum）
  default?: Array<string>,            // 默认选中的值列表
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | `McpElicitationArrayType` | 是 | 固定为 `"array"`，表示多选 |
| `title` | `string` | 否 | 字段的显示标题 |
| `description` | `string` | 否 | 字段的详细描述 |
| `minItems` | `bigint` | 否 | 最少需要选择的选项数量 |
| `maxItems` | `bigint` | 否 | 最多可以选择的选项数量 |
| `items` | `McpElicitationUntitledEnumItems` | 是 | 选项定义，使用 `enum` 数组 |
| `default` | `string[]` | 否 | 默认选中的选项值列表 |

### 选项结构 (`McpElicitationUntitledEnumItems`)

```typescript
{
  type: "string",
  enum: ["选项1", "选项2", "选项3"]  // 选项值列表
}
```

### 生成来源

该文件由 Rust 结构体通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpElicitationUntitledMultiSelectEnumSchema {
    pub r#type: McpElicitationArrayType,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub min_items: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub max_items: Option<u64>,
    pub items: McpElicitationUntitledEnumItems,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<Vec<String>>,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义相关 Rust 类型 |
| `codex-rs/core/src/mcp_tool_call.rs` | 处理 MCP 工具调用 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的多选表单组件（复选框组或多选下拉框）
- TUI 的多选提示界面
- 表单验证逻辑

### 相关类型

| 类型 | 说明 |
|------|------|
| `McpElicitationArrayType.ts` | 数组类型枚举 |
| `McpElicitationUntitledEnumItems.ts` | 无标题的选项定义 |
| `McpElicitationTitledMultiSelectEnumSchema.ts` | 带标题多选枚举 |

### 相关测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs` | MCP 征求功能测试 |

## 依赖与外部交互

### 直接依赖类型

- `McpElicitationArrayType.ts`: 数组类型定义
- `McpElicitationUntitledEnumItems.ts`: 无标题的选项定义

### 被依赖类型

- `McpElicitationPrimitiveSchema.ts`: 可能包含此类型作为数组类型的变体

### MCP 协议集成

该类型实现了 MCP 规范中的简单多选征求功能：
1. MCP 服务器定义征求表单，包含无标题的多选字段
2. 客户端根据 `items.enum` 列表渲染多选 UI
3. 用户选择多个选项
4. 客户端验证选择数量是否在 `minItems` 和 `maxItems` 范围内
5. 客户端将选中的值数组发送回 MCP 服务器

### 与带标题多选枚举的对比

| 特性 | 无标题 (`Untitled`) | 带标题 (`Titled`) |
|------|-------------------|------------------|
| 选项定义 | `enum` 字符串数组 | `oneOf` 对象数组 |
| 显示值 | 选项值本身 | `title` 字段 |
| 描述支持 | 无 | 每个选项可有描述 |
| 适用场景 | 选项值可读 | 选项值为技术标识符 |
| 复杂度 | 简单 | 较复杂 |

## 风险、边界与改进建议

### 风险点

1. **选项值可读性**: 需要确保 `enum` 中的值对人类可读
2. **国际化限制**: 直接使用值作为显示文本，不利于国际化
3. **选择数量验证**: 客户端和服务器都需要验证选择数量
4. **默认值有效性**: `default` 中的值必须在 `enum` 中

### 边界情况

1. **空枚举列表**: `enum: []` 会导致无选项可选
2. **重复值**: `enum` 中不应有重复值
3. **空选择**: `minItems` 为 0 或未设置时允许空选择
4. **全选**: 当选项数量等于 `maxItems` 时，可能需要"全选"功能

### 改进建议

1. **添加搜索功能**: 对于大量选项，添加搜索/过滤功能
2. **选项排序**: 支持选项排序或按字母顺序自动排序
3. **值映射**: 支持值到显示文本的简单映射（轻量级标题支持）
   ```typescript
   {
     type: "array",
     items: {
       type: "string",
       enum: ["bug", "feature"],
       labels: { "bug": "Bug 修复", "feature": "新功能" }
     }
   }
   ```
4. **全选/取消全选**: 提供快捷操作按钮
5. **选项分组**: 支持简单的选项分组

### UI 建议

1. **选项数量阈值**:
   - 少于 10 个选项：使用复选框组
   - 10-30 个选项：使用带搜索的多选下拉框
   - 超过 30 个选项：使用虚拟滚动 + 搜索

2. **选择计数显示**: 实时显示已选择数量，特别是当有 `minItems`/`maxItems` 限制时

3. **验证提示**:
   - 未达到 `minItems` 时显示提示
   - 超过 `maxItems` 时阻止选择并提示

### 示例使用场景

```typescript
// 标签选择示例
const labelSchema: McpElicitationUntitledMultiSelectEnumSchema = {
  type: "array",
  title: "选择标签",
  description: "为此问题添加标签",
  minItems: 1n,
  maxItems: 3n,
  items: {
    type: "string",
    enum: ["bug", "feature", "docs", "test", "refactor"]
  },
  default: []
};

// 星期选择示例
const weekdaySchema: McpElicitationUntitledMultiSelectEnumSchema = {
  type: "array",
  title: "选择工作日",
  items: {
    type: "string",
    enum: ["周一", "周二", "周三", "周四", "周五"]
  },
  minItems: 1n,
  maxItems: 5n,
  default: ["周一", "周二", "周三", "周四", "周五"]
};
```
