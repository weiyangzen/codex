# McpElicitationUntitledSingleSelectEnumSchema.ts 研究文档

## 场景与职责

`McpElicitationUntitledSingleSelectEnumSchema.ts` 定义了 MCP (Model Context Protocol) 征求表单中**无标题的单选枚举**字段的模式类型。该类型允许用户从预定义的字符串选项列表中选择一个值，选项值本身就是显示文本。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **简单单选枚举**: 提供轻量级的单选枚举模式，选项值直接作为显示文本
2. **默认值支持**: 可以指定默认选中的选项
3. **快速实现**: 适用于选项值本身就是人类可读字符串的场景
4. **简化定义**: 不需要为每个选项定义标题和描述

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationUntitledSingleSelectEnumSchema = { 
  type: McpElicitationStringType,     // 必须是 "string"
  title?: string,                     // 字段标题
  description?: string,               // 字段描述
  enum: Array<string>,                // 选项值列表
  default?: string,                   // 默认选中的值
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | `McpElicitationStringType` | 是 | 固定为 `"string"`，表示单选返回字符串值 |
| `title` | `string` | 否 | 字段的显示标题 |
| `description` | `string` | 否 | 字段的详细描述 |
| `enum` | `string[]` | 是 | 允许的选项值列表 |
| `default` | `string` | 否 | 默认选中的选项值 |

### 生成来源

该文件由 Rust 结构体通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpElicitationUntitledSingleSelectEnumSchema {
    pub r#type: McpElicitationStringType,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub description: Option<String>,
    pub r#enum: Vec<String>,
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
| `McpElicitationTitledSingleSelectEnumSchema.ts` | 带标题单选枚举 |
| `McpElicitationSingleSelectEnumSchema.ts` | 单选枚举联合类型 |

### 相关测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs` | MCP 征求功能测试 |

## 依赖与外部交互

### 直接依赖类型

- `McpElicitationStringType.ts`: 字符串类型定义

### 被依赖类型

- `McpElicitationSingleSelectEnumSchema.ts`: 包含此类型作为联合类型的变体

### MCP 协议集成

该类型实现了 MCP 规范中的简单单选征求功能：
1. MCP 服务器定义征求表单，包含无标题的单选字段
2. 客户端根据 `enum` 列表渲染单选 UI
3. 用户选择一个选项
4. 客户端提交选中的值回 MCP 服务器

### 与带标题单选枚举的对比

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
3. **默认值有效性**: `default` 值必须在 `enum` 中
4. **选项值唯一性**: `enum` 中的值必须唯一

### 边界情况

1. **空枚举列表**: `enum: []` 会导致无选项可选
2. **重复值**: `enum` 中不应有重复值
3. **空字符串**: `""` 作为选项值可能需要特殊处理
4. **长选项值**: 过长的选项值可能影响 UI 布局

### 改进建议

1. **值映射**: 支持值到显示文本的简单映射
   ```typescript
   {
     type: "string",
     enum: ["low", "medium", "high"],
     labels: {
       "low": "低优先级",
       "medium": "中优先级",
       "high": "高优先级"
     }
   }
   ```

2. **选项排序**: 支持选项排序或按字母顺序自动排序

3. **图标支持**: 为选项添加图标
   ```typescript
   {
     type: "string",
     enum: ["success", "warning", "error"],
     icons: {
       "success": "check-circle",
       "warning": "alert-triangle",
       "error": "x-circle"
     }
   }
   ```

4. **条件禁用**: 支持基于其他字段值禁用某些选项

### UI 建议

1. **选项数量阈值**:
   - 少于 5 个选项：使用单选按钮组
   - 5-10 个选项：使用下拉选择器
   - 超过 10 个选项：使用带搜索的下拉选择器

2. **默认值处理**:
   - 明确标记默认选项
   - 提供"重置为默认"按钮

### 示例使用场景

```typescript
// 优先级选择示例
const prioritySchema: McpElicitationUntitledSingleSelectEnumSchema = {
  type: "string",
  title: "优先级",
  description: "请选择任务优先级",
  enum: ["低", "中", "高", "紧急"],
  default: "中"
};

// 状态选择示例
const statusSchema: McpElicitationUntitledSingleSelectEnumSchema = {
  type: "string",
  title: "状态",
  enum: ["待处理", "进行中", "已完成", "已取消"],
  default: "待处理"
};
```
