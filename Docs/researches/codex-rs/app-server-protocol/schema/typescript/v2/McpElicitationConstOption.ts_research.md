# McpElicitationConstOption 研究文档

## 1. 场景与职责

`McpElicitationConstOption` 是 App-Server Protocol v2 中的结构体类型，定义了 MCP（Model Context Protocol）参数征求中的常量选项。该类型用于表示带有标题的枚举常量选项，支持在表单中显示友好的选项名称。

**主要使用场景：**
- MCP 服务器参数征求表单中的单选/多选枚举选项
- JSON Schema 的 `oneOf`/`anyOf` 构造
- 提供常量值和用户友好的显示标题
- 客户端下拉框、单选按钮组渲染

## 2. 功能点目的

该类型的核心目的是为枚举选项提供值和显示文本的分离：

1. **常量值** (`const`)：实际的枚举值，用于提交
2. **显示标题** (`title`)：用户友好的显示文本，用于UI展示

这个设计使得：
- 枚举值可以是机器友好的标识符（如 `"api_key"`）
- 显示文本可以是用户友好的描述（如 `"API Key 认证"`）
- 支持国际化（通过动态替换标题）
- 表单渲染更加用户友好

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type McpElicitationConstOption = { 
  const: string, 
  title: string, 
};
```

### Rust 源定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct McpElicitationConstOption {
    #[serde(rename = "const")]
    #[ts(rename = "const")]
    pub const_: String,
    pub title: String,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `const` | `string` | 常量值，实际的枚举值 |
| `title` | `string` | 显示标题，用户友好的描述 |

### 特性注解

- `#[serde(deny_unknown_fields)]`：拒绝未知字段，严格模式
- `#[serde(rename = "const")]`/`#[ts(rename = "const")]`：处理 Rust 关键字 `const`
- `#[ts(export_to = "v2/")]`：TypeScript 类型导出到 `v2/` 目录

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 5494-5502 行

### 相关类型

- `McpElicitationTitledSingleSelectEnumSchema`：带标题的单选枚举 Schema（第 5387-5406 行）
- `McpElicitationTitledEnumItems`：带标题的枚举项（第 5485-5492 行）
- `McpElicitationMultiSelectEnumSchema`：多选枚举 Schema（第 5408-5464 行）

### 使用场景

该类型通常用于：
- `McpElicitationTitledEnumItems` 中的 `any_of` 字段
- 构建带标题的枚举选项列表

## 5. 依赖与外部交互

### 序列化行为

- 使用 `serde` 进行 JSON 序列化/反序列化
- `const` 字段在 JSON 中保持为 `"const"`
- 支持 JSON Schema 生成

### 与 JSON Schema 的关系

该类型对应 JSON Schema 中的 `const` 构造：
```json
{
  "anyOf": [
    { "const": "option1", "title": "选项 1" },
    { "const": "option2", "title": "选项 2" }
  ]
}
```

## 6. 风险、边界与改进建议

### 潜在风险

1. **严格模式**：`deny_unknown_fields` 可能导致向前兼容性问题
2. **空字符串**：`const` 或 `title` 为空字符串时的处理
3. **重复值**：多个选项具有相同的 `const` 值
4. **国际化**：标题硬编码，不支持动态国际化

### 边界情况

- `const` 值为空字符串
- `title` 为空字符串
- 特殊字符在 `const` 中的处理
- 超长标题的截断

### 改进建议

1. **添加描述**：
   - 添加 `description` 字段用于详细说明
   - 支持帮助文本或提示信息

2. **国际化支持**：
   - 添加 `titleKey` 字段用于 i18n
   - 支持动态标题替换

3. **禁用状态**：
   - 添加 `disabled` 字段标记不可选选项
   - 添加 `disabledReason` 说明禁用原因

4. **分组支持**：
   - 添加 `group` 字段支持选项分组
   - 实现层级选项结构

5. **图标支持**：
   - 添加 `icon` 字段支持选项图标
   - 增强视觉表现

### 与无标题枚举的对比

| 特性 | `McpElicitationConstOption` | 无标题枚举 (`McpElicitationUntitledEnumItems`) |
|------|----------------------------|-----------------------------------------------|
| 显示 | 使用 `title` | 直接使用 `const` 值 |
| 灵活性 | 高（值和显示分离） | 低（值即显示） |
| 适用场景 | 用户界面 | 程序配置 |
| JSON Schema | `oneOf`/`anyOf` | `enum` |

### 使用示例

```json
// 认证方式选择
{
  "anyOf": [
    { "const": "none", "title": "无认证" },
    { "const": "api_key", "title": "API Key" },
    { "const": "oauth", "title": "OAuth 2.0" },
    { "const": "bearer", "title": "Bearer Token" }
  ]
}
```

### JSON Schema 兼容性

该类型遵循 JSON Schema 规范：
- `const`：固定值（JSON Schema 草案 6+）
- `title`：短标题（标准 JSON Schema 属性）

这些字段可以被标准 JSON Schema 验证器识别，`const` 用于值匹配，`title` 用于文档生成。
