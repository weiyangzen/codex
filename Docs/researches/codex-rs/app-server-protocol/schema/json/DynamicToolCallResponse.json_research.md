# DynamicToolCallResponse.json 研究文档

## 场景与职责

`DynamicToolCallResponse` 是 Codex App-Server 协议中用于**响应动态工具调用请求**的结构。当客户端完成动态工具的执行后，通过此结构向服务器返回执行结果。

该类型属于 **Client → Server** 的响应流，是 `DynamicToolCall` 请求的预期响应类型。

### 使用场景

1. **工具执行成功**：返回工具执行的结果内容
2. **多模态输出**：支持文本和图像等多种输出类型
3. **执行失败报告**：通过 `success` 字段指示执行是否成功

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `contentItems` | DynamicToolCallOutputContentItem[] | ✅ | 输出内容项列表 |
| `success` | boolean | ✅ | 执行是否成功 |

### 内容项类型

`DynamicToolCallOutputContentItem` 支持以下变体：

#### 1. 文本输入（InputText）
```json
{
  "type": "inputText",
  "text": "string"
}
```

#### 2. 图像输入（InputImage）
```json
{
  "type": "inputImage",
  "imageUrl": "string"
}
```

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct DynamicToolCallResponse {
    pub content_items: Vec<DynamicToolCallOutputContentItem>,
    pub success: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum DynamicToolCallOutputContentItem {
    #[serde(rename_all = "camelCase")]
    InputText { text: String },
    #[serde(rename_all = "camelCase")]
    InputImage { image_url: String },
}
```

### 与 Core 类型的转换

```rust
impl From<DynamicToolCallOutputContentItem>
    for codex_protocol::dynamic_tools::DynamicToolCallOutputContentItem
{
    fn from(item: DynamicToolCallOutputContentItem) -> Self {
        match item {
            DynamicToolCallOutputContentItem::InputText { text } => Self::InputText { text },
            DynamicToolCallOutputContentItem::InputImage { image_url } => {
                Self::InputImage { image_url }
            }
        }
    }
}

impl From<codex_protocol::dynamic_tools::DynamicToolCallOutputContentItem>
    for DynamicToolCallOutputContentItem
{
    fn from(item: codex_protocol::dynamic_tools::DynamicToolCallOutputContentItem) -> Self {
        match item {
            codex_protocol::dynamic_tools::DynamicToolCallOutputContentItem::InputText { text } => {
                Self::InputText { text }
            }
            codex_protocol::dynamic_tools::DynamicToolCallOutputContentItem::InputImage {
                image_url,
            } => Self::InputImage { image_url },
        }
    }
}
```

### 序列化示例

```rust
// 测试代码片段（来自 v2.rs 行 7766-7819）
let value = serde_json::to_value(DynamicToolCallResponse {
    content_items: vec![
        DynamicToolCallOutputContentItem::InputText {
            text: "dynamic-ok".to_string(),
        },
        DynamicToolCallOutputContentItem::InputImage {
            image_url: "data:image/png;base64,AAA".to_string(),
        },
    ],
    success: true,
})?;

// 输出：
// {
//   "contentItems": [
//     { "type": "inputText", "text": "dynamic-ok" },
//     { "type": "inputImage", "imageUrl": "data:image/png;base64,AAA" }
//   ],
//   "success": true
// }
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 主类型定义（行 5633-5650） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 单元测试（行 7766-7819） |

### 使用方

| 文件 | 说明 |
|------|------|
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | TUI 构造动态工具响应 |
| `codex-rs/app-server/tests/suite/v2/dynamic_tools.rs` | 动态工具测试 |

---

## 依赖与外部交互

### 依赖类型

```rust
// 来自 codex_protocol crate
use codex_protocol::dynamic_tools::DynamicToolCallOutputContentItem as CoreDynamicToolCallOutputContentItem;
```

### 序列化特性

- 使用 `#[serde(tag = "type")]` 实现内部标签式的枚举序列化
- 字段使用 camelCase 命名（`image_url` → `imageUrl`）

---

## 风险、边界与改进建议

### 已知风险

1. **内容项为空**：`contentItems` 为空数组时，`success` 字段的语义不明确
2. **图像 URL 格式**：`imageUrl` 可以是任意字符串，没有格式验证（如 data URI、HTTP URL）

### 边界情况

1. **失败时的内容**：`success: false` 时，`contentItems` 可能包含错误信息或为空
2. **混合内容类型**：目前支持文本和图像混合，但顺序可能影响模型理解
3. **大图像处理**：base64 编码的大图像可能导致 JSON 体积过大

### 改进建议

1. **错误信息标准化**：考虑在失败时支持标准化的错误信息格式：
   ```rust
   pub enum DynamicToolCallOutputContentItem {
       InputText { text: String },
       InputImage { image_url: String },
       Error { code: String, message: String },  // 新增
   }
   ```

2. **内容类型扩展**：考虑添加更多内容类型：
   - `InputFile` - 文件引用
   - `InputJson` - 结构化数据
   - `InputMarkdown` - Markdown 格式文本

3. **元数据支持**：添加可选的元数据字段：
   ```json
   {
     "type": "inputImage",
     "imageUrl": "...",
     "metadata": {
       "mimeType": "image/png",
       "width": 1024,
       "height": 768
     }
   }
   ```

4. **成功时可选内容**：允许 `success: true` 但 `contentItems` 为空（如副作用-only 工具）

5. **分页支持**：对于可能产生大量输出的工具，考虑支持分页或流式响应
