# FunctionCallOutputContentItem Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`FunctionCallOutputContentItem` 是 Codex 协议中用于**函数调用输出的内容项**类型。它是 Responses API 兼容的内容项子集，支持作为函数调用输出返回给模型。

**典型使用场景：**
- Shell 命令返回文本输出
- 图片查看工具返回图片内容
- MCP 工具返回多模态结果
- 文件读取返回文件内容（文本或图片）

**职责：**
- 定义支持的内容项类型（文本、图片）
- 与 OpenAI Responses API 格式兼容
- 支持多模态工具输出
- 作为 `FunctionCallOutputBody::ContentItems` 的元素

## 2. 功能点目的 (Purpose of This Type)

该类型的设计目的是：

1. **API 兼容性**：与 OpenAI Responses API 的内容项格式保持一致
2. **多模态支持**：支持文本和图片混合输出
3. **结构化数据**：提供比纯字符串更丰富的内容表达能力
4. **可扩展性**：为未来支持更多内容类型预留空间

## 3. 具体技术实现 (Technical Implementation Details)

### TypeScript 定义

```typescript
/**
 * Responses API compatible content items that can be returned by a tool call.
 * This is a subset of ContentItem with the types we support as function call outputs.
 */
export type FunctionCallOutputContentItem = 
  | { "type": "input_text", text: string }
  | { "type": "input_image", image_url: string, detail?: ImageDetail };
```

### Rust 定义

```rust
/// Responses API compatible content items that can be returned by a tool call.
/// This is a subset of ContentItem with the types we support as function call outputs.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum FunctionCallOutputContentItem {
    // Do not rename, these are serialized and used directly in the responses API.
    InputText {
        text: String,
    },
    // Do not rename, these are serialized and used directly in the responses API.
    InputImage {
        image_url: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        #[ts(optional)]
        detail: Option<ImageDetail>,
    },
}
```

### 变体说明

| 变体 | 字段 | 说明 |
|------|------|------|
| `InputText` | `text: string` | 文本内容 |
| `InputImage` | `image_url: string` | 图片 URL（支持 data URL） |
| `InputImage` | `detail?: ImageDetail` | 图片细节级别（可选） |

### ImageDetail 类型

```typescript
export type ImageDetail = "auto" | "low" | "high" | "original";
```

| 值 | 说明 |
|----|------|
| `"auto"` | 自动选择细节级别 |
| `"low"` | 低分辨率（快速） |
| `"high"` | 高分辨率（详细） |
| `"original"` | 原始分辨率 |

### 序列化格式

使用 `#[serde(tag = "type", rename_all = "snake_case")]` 实现 internally tagged union：

```json
// InputText
{
  "type": "input_text",
  "text": "This is the command output"
}

// InputImage
{
  "type": "input_image",
  "image_url": "data:image/png;base64,iVBORw0KGgo...",
  "detail": "high"
}
```

### 辅助函数

```rust
/// 将内容项数组转换为纯文本（用于人类可读界面）
pub fn function_call_output_content_items_to_text(
    content_items: &[FunctionCallOutputContentItem]
) -> Option<String> {
    let text_segments = content_items
        .iter()
        .filter_map(|item| match item {
            FunctionCallOutputContentItem::InputText { text } 
                if !text.trim().is_empty() => Some(text.as_str()),
            _ => None,
        })
        .collect::<Vec<_>>();
    
    if text_segments.is_empty() {
        None
    } else {
        Some(text_segments.join("\n"))
    }
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 类型定义
- **TypeScript**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/FunctionCallOutputContentItem.ts`
- **Rust**: `/home/sansha/Github/codex/codex-rs/protocol/src/models.rs` (lines 1196-1212)

### 相关类型
- `FunctionCallOutputBody` - 包含 `FunctionCallOutputContentItem` 数组
- `ImageDetail` - 图片细节级别枚举
- `ContentItem` - 更通用的内容项类型（superset）

### 使用位置

1. **函数调用输出体**：
   ```rust
   pub enum FunctionCallOutputBody {
       Text(String),
       ContentItems(Vec<FunctionCallOutputContentItem>),
   }
   ```

2. **MCP 转换**：
   ```rust
   fn convert_mcp_content_to_items(
       contents: &[serde_json::Value]
   ) -> Option<Vec<FunctionCallOutputContentItem>>
   ```

3. **动态工具**：`DynamicToolCallOutputContentItem` 的转换

### 与 ContentItem 的关系

```rust
// ContentItem 是更通用的类型
pub enum ContentItem {
    InputText { text: String },
    InputImage { image_url: String },
    OutputText { text: String },
}

// FunctionCallOutputContentItem 是子集（只包含 input_* 变体）
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 协议集成
- 属于 models 类型（在 `protocol` crate 的 `models.rs` 中定义）
- 通过 `ts-rs` 自动生成 TypeScript 类型
- 使用 snake_case 序列化以匹配 OpenAI API

### 与 OpenAI API 的兼容性

字段名称直接用于 OpenAI Responses API：

```json
{
  "type": "function_call_output",
  "call_id": "call_123",
  "output": [
    { "type": "input_text", "text": "File content here" }
  ]
}
```

**重要**：注释明确说明 "Do not rename, these are serialized and used directly in the responses API"

### 外部交互

1. **MCP 工具**：MCP 返回的 content 被转换为 `FunctionCallOutputContentItem`
2. **图片加载**：`codex_utils_image` crate 处理图片加载和转换
3. **序列化**：直接发送到 OpenAI API
4. **UI 显示**：渲染文本和图片

### 转换映射

| 来源类型 | 转换目标 |
|----------|----------|
| MCP Text | `InputText` |
| MCP Image (data URL) | `InputImage` |
| MCP Image (base64) | `InputImage`（构建 data URL） |
| Shell stdout | `InputText` |
| Local image file | `InputImage`（转换为 data URL） |

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **命名约束**：
   - 字段名直接用于 OpenAI API，不能随意更改
   - 序列化格式必须与 API 保持一致

2. **图片大小限制**：
   - `image_url` 可以是 data URL，可能非常大
   - 没有内置的大小验证

3. **Detail 可选性**：
   - `detail` 是可选的，默认行为依赖 API
   - 可能导致不同模型的行为不一致

4. **与 ContentItem 的重复**：
   - `InputText` 和 `InputImage` 在 `ContentItem` 中重复定义
   - 维护时需要同步更新

5. **仅支持输入类型**：
   - 只包含 `input_*` 变体
   - 不支持 `output_text` 等输出类型

### 改进建议

1. **添加验证**：
   ```rust
   impl FunctionCallOutputContentItem {
       pub fn validate(&self) -> Result<(), ValidationError> {
           match self {
               Self::InputImage { image_url, .. } => {
                   // 验证 URL 格式或 data URL 大小
               }
               Self::InputText { text } => {
                   // 验证文本长度
               }
           }
       }
   }
   ```

2. **支持更多内容类型**：
   ```rust
   pub enum FunctionCallOutputContentItem {
       InputText { text: String },
       InputImage { image_url: String, detail: Option<ImageDetail> },
       InputAudio { audio_url: String },  // 新
       InputDocument { document_url: String, mime_type: String },  // 新
   }
   ```

3. **图片优化**：
   ```rust
   pub struct InputImageOptions {
       pub max_width: Option<u32>,
       pub max_height: Option<u32>,
       pub quality: Option<u8>,
   }
   ```

4. **与 ContentItem 的统一**：
   - 考虑使用类型别名或泛型减少重复
   - 或者明确分离职责（输入 vs 输出）

### 测试建议
- 验证序列化格式与 OpenAI API 文档一致
- 测试大图片的 data URL 处理
- 验证 `detail` 字段的各种值
- 测试 MCP 内容的转换

### 性能考虑
- 图片 Base64 编码增加 33% 大小
- 考虑在添加到数组前压缩图片
- 对于纯文本输出，优先使用 `FunctionCallOutputBody::Text` 而非单元素数组
