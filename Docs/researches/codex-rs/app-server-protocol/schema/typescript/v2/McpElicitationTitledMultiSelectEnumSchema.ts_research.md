# McpElicitationTitledMultiSelectEnumSchema.ts 研究文档

## 场景与职责

`McpElicitationTitledMultiSelectEnumSchema.ts` 定义了 MCP (Model Context Protocol) 征求表单中**带标题的多选枚举**字段的模式类型。该类型允许用户从预定义选项中选择多个值，每个选项都有友好的标题和描述。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **多选枚举定义**: 提供类型化的多选枚举模式，支持选择多个选项
2. **带标题选项**: 每个选项都有 `const`（值）、`title`（标题）和可选的 `description`（描述）
3. **选择数量限制**: 支持 `minItems` 和 `maxItems` 限制选择的数量
4. **默认值支持**: 可以指定默认选中的选项列表

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationTitledMultiSelectEnumSchema = { 
  type: McpElicitationArrayType,      // 必须是 "array"
  title?: string,                     // 字段标题
  description?: string,               // 字段描述
  minItems?: bigint,                  // 最少选择数量
  maxItems?: bigint,                  // 最多选择数量
  items: McpElicitationTitledEnumItems,  // 选项定义
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
| `items` | `McpElicitationTitledEnumItems` | 是 | 选项定义，使用 `oneOf` 结构 |
| `default` | `string[]` | 否 | 默认选中的选项值列表 |

### 选项结构 (`McpElicitationTitledEnumItems`)

```typescript
{
  type: "string",
  oneOf: [
    { const: "value1", title: "选项 1", description: "描述 1" },
    { const: "value2", title: "选项 2", description: "描述 2" },
    // ...
  ]
}
```

### 生成来源

该文件由 Rust 结构体通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpElicitationTitledMultiSelectEnumSchema {
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
    pub items: McpElicitationTitledEnumItems,
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
| `McpElicitationTitledEnumItems.ts` | 带标题的选项定义 |
| `McpElicitationUntitledMultiSelectEnumSchema.ts` | 无标题多选枚举 |

### 相关测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs` | MCP 征求功能测试 |

## 依赖与外部交互

### 直接依赖类型

- `McpElicitationArrayType.ts`: 数组类型定义
- `McpElicitationTitledEnumItems.ts`: 带标题的选项定义

### 被依赖类型

- `McpElicitationPrimitiveSchema.ts`: 可能包含此类型作为数组类型的变体

### MCP 协议集成

该类型实现了 MCP 规范中的多选征求功能：
1. MCP 服务器定义征求表单，包含多选字段
2. 客户端根据模式渲染多选 UI（复选框组或多选下拉框）
3. 用户选择多个选项
4. 客户端验证选择数量是否在 `minItems` 和 `maxItems` 范围内
5. 客户端将选中的值数组发送回 MCP 服务器

## 风险、边界与改进建议

### 风险点

1. **选择数量验证**: 客户端和服务器都需要验证选择数量
2. **默认值有效性**: `default` 中的值必须在有效选项中
3. **重复选择**: 需要处理重复值的情况
4. **大数据量**: 大量选项可能影响 UI 性能

### 边界情况

1. **空选择**: `minItems: 0` 允许空选择，但某些场景可能需要至少一个
2. **全选**: 当选项数量等于 `maxItems` 时，可能需要"全选"功能
3. **互斥选项**: 某些选项可能与其他选项互斥
4. **选项依赖**: 某些选项可能只在其他选项选中时才可用

### 改进建议

1. **添加搜索功能**: 对于大量选项，添加搜索/过滤功能
2. **选项分组**: 支持选项分组（如 `optgroup`）
3. **互斥选项支持**: 添加 `exclusiveGroups` 字段定义互斥选项组
4. **依赖选项**: 支持基于其他字段值的动态选项
5. **全选/取消全选**: 提供快捷操作按钮

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
// 权限选择示例
const permissionSchema: McpElicitationTitledMultiSelectEnumSchema = {
  type: "array",
  title: "选择权限",
  description: "请选择您要授予的权限",
  minItems: 1n,
  maxItems: 3n,
  items: {
    type: "string",
    oneOf: [
      { const: "read", title: "读取权限", description: "允许读取文件" },
      { const: "write", title: "写入权限", description: "允许修改文件" },
      { const: "delete", title: "删除权限", description: "允许删除文件" },
      { const: "admin", title: "管理权限", description: "完全控制权限" }
    ]
  },
  default: ["read"]
};
```
