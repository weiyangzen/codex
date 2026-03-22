# FunctionCallOutputBody Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`FunctionCallOutputBody` 是 Codex 协议中用于**函数调用输出体**的类型。它表示工具调用（function call）返回给模型的内容，支持纯文本和结构化内容项两种格式。

**典型使用场景：**
- Shell 命令执行后返回输出给模型
- 文件读取操作返回文件内容
- MCP 工具调用返回结构化结果
- 自定义工具返回多模态内容（文本+图片）

**职责：**
- 统一表示工具调用的输出内容
- 支持简单的字符串输出（向后兼容）
- 支持结构化的多模态内容项（Responses API 兼容）
- 作为 `FunctionCallOutputPayload` 的核心字段

## 2. 功能点目的 (Purpose of This Type)

该类型的设计目的是：

1. **向后兼容**：支持传统的纯文本输出格式
2. **多模态支持**：支持文本和图片混合的输出
3. **API 兼容**：与 OpenAI Responses API 的内容格式兼容
4. **灵活性**：允许工具返回复杂结构的内容

## 3. 具体技术实现 (Technical Implementation Details)

### TypeScript 定义

```typescript
export type FunctionCallOutputBody = 
  | string 
  | Array<FunctionCallOutputContentItem>;
```

### Rust 定义

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, TS)]
#[serde(untagged)]
pub enum FunctionCallOutputBody {
    Text(String),
    ContentItems(Vec<FunctionCallOutputContentItem>),
}
```

### 变体说明

| 变体 | 类型 | 说明 |
|------|------|------|
| `Text` | `string` | 纯文本输出（传统格式） |
| `ContentItems` | `FunctionCallOutputContentItem[]` | 结构化内容项数组（Responses API 格式） |

### 序列化格式

使用 `#[serde(untagged)]` 实现无标签联合类型：

```json
// Text 变体
"This is plain text output"

// ContentItems 变体
[
  { "type": "input_text", "text": "Text content" },
  { "type": "input_image", "image_url": "data:image/png;base64,..." }
]
```

### 相关类型

```typescript
export type FunctionCallOutputContentItem = 
  | { "type": "input_text", text: string }
  | { "type": "input_image", image_url: string, detail?: ImageDetail };
```

### 辅助方法（Rust）

```rust
impl FunctionCallOutputBody {
    /// 转换为纯文本（用于人类可读界面）
    pub fn to_text(&self) -> Option<String> {
        match self {
            Self::Text(content) => Some(content.clone()),
            Self::ContentItems(items) => function_call_output_content_items_to_text(items),
        }
    }
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 类型定义
- **TypeScript**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/FunctionCallOutputBody.ts`
- **Rust**: `/home/sansha/Github/codex/codex-rs/protocol/src/models.rs` (lines 1274-1279)

### 相关类型
- `FunctionCallOutputContentItem` - 内容项类型
- `FunctionCallOutputPayload` - 包装 `FunctionCallOutputBody` 并添加 `success` 元数据
- `ResponseInputItem::FunctionCallOutput` - 使用 `FunctionCallOutputPayload`

### 使用位置

1. **函数调用输出**：
   ```rust
   pub struct FunctionCallOutputPayload {
       pub body: FunctionCallOutputBody,
       pub success: Option<bool>,
   }
   ```

2. **响应项**：
   ```rust
   pub enum ResponseInputItem {
       FunctionCallOutput {
           call_id: String,
           output: FunctionCallOutputPayload,
       },
       // ...
   }
   ```

3. **MCP 集成**：`CallToolResult::as_function_call_output_payload()`

### 转换逻辑

```rust
// MCP 内容转换为 FunctionCallOutputContentItem
fn convert_mcp_content_to_items(
    contents: &[serde_json::Value]
) -> Option<Vec<FunctionCallOutputContentItem>> {
    // 解析 MCP 的 text/image 内容
    // 返回 None 如果没有图片（纯文本场景优化）
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 协议集成
- 属于 models 类型（在 `protocol` crate 的 `models.rs` 中定义）
- 通过 `ts-rs` 自动生成 TypeScript 类型
- 使用 untagged 序列化（基于内容类型推断）

### 与 Responses API 的关系

`FunctionCallOutputContentItem` 与 OpenAI Responses API 兼容：

```json
{
  "type": "function_call_output",
  "call_id": "call_123",
  "output": [
    { "type": "input_text", "text": "Command output" },
    { "type": "input_image", "image_url": "data:image/png;base64,..." }
  ]
}
```

### 外部交互

1. **工具执行**：工具返回 `FunctionCallOutputPayload`
2. **序列化**：发送到 OpenAI API 时序列化为 JSON
3. **反序列化**：从 API 响应解析
4. **UI 显示**：转换为文本或渲染图片

### 内容项类型映射

| 来源 | 目标 |
|------|------|
| MCP Text | `FunctionCallOutputContentItem::InputText` |
| MCP Image | `FunctionCallOutputContentItem::InputImage` |
| Shell 输出 | `FunctionCallOutputBody::Text` 或 `ContentItems` |
| 文件内容 | `FunctionCallOutputBody::Text` |

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **Untagged 序列化的歧义**：
   - 纯字符串 `"text"` 和单元素数组 `[{type: "input_text", text: "text"}]` 不同
   - 空字符串 `""` 和空数组 `[]` 的语义差异

2. **图片大小限制**：
   - Base64 编码的图片可能非常大
   - 需要大小限制和压缩策略

3. **to_text 的丢失性**：
   - `to_text()` 方法会丢弃图片内容
   - 仅适用于人类可读界面，不适用于模型输入

4. **Detail 字段可选**：
   - `ImageDetail` 是可选的，默认行为依赖 API

### 改进建议

1. **添加大小限制**：
   ```rust
   pub const MAX_OUTPUT_BODY_SIZE: usize = 10 * 1024 * 1024; // 10MB
   
   impl FunctionCallOutputBody {
       pub fn check_size(&self) -> Result<(), Error> {
           // 验证总大小
       }
   }
   ```

2. **支持更多内容类型**：
   ```rust
   pub enum FunctionCallOutputContentItem {
       InputText { text: String },
       InputImage { image_url: String, detail: Option<ImageDetail> },
       InputFile { file_url: String, mime_type: String },  // 新
       InputJson { data: serde_json::Value },              // 新
   }
   ```

3. **添加元数据**：
   ```rust
   pub struct FunctionCallOutputBody {
       pub content: BodyContent,
       pub metadata: Option<OutputMetadata>,
   }
   
   pub struct OutputMetadata {
       pub content_type: String,
       pub size: usize,
       pub encoding: Option<String>,
   }
   ```

4. **流式输出支持**：
   - 对于大输出，支持分块传输
   - 添加 `Stream<FunctionCallOutputContentItem>` 变体

### 测试建议
- 验证 untagged 序列化的正确性
- 测试大图片的编码和解码
- 验证 `to_text()` 的各种输入
- 测试与 MCP 的集成

### 性能考虑
- 图片 Base64 编码会增加约 33% 的大小
- 考虑在传输前压缩图片
- 对于纯文本场景，优先使用 `Text` 变体
