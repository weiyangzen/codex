# McpElicitationUntitledSingleSelectEnumSchema 研究文档

## 场景与职责

`McpElicitationUntitledSingleSelectEnumSchema` 是 MCP (Model Context Protocol) 服务器引导请求中表单模式下的**无标题单选枚举模式**定义。它用于描述 MCP 服务器向客户端请求用户输入时，需要展示的单选枚举类型表单字段的 JSON Schema 结构。

该类型属于 MCP Elicitation 表单系统的一部分，专门处理**不带标题的字符串枚举选项**（即仅显示选项值本身，而非显示标题-值对）。

## 功能点目的

### 核心功能
1. **定义单选枚举字段结构**：为 MCP 服务器的 `elicitation/create` 请求提供标准化的表单字段描述
2. **支持无标题选项**：区别于 `Titled` 变体，此模式直接展示字符串选项值，无需额外的标题映射
3. **JSON Schema 兼容**：遵循 JSON Schema 2020-12 规范，确保客户端能够正确渲染表单

### 使用场景
- MCP 工具需要用户从预定义选项中选择单个值
- 选项列表简单，不需要额外的标题描述
- 例如：选择环境（"dev"/"staging"/"prod"）、选择操作类型等

## 具体技术实现

### 数据结构定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (lines 5366-5385)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationUntitledSingleSelectEnumSchema {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub type_: McpElicitationStringType,  // 固定为 "string"
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub title: Option<String>,            // 字段标题（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub description: Option<String>,      // 字段描述（可选）
    #[serde(rename = "enum")]
    #[ts(rename = "enum")]
    pub enum_: Vec<String>,               // 可选值列表（必需）
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub default: Option<String>,          // 默认值（可选）
}
```

### 生成的 TypeScript 类型

```typescript
// schema/typescript/v2/McpElicitationUntitledSingleSelectEnumSchema.ts
export type McpElicitationUntitledSingleSelectEnumSchema = { 
    type: McpElicitationStringType,  // "string"
    title?: string, 
    description?: string, 
    enum: Array<string>,             // 必需：选项值列表
    default?: string, 
};
```

### 类型层级关系

```
McpElicitationSchema
├── type: "object"
└── properties: Map<String, McpElicitationPrimitiveSchema>
                              │
                              └── McpElicitationEnumSchema
                                  ├── SingleSelect
                                  │   ├── Untitled → McpElicitationUntitledSingleSelectEnumSchema
                                  │   └── Titled → McpElicitationTitledSingleSelectEnumSchema
                                  └── MultiSelect
                                      ├── Untitled → McpElicitationUntitledMultiSelectEnumSchema
                                      └── Titled → McpElicitationTitledMultiSelectEnumSchema
```

### 序列化特性

- **`deny_unknown_fields`**：拒绝未知字段，确保严格的模式验证
- **`skip_serializing_if = "Option::is_none"`**：省略空值字段，保持 JSON 精简
- **字段重命名**：Rust 的 `enum_` 字段映射到 JSON 的 `enum`（保留字处理）

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行 5366-5385：结构体定义
  - 行 5358-5364：`McpElicitationSingleSelectEnumSchema` 枚举定义

### 相关类型定义
| 类型 | 文件 | 行号 | 说明 |
|------|------|------|------|
| `McpElicitationSingleSelectEnumSchema` | v2.rs | 5358-5364 | 父枚举类型 |
| `McpElicitationStringType` | v2.rs | 5251-5256 | 字符串类型枚举 |
| `McpElicitationEnumSchema` | v2.rs | 5325-5332 | 枚举模式顶层类型 |
| `McpElicitationPrimitiveSchema` | v2.rs | 5214-5222 | 原始模式类型 |
| `McpElicitationSchema` | v2.rs | 5191-5205 | 根模式定义 |

### 生成的 TypeScript 文件
- `codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationUntitledSingleSelectEnumSchema.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationStringType.ts`（依赖）

### 使用场景
- `McpServerElicitationRequestParams` 中的 `Form` 模式请求
- ServerRequest 的 `McpServerElicitationRequest` 方法参数

## 依赖与外部交互

### 内部依赖
1. **ts-rs**：用于 TypeScript 类型生成
2. **schemars**：用于 JSON Schema 生成
3. **serde**：序列化/反序列化

### 协议依赖
- 遵循 MCP 2025-11-25 规范的 `ElicitRequestFormParams` 模式
- 与 `rmcp` crate 的 `CreateElicitationResult` 兼容

### 上游依赖类型
```rust
// 来自 codex_protocol::approvals::ElicitationRequest
CoreElicitationRequest::Form {
    meta,
    message,
    requested_schema,  // 包含此类型的序列化数据
}
```

## 风险、边界与改进建议

### 潜在风险
1. **保留字冲突**：Rust 中使用 `enum_` 作为字段名，虽然通过 serde 重命名解决，但在模式匹配时容易出错
2. **严格模式验证**：`deny_unknown_fields` 可能导致向前兼容性 issues——新增字段会被拒绝
3. **无标题限制**：某些复杂场景可能需要显示标题-值对，此时必须使用 `Titled` 变体

### 边界情况
1. **空枚举列表**：`enum_` 字段为必需，但空列表 `[]` 在 JSON Schema 中是合法的，可能导致客户端渲染空选择器
2. **默认值不在枚举中**：JSON Schema 允许，但可能导致验证失败或用户困惑
3. **字符串类型约束**：`type_` 字段固定为 `McpElicitationStringType::String`，但序列化后仅为 `"string"`

### 改进建议
1. **添加验证**：在反序列化时验证 `default` 值是否存在于 `enum_` 列表中
2. **文档增强**：添加示例值到字段文档中
3. **非空枚举约束**：考虑使用 `#[serde(validate)]` 或自定义验证确保 `enum_` 非空
4. **类型安全**：考虑将 `enum_: Vec<String>` 改为 `NonEmptyVec<String>` 类型

### 测试覆盖
相关测试位于 `v2.rs` 的 `#[cfg(test)]` 模块（约行 7138+），包括：
- 序列化/反序列化测试
- 与 `CoreElicitationRequest` 的转换测试
- 与 `rmcp::model::CreateElicitationResult` 的兼容性测试
