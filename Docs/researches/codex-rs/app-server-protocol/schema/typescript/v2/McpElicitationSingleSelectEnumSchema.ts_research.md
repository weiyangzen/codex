# McpElicitationSingleSelectEnumSchema.ts 研究文档

## 场景与职责

`McpElicitationSingleSelectEnumSchema.ts` 定义了 MCP (Model Context Protocol) 征求表单中单选枚举字段的模式类型。该类型表示用户必须从预定义选项中选择一个值的表单字段。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **单选枚举定义**: 提供类型化的单选枚举模式，支持两种变体：
   - 无标题选项（`McpElicitationUntitledSingleSelectEnumSchema`）: 简单的字符串枚举
   - 带标题选项（`McpElicitationTitledSingleSelectEnumSchema`）: 每个选项都有标题和描述的枚举
2. **UI 渲染支持**: 为客户端提供足够的信息来渲染单选按钮或下拉选择器
3. **类型安全**: 确保表单字段定义在编译时就能验证

## 具体技术实现

### 数据结构

```typescript
export type McpElicitationSingleSelectEnumSchema = 
  | McpElicitationUntitledSingleSelectEnumSchema    // 无标题选项
  | McpElicitationTitledSingleSelectEnumSchema;     // 带标题选项
```

### 变体说明

#### 1. 无标题单选枚举 (`McpElicitationUntitledSingleSelectEnumSchema`)

```typescript
{
  type: "string",
  title?: string,           // 字段标题
  description?: string,     // 字段描述
  enum: string[],           // 选项值列表
  default?: string,         // 默认值
}
```

**适用场景**: 简单枚举，选项值本身就是可读的标签

#### 2. 带标题单选枚举 (`McpElicitationTitledSingleSelectEnumSchema`)

```typescript
{
  type: "string",
  title?: string,           // 字段标题
  description?: string,     // 字段描述
  oneOf: McpElicitationConstOption[],  // 带标题的选项列表
  default?: string,         // 默认值
}

// McpElicitationConstOption 结构
{
  const: string,            // 选项值
  title: string,            // 显示标题
  description?: string,     // 选项描述
}
```

**适用场景**: 选项值是技术标识符（如 ID），需要友好的显示标题

### 生成来源

该文件由 Rust 中的联合类型通过 `ts-rs` 自动生成：

```rust
pub type McpElicitationSingleSelectEnumSchema = 
    McpElicitationUntitledSingleSelectEnumSchema 
    | McpElicitationTitledSingleSelectEnumSchema;
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义相关 Rust 类型 |
| `codex-rs/core/src/mcp_tool_call.rs` | 处理 MCP 工具调用和征求请求 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的单选表单组件
- TUI 的选择提示界面
- 表单验证逻辑

### 相关类型

| 类型 | 说明 |
|------|------|
| `McpElicitationUntitledSingleSelectEnumSchema.ts` | 无标题单选枚举 |
| `McpElicitationTitledSingleSelectEnumSchema.ts` | 带标题单选枚举 |
| `McpElicitationConstOption.ts` | 带标题的选项定义 |

### 相关测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs` | MCP 征求功能测试 |

## 依赖与外部交互

### 直接依赖类型

- `McpElicitationTitledSingleSelectEnumSchema.ts`: 带标题选项的枚举模式
- `McpElicitationUntitledSingleSelectEnumSchema.ts`: 无标题选项的枚举模式

### 被依赖类型

- `McpElicitationPrimitiveSchema.ts`: 可能包含单选枚举作为原始类型之一

### MCP 协议集成

该类型实现了 MCP 规范中的单选征求功能：
1. MCP 服务器定义征求表单，包含单选字段
2. 客户端根据模式渲染单选 UI（下拉框或单选按钮组）
3. 用户选择一个选项
4. 客户端将选择的值发送回 MCP 服务器

## 风险、边界与改进建议

### 风险点

1. **选项值验证**: 客户端需要确保用户选择的值在 `enum` 或 `oneOf` 中定义
2. **默认值有效性**: `default` 值必须在有效选项范围内
3. **空选项处理**: 需要考虑是否允许空选择（可能需要额外的 `""` 选项）

### 边界情况

1. **空枚举列表**: `enum: []` 或 `oneOf: []` 会导致无选项可选
2. **重复选项**: `enum` 中可能有重复值，客户端需要去重
3. **默认值不在选项中**: 需要处理默认值不在有效选项列表中的情况
4. **长选项列表**: 大量选项可能影响 UI 性能，需要考虑虚拟滚动或搜索

### 改进建议

1. **添加搜索功能**: 对于大量选项，建议添加搜索/过滤功能
2. **分组支持**: 考虑添加选项分组支持（`optgroup`）
3. **验证增强**: 在客户端添加运行时验证，确保选择的值有效
4. **可清除选项**: 明确是否支持清除选择（设置为 `null`）
5. **依赖字段**: 支持基于其他字段值的动态选项（如省/市联动）

### UI 建议

1. **选项数量阈值**: 
   - 少于 5 个选项：使用单选按钮组
   - 5-10 个选项：使用下拉选择器
   - 超过 10 个选项：使用带搜索的下拉选择器
2. **默认值显示**: 明确标记默认值，帮助用户快速提交
3. **描述提示**: 使用工具提示或展开面板显示选项描述
