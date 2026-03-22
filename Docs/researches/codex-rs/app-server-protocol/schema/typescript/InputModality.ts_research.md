# InputModality Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`InputModality` 是 Codex 中用于描述模型支持的输入模态的枚举类型。它定义了模型可以处理的输入类型，主要用于模型能力声明和输入验证。

主要使用场景：
- **模型能力声明**：模型声明其支持的输入类型
- **输入验证**：验证用户输入是否符合模型支持的范围
- **UI 适配**：根据模型能力调整用户界面
- **功能开关**：控制图像上传等功能的可用性

## 2. 功能点目的 (Purpose of This Type)

- **能力描述**：明确模型支持的输入模态
- **多模态支持**：支持文本和图像等多种输入类型
- **默认值提供**：为向后兼容提供默认模态列表
- **类型安全**：防止无效的模态值

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
export type InputModality = "text" | "image";
```

```rust
// Rust 定义
#[derive(
    Debug,
    Clone,
    Copy,
    PartialEq,
    Eq,
    Serialize,
    Deserialize,
    JsonSchema,
    TS,
    EnumIter,
    Hash,
)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum InputModality {
    /// Plain text turns and tool payloads.
    Text,
    /// Image attachments included in user turns.
    Image,
}

/// Backward-compatible default when `input_modalities` is omitted on the wire.
///
/// Legacy payloads predate modality metadata, so we conservatively assume both text and images are
/// accepted unless a preset explicitly narrows support.
pub fn default_input_modalities() -> Vec<InputModality> {
    vec![InputModality::Text, InputModality::Image]
}
```

### 变体说明

| 变体 | 值 | 说明 |
|-----|---|------|
| `Text` | `"text"` | 纯文本输入和工具负载 |
| `Image` | `"image"` | 用户消息中的图像附件 |

### 关键特性

- **EnumIter**：支持遍历所有变体
- **Hash**：支持用作哈希集合的键
- **默认值函数**：`default_input_modalities()` 返回 `[Text, Image]`
- **向后兼容**：省略时默认假设支持文本和图像

### 使用位置

```rust
// 在 ModelPreset 中使用
pub struct ModelPreset {
    // ...
    pub input_modalities: Vec<InputModality>,
    // ...
}

// 在 ModelInfo 中使用
pub struct ModelInfo {
    // ...
    pub input_modalities: Vec<InputModality>,
    // ...
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/protocol/src/openai_models.rs` (lines 78-91) | Rust 枚举定义和默认值函数 |
| `/codex-rs/app-server-protocol/schema/typescript/InputModality.ts` | TypeScript 类型定义（生成） |

### 相关类型

- `ModelPreset`：模型预设，包含 input_modalities 字段
- `ModelInfo`：模型信息，包含 input_modalities 字段

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `serde`：序列化/反序列化，使用 `lowercase` 命名策略
- `strum_macros`：提供 `EnumIter` 和 `Display` 派生
- `ts_rs::TS`：TypeScript 类型生成
- `schemars::JsonSchema`：JSON Schema 生成

### 序列化示例

```json
// 单个模态
"text"

// 模态数组
["text", "image"]

// 在模型预设中
{
  "id": "gpt-4",
  "input_modalities": ["text", "image"],
  // ...
}
```

### 使用场景

```rust
// 检查模型是否支持图像
fn supports_image(model: &ModelPreset) -> bool {
    model.input_modalities.contains(&InputModality::Image)
}

// 获取默认模态
let modalities = default_input_modalities();  // [Text, Image]
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **扩展性**：当前只有两个变体，未来可能需要添加音频、视频等
2. **组合复杂性**：多模态组合可能产生复杂的验证逻辑
3. **默认值假设**：默认支持图像可能不适用于所有旧模型

### 改进建议

1. **添加音频模态**：支持语音输入
   ```rust
   Audio,
   ```

2. **添加视频模态**：支持视频输入
   ```rust
   Video,
   ```

3. **添加文档模态**：支持 PDF 等文档
   ```rust
   Document,
   ```

4. **添加能力检查方法**：
   ```rust
   impl InputModality {
       pub fn supports_multimodal(&self) -> bool {
           matches!(self, Self::Image | Self::Audio | Self::Video)
       }
   }
   ```

5. **使用 BitFlags**：对于频繁的组合检查，考虑使用位标志
   ```rust
   #[derive(BitFlags)]
   pub struct InputModalities: u8 {
       const Text = 1;
       const Image = 2;
       const Audio = 4;
   }
   ```

### 测试建议

- 测试各变体的序列化/反序列化
- 测试默认值函数
- 测试 EnumIter 遍历
- 验证 Hash 实现的一致性

### 未来扩展

随着多模态模型的发展，可能需要支持：
- 音频输入/输出
- 视频输入
- 文档处理（PDF、Word 等）
- 结构化数据输入
