# DynamicToolCallOutputContentItem.ts 研究文档

## 场景与职责

`DynamicToolCallOutputContentItem.ts` 定义了动态工具调用输出内容项类型，用于表示动态工具调用的输出内容。动态工具是 Codex 的扩展机制，允许在运行时注册和使用自定义工具。

该类型支持多种内容格式（文本、图像），使动态工具能够返回丰富的结果。

## 功能点目的

1. **多样化输出**: 支持文本和图像两种输出格式
2. **动态工具集成**: 为动态工具调用提供标准化的输出结构
3. **内容传递**: 将工具执行结果传递回对话上下文

## 具体技术实现

### 数据结构定义

```typescript
export type DynamicToolCallOutputContentItem = 
  | { "type": "inputText", text: string }
  | { "type": "inputImage", imageUrl: string };
```

### 字段说明

| 变体 | 字段 | 类型 | 说明 |
|------|------|------|------|
| `inputText` | `text` | `string` | 文本内容 |
| `inputImage` | `imageUrl` | `string` | 图像 URL |

### 使用示例

```typescript
// 文本输出
const textItem: DynamicToolCallOutputContentItem = {
  type: 'inputText',
  text: '搜索结果显示...'
};

// 图像输出
const imageItem: DynamicToolCallOutputContentItem = {
  type: 'inputImage',
  imageUrl: 'https://example.com/chart.png'
};
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/protocol/src/models.rs`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum DynamicToolCallOutputContentItem {
    #[serde(rename_all = "camelCase")]
    InputText { text: String },
    #[serde(rename_all = "camelCase")]
    InputImage { image_url: String },
}
```

### 动态工具调用

**文件**: `codex-rs/protocol/src/protocol.rs`

```rust
pub struct DynamicToolCall {
    pub id: String,
    pub tool: String,
    pub arguments: Value,
    pub status: DynamicToolCallStatus,
    pub content_items: Option<Vec<DynamicToolCallOutputContentItem>>,
    pub success: Option<bool>,
    pub duration_ms: Option<i64>,
}
```

### ThreadItem 集成

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4197-4207)

```rust
DynamicToolCall {
    id: String,
    tool: String,
    arguments: JsonValue,
    status: DynamicToolCallStatus,
    content_items: Option<Vec<DynamicToolCallOutputContentItem>>,
    success: Option<bool>,
    duration_ms: Option<i64>,
}
```

### 动态工具实现

**文件**: `codex-rs/app-server/src/dynamic_tools.rs`

处理动态工具的注册、调用和结果处理。

### 测试用例

**文件**: `codex-rs/app-server/tests/suite/v2/dynamic_tools.rs`

动态工具的集成测试。

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `codex_protocol::models::DynamicToolCallOutputContentItem` | 核心协议定义 |
| `serde` | 序列化/反序列化 |

### 下游消费者

- **TUI**: 显示动态工具调用的结果
- **ThreadItem 渲染**: 作为对话历史的一部分显示
- **客户端**: 处理动态工具的输出

## 风险、边界与改进建议

### 已知风险

1. **类型命名**: `inputText`/`inputImage` 命名可能令人困惑（是输入还是输出？）
2. **格式限制**: 仅支持文本和图像，不支持其他格式（如音频、视频）
3. **图像加载**: 图像 URL 可能存在加载失败风险

### 边界情况

1. **空内容**: 工具可能返回空内容
2. **大图像**: 图像 URL 可能指向大文件，影响性能
3. **URL 有效性**: 图像 URL 可能过期或无效

### 改进建议

1. **更多格式**: 支持 Markdown、HTML、表格等更多格式
2. **内联数据**: 支持 base64 编码的内联图像数据
3. **元数据**: 增加内容类型、大小等元数据
4. **命名澄清**: 考虑将 `inputText` 重命名为 `text` 或 `content`
5. **错误处理**: 增加内容加载失败的错误类型

### 扩展示例

```typescript
// 改进后的结构
export type DynamicToolCallOutputContentItem = 
  | { type: "text"; content: string; format?: "plain" | "markdown" | "html" }
  | { type: "image"; source: { type: "url"; url: string } | { type: "base64"; data: string; mimeType: string } }
  | { type: "table"; headers: string[]; rows: string[][] }
  | { type: "error"; message: string; code?: string };
```
