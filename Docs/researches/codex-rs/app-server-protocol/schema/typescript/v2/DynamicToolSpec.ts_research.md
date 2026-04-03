# DynamicToolSpec.ts Research Document

## 场景与职责

`DynamicToolSpec` 是 Codex App-Server Protocol v2 API 中用于定义动态工具规范的数据结构。它描述了动态工具的元数据，包括工具名称、描述、输入参数模式（JSON Schema）以及加载行为控制选项。

动态工具规范是工具注册和发现机制的基础，允许客户端了解可用工具的能力，并正确构造工具调用请求。

## 功能点目的

该类型的主要目的是：

1. **工具描述**：提供工具的人类可读描述，帮助用户和 AI 理解工具的用途
2. **参数验证**：通过 JSON Schema 定义工具期望的输入参数结构，支持运行时验证
3. **延迟加载控制**：通过 `deferLoading` 选项控制工具的加载时机，优化启动性能
4. **工具发现**：支持工具注册表的构建和工具列表的展示

## 具体技术实现

### 数据结构定义

```typescript
// DynamicToolSpec.ts
import type { JsonValue } from "../serde_json/JsonValue";

export type DynamicToolSpec = { 
  name: string, 
  description: string, 
  inputSchema: JsonValue, 
  deferLoading?: boolean, 
};
```

### 关键字段说明

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `name` | `string` | 是 | 工具的唯一标识名称，用于调用时引用该工具 |
| `description` | `string` | 是 | 工具的功能描述，通常用于向 AI 解释工具的用途和使用场景 |
| `inputSchema` | `JsonValue` | 是 | 符合 JSON Schema 规范的对象，定义工具接受的输入参数结构 |
| `deferLoading` | `boolean` | 否 | 如果为 `true`，工具将在首次调用时延迟加载而非启动时加载 |

#### inputSchema 详细说明

`inputSchema` 是一个 JSON Schema 对象，定义了工具期望的输入参数。例如：

```json
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "搜索查询字符串"
    },
    "limit": {
      "type": "number",
      "description": "返回结果的最大数量",
      "default": 10
    }
  },
  "required": ["query"]
}
```

#### deferLoading 详细说明

- **默认值**: `false`（如果省略）
- **用途**: 控制工具的加载时机
  - `false` 或未设置：工具在系统启动时立即加载
  - `true`：工具在首次被调用时才加载，减少启动时间和资源占用
- **适用场景**: 大型工具或不常用工具的懒加载

### Rust 端对应实现

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct DynamicToolSpec {
    pub name: String,
    pub description: String,
    pub input_schema: JsonValue,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub defer_loading: bool,
}

// 反序列化实现，支持向后兼容的 expose_to_context 字段
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DynamicToolSpecDe {
    name: String,
    description: String,
    input_schema: JsonValue,
    defer_loading: Option<bool>,
    expose_to_context: Option<bool>,  // 旧字段，已弃用
}

impl<'de> Deserialize<'de> for DynamicToolSpec {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let DynamicToolSpecDe {
            name,
            description,
            input_schema,
            defer_loading,
            expose_to_context,
        } = DynamicToolSpecDe::deserialize(deserializer)?;

        Ok(Self {
            name,
            description,
            input_schema,
            defer_loading: defer_loading
                .unwrap_or_else(|| expose_to_context.map(|visible| !visible).unwrap_or(false)),
        })
    }
}
```

注意：Rust 实现包含向后兼容逻辑，将旧的 `expose_to_context` 字段映射到新的 `defer_loading` 字段（语义相反）。

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/DynamicToolSpec.ts`
- **TypeScript 依赖**: `codex-rs/app-server-protocol/schema/typescript/v2/serde_json/JsonValue.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `DynamicToolSpec` 结构体定义（约第 547-586 行）
- **相关类型**:
  - `DynamicToolCallParams` - 动态工具调用请求
  - `DynamicToolCallResponse` - 动态工具调用响应

## 依赖与外部交互

### 上游依赖

1. **JsonValue**: 来自 `serde_json` 的通用 JSON 值类型，用于表示灵活的 JSON Schema 结构
2. **Tool Registration System**: 动态工具规范通常由工具注册系统生成和管理

### 下游消费

1. **AI Model**: 工具描述和 inputSchema 被传递给 AI 模型，帮助模型理解何时以及如何使用工具
2. **Client UI**: 工具列表和描述可能显示在用户界面中
3. **Validation Layer**: inputSchema 用于验证工具调用请求的参数

### 序列化行为

- 使用 camelCase 命名规范
- `defer_loading` 仅在值为 `true` 时序列化（`skip_serializing_if = "std::ops::Not::not"`）
- 支持向后兼容的反序列化

## 风险、边界与改进建议

### 潜在风险

1. **Schema 兼容性**: JSON Schema 版本差异可能导致验证行为不一致
2. **循环引用**: 复杂的 inputSchema 可能包含循环引用，导致序列化/反序列化问题
3. **描述质量**: 描述字段的质量直接影响 AI 使用工具的准确性
4. **命名冲突**: 工具名称需要全局唯一，否则可能导致调用歧义

### 边界情况

1. **空 Schema**: `inputSchema` 可以是空对象 `{}`，表示工具不接受任何参数
2. **复杂嵌套**: Schema 可能包含深层嵌套的对象和数组定义
3. **动态 Schema**: 某些工具的 Schema 可能在运行时根据上下文变化
4. **向后兼容**: 旧版本客户端可能不理解新添加的字段

### 改进建议

1. **添加版本字段**: 添加 `version` 字段支持工具规范的版本管理
2. **添加标签/分类**: 添加 `tags` 或 `category` 字段支持工具分类和过滤
3. **添加示例**: 添加 `examples` 字段展示工具调用的示例输入输出
4. **Schema 版本声明**: 明确声明使用的 JSON Schema 版本
5. **添加作者信息**: 添加 `author` 或 `source` 字段标识工具来源
6. **弃用标记**: 添加 `deprecated` 字段标记已弃用的工具

### 扩展示例

```typescript
// 建议的扩展版本
export type DynamicToolSpec = { 
  name: string;
  description: string;
  inputSchema: JsonValue;
  outputSchema?: JsonValue;  // 新增：输出参数模式
  deferLoading?: boolean;
  version?: string;  // 新增：工具版本
  tags?: string[];  // 新增：工具标签
  examples?: ToolExample[];  // 新增：使用示例
  deprecated?: boolean;  // 新增：弃用标记
  deprecationMessage?: string;  // 新增：弃用说明
};

interface ToolExample {
  description: string;
  input: JsonValue;
  output: JsonValue;
}
```
