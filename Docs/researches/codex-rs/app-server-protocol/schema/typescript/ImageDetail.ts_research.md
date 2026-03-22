# ImageDetail Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`ImageDetail` 是 Codex 中用于控制图像处理细节级别的枚举类型。它决定了图像在发送到模型前的预处理方式。

主要使用场景：
- **图像输入**：用户上传图像作为对话输入
- **工具输出**：工具调用返回图像内容
- **质量控制**：平衡图像质量和 Token 消耗

## 2. 功能点目的 (Purpose of This Type)

- **质量控制**：允许用户或系统选择图像处理质量
- **Token 优化**：通过降低细节级别减少 Token 消耗
- **自动优化**：让系统自动选择最佳处理方式
- **原始保留**：支持发送原始图像不进行压缩

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
export type ImageDetail = "auto" | "low" | "high" | "original";
```

```rust
// Rust 定义
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "lowercase")]
pub enum ImageDetail {
    Auto,
    Low,
    High,
    Original,
}
```

### 变体说明

| 变体 | 值 | 说明 |
|-----|---|------|
| `Auto` | `"auto"` | 系统自动选择最佳处理方式 |
| `Low` | `"low"` | 低质量，低 Token 消耗 |
| `High` | `"high"` | 高质量，高 Token 消耗 |
| `Original` | `"original"` | 发送原始图像，不做处理 |

### 使用位置

```rust
// 在 FunctionCallOutputContentItem::InputImage 中使用
pub enum FunctionCallOutputContentItem {
    InputText { text: String },
    InputImage {
        image_url: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        #[ts(optional)]
        detail: Option<ImageDetail>,
    },
}
```

### 图像处理流程

```rust
// codex-utils-image 中的处理
pub fn load_for_prompt_bytes(
    path: &Path,
    file_bytes: Vec<u8>,
    mode: PromptImageMode,  // 与 ImageDetail 相关
) -> Result<PromptImage, ImageProcessingError>;
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/protocol/src/models.rs` (lines 268-275) | Rust 枚举定义 |
| `/codex-rs/app-server-protocol/schema/typescript/ImageDetail.ts` | TypeScript 类型定义（生成） |
| `/codex-rs/utils/image/src/lib.rs` | 图像处理实现 |

### 相关类型

- `PromptImageMode`：内部图像处理模式
- `FunctionCallOutputContentItem`：使用 ImageDetail 作为可选字段

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `serde`：序列化/反序列化，使用 `lowercase` 命名策略
- `ts_rs::TS`：TypeScript 类型生成
- `schemars::JsonSchema`：JSON Schema 生成

### 外部交互

- 图像处理库（如 `image` crate）：实际的图像缩放和编码
- OpenAI API：detail 参数传递给 Responses API

### 序列化示例

```json
// Auto
{ "image_url": "data:image/png;base64,...", "detail": "auto" }

// Low
{ "image_url": "data:image/png;base64,...", "detail": "low" }

// 省略 detail 字段（使用默认值）
{ "image_url": "data:image/png;base64,..." }
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **默认值不明确**：省略时的默认行为取决于具体使用场景
2. **模型支持**：不同模型对图像细节的支持可能不同
3. **Token 计算**：高细节图像可能导致意外的 Token 消耗
4. **处理性能**：Original 模式可能传输大量数据

### 改进建议

1. **添加默认值**：为枚举实现 `Default` trait
   ```rust
   impl Default for ImageDetail {
       fn default() -> Self {
           ImageDetail::Auto
       }
   }
   ```

2. **文档化 Token 影响**：明确各选项对 Token 消耗的影响
3. **添加尺寸限制**：对 Original 模式添加最大尺寸限制
4. **智能选择**：改进 Auto 模式的智能选择算法

### 使用建议

- **默认使用 `Auto`**：让系统根据上下文自动选择
- **关注 Token 消耗**：在高 Token 压力场景使用 `Low`
- **质量优先**：需要精细图像分析时使用 `High`
- **谨慎使用 `Original`**：仅在必要时使用，注意数据大小

### 测试建议

- 测试各 detail 级别的图像处理结果
- 验证 Token 消耗符合预期
- 测试边界尺寸图像的处理
- 验证序列化/反序列化的正确性
