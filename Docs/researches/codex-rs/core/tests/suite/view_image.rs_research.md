# view_image.rs 研究文档

## 场景与职责

`view_image.rs` 是 Codex Core 集成测试套件中专门测试**图像查看工具**的测试文件。该文件全面验证了 `view_image` 工具的各种使用场景，包括用户直接附加本地图像、模型调用 view_image 工具、图像尺寸调整、原始分辨率保留等功能。

### 核心职责

1. **验证图像附加功能**：测试用户通过 `LocalImage` 输入和 `view_image` 工具附加图像
2. **测试图像处理**：验证图像尺寸调整、Base64 编码、格式转换
3. **验证模型能力检测**：确保系统正确检测模型对图像输入的支持
4. **测试错误处理**：验证对无效路径、非图像文件、不支持的操作的处理
5. **验证 JS REPL 集成**：测试通过 JavaScript REPL 动态生成和附加图像

---

## 功能点目的

### 1. 用户回合附加本地图像 (`user_turn_with_local_image_attaches_image`)

**目的**：验证用户可以直接在回合中附加本地图像文件。

**测试逻辑**：
- 创建大尺寸测试图像（2304x864 像素）
- 通过 `UserInput::LocalImage` 提交图像
- 验证请求中包含 `input_image` 类型的消息
- 验证图像被调整为符合模型要求的最大尺寸（2048x768）

**关键断言**：
```rust
assert!(width <= 2048);
assert!(height <= 768);
assert!(width < original_width);  // 确认发生了调整
assert!(height < original_height);
```

### 2. View Image 工具附加图像 (`view_image_tool_attaches_local_image`)

**目的**：验证模型可以通过 `view_image` 工具调用附加图像。

**测试逻辑**：
- 创建测试图像
- 模拟模型调用 `view_image` 工具
- 验证工具输出包含 `input_image` 内容项
- 确认不注入单独的图像消息（与 LocalImage 不同）

**输出验证**：
```rust
assert_eq!(output_items.len(), 1);
assert_eq!(output_items[0].get("type").and_then(Value::as_str), Some("input_image"));
```

### 3. 原始分辨率保留 (`view_image_tool_can_preserve_original_resolution_when_requested_on_gpt5_3_codex`)

**目的**：验证在支持的模型上，可以通过 `detail: "original"` 参数保留图像原始分辨率。

**测试逻辑**：
- 启用 `ImageDetailOriginal` 特性
- 使用 `gpt-5.3-codex` 模型
- 调用 `view_image` 时指定 `detail: "original"`
- 验证图像尺寸保持不变

**关键代码**：
```rust
let arguments = serde_json::json!({ "path": rel_path, "detail": "original" }).to_string();
```

### 4. 不支持 Detail 值的错误处理 (`view_image_tool_errors_clearly_for_unsupported_detail_values`)

**目的**：验证对无效 `detail` 参数值（如 `"low"`）返回清晰的错误信息。

**预期错误消息**：
```
view_image.detail only supports `original`; omit `detail` for default resized behavior, got `low`
```

### 5. Null Detail 处理 (`view_image_tool_treats_null_detail_as_omitted`)

**目的**：验证 `detail: null` 被正确处理为省略参数，使用默认调整大小行为。

### 6. 模型不支持时的回退 (`view_image_tool_resizes_when_model_lacks_original_detail_support`)

**目的**：验证即使启用了 `ImageDetailOriginal` 特性，在不支持的模型上仍会调整图像大小。

### 7. 仅特性启用不强制原始分辨率 (`view_image_tool_does_not_force_original_resolution_with_capability_feature_only`)

**目的**：验证仅启用特性而不指定 `detail: "original"` 时，仍使用默认调整大小。

### 8. JS REPL 图像附加 (`js_repl_emit_image_attaches_local_image`)

**目的**：验证通过 JavaScript REPL 动态生成图像并调用 `emitImage` 附加。

**测试逻辑**：
- 启用 `JsRepl` 特性
- 执行 JS 代码创建图像文件
- 调用 `codex.tool("view_image", { path: imagePath })`
- 调用 `codex.emitImage(out)` 附加图像
- 验证图像被正确附加到输出

### 9. JS REPL 需要显式 Emit (`js_repl_view_image_requires_explicit_emit`)

**目的**：验证仅调用 `view_image` 而不调用 `emitImage` 不会自动附加图像。

### 10. 目录路径错误 (`view_image_tool_errors_when_path_is_directory`)

**目的**：验证当路径指向目录而非文件时返回适当的错误。

**预期错误**：
```
image path `{path}` is not a file
```

### 11. 非图像文件错误 (`view_image_tool_errors_for_non_image_files`)

**目的**：验证对非图像文件（如 JSON）返回 MIME 类型错误。

**预期错误**：
```
unable to process image at `{path}`: unsupported image `application/json`
```

### 12. 文件不存在错误 (`view_image_tool_errors_when_file_missing`)

**目的**：验证对不存在的文件路径返回适当的错误。

### 13. 纯文本模型不支持 (`view_image_tool_returns_unsupported_message_for_text_only_model`)

**目的**：验证纯文本模型（不支持图像输入）调用 `view_image` 时返回友好提示。

**预期消息**：
```
view_image is not allowed because you do not support image inputs
```

### 14. 无效图像替换 (`replaces_invalid_local_image_after_bad_request`)

**目的**：验证当上传的图像被 API 拒绝时，系统会替换为 "Invalid image" 文本并重试。

**测试逻辑**：
- 模拟 API 返回 400 错误（无效图像数据）
- 验证第二次请求不包含图像
- 验证包含 "Invalid image" 文本提示

---

## 具体技术实现

### 关键数据结构

#### `ViewImageArgs`（工具参数）
```rust
#[derive(Deserialize)]
struct ViewImageArgs {
    path: String,
    detail: Option<String>,  // 仅支持 "original" 或省略
}
```

#### `ViewImageDetail`（内部枚举）
```rust
#[derive(Clone, Copy, Eq, PartialEq)]
enum ViewImageDetail {
    Original,
}
```

#### `ViewImageOutput`（工具输出）
```rust
pub struct ViewImageOutput {
    image_url: String,       // data:image/png;base64,... 格式
    image_detail: Option<ImageDetail>,
}
```

### 图像处理流程

#### 1. 图像加载和尺寸调整

```rust
let can_request_original_detail =
    can_request_original_image_detail(turn.features.get(), &turn.model_info);
let use_original_detail =
    can_request_original_detail && matches!(detail, Some(ViewImageDetail::Original));
let image_mode = if use_original_detail {
    PromptImageMode::Original
} else {
    PromptImageMode::ResizeToFit
};

let image = load_for_prompt_bytes(abs_path.as_path(), file_bytes, image_mode)?;
let image_url = image.into_data_url();
```

#### 2. 图像尺寸限制

- **默认模式**：最大 2048x768 像素
- **原始模式**：保留原始尺寸（需要模型支持）

#### 3. 输出格式

```rust
fn to_response_item(&self, call_id: &str, _payload: &ToolPayload) -> ResponseInputItem {
    let body = FunctionCallOutputBody::ContentItems(vec![
        FunctionCallOutputContentItem::InputImage {
            image_url: self.image_url.clone(),
            detail: self.image_detail,
        }
    ]);
    // ...
}
```

### 测试辅助函数

#### 图像消息查找
```rust
fn image_messages(body: &Value) -> Vec<&Value> {
    body.get("input")
        .and_then(Value::as_array)
        .map(|items| {
            items.iter().filter(|item| {
                item.get("type").and_then(Value::as_str) == Some("message")
                    && item.get("content")
                        .and_then(Value::as_array)
                        .map(|content| {
                            content.iter().any(|span| {
                                span.get("type").and_then(Value::as_str) == Some("input_image")
                            })
                        })
                        .unwrap_or(false)
            }).collect()
        })
        .unwrap_or_default()
}
```

#### Base64 解码和验证
```rust
let (prefix, encoded) = image_url.split_once(',').expect("image url contains data prefix");
assert_eq!(prefix, "data:image/png;base64");

let decoded = BASE64_STANDARD.decode(encoded)?;
let resized = load_from_memory(&decoded)?;
let (width, height) = resized.dimensions();
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/tools/handlers/view_image.rs` | `ViewImageHandler` 和 `ViewImageOutput` 实现 |
| `codex-rs/core/src/original_image_detail.rs` | 原始分辨率支持检测 |
| `codex-rs/core/src/features.rs` | 特性标志定义（`ImageDetailOriginal`） |

### 图像处理工具

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/utils/image/src/lib.rs` | `load_for_prompt_bytes`、`PromptImageMode` |

### 协议定义

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/models.rs` | `FunctionCallOutputContentItem::InputImage`、`ImageDetail` |
| `codex-rs/protocol/src/protocol.rs` | `ViewImageToolCallEvent` |

### 关键代码引用

#### ViewImageHandler 实现
```rust
// codex-rs/core/src/tools/handlers/view_image.rs:42-164
#[async_trait]
impl ToolHandler for ViewImageHandler {
    type Output = ViewImageOutput;

    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        // 1. 检查模型是否支持图像输入
        if !invocation.turn.model_info.input_modalities.contains(&InputModality::Image) {
            return Err(FunctionCallError::RespondToModel(VIEW_IMAGE_UNSUPPORTED_MESSAGE.to_string()));
        }
        
        // 2. 解析参数
        let args: ViewImageArgs = parse_arguments(&arguments)?;
        
        // 3. 验证 detail 参数
        let detail = match args.detail.as_deref() {
            None => None,
            Some("original") => Some(ViewImageDetail::Original),
            Some(detail) => return Err(...),
        };
        
        // 4. 加载和处理图像
        // ...
        
        // 5. 发送事件并返回输出
        session.send_event(..., EventMsg::ViewImageToolCall(...)).await;
        Ok(ViewImageOutput { image_url, image_detail })
    }
}
```

#### 原始分辨率支持检测
```rust
// codex-rs/core/src/original_image_detail.rs
pub fn can_request_original_image_detail(features: &Features, model_info: &ModelInfo) -> bool {
    features.is_enabled(Feature::ImageDetailOriginal) && model_info.supports_image_detail_original
}
```

---

## 依赖与外部交互

### 外部依赖

1. **image crate**：图像处理和尺寸调整
2. **base64 crate**：Base64 编码/解码
3. **wiremock**：API 模拟
4. **tempfile**：临时目录

### 内部依赖

1. **codex_utils_image**：图像加载和调整大小工具
2. **codex_protocol**：协议类型
3. **core_test_support**：测试支持

### 模型能力检测

```rust
// 检查模型输入模态
invocation.turn.model_info.input_modalities.contains(&InputModality::Image)

// 检查原始分辨率支持
model_info.supports_image_detail_original
```

### 特性标志

| 特性 | 描述 |
|-----|------|
| `ImageDetailOriginal` | 启用原始分辨率图像支持 |
| `JsRepl` | 启用 JavaScript REPL |

---

## 风险、边界与改进建议

### 已知风险

1. **平台限制**：文件在 Windows 上被排除（`#![cfg(not(target_os = "windows"))]`）
2. **网络依赖**：大多数测试需要网络访问
3. **模型特定**：某些测试依赖特定模型（`gpt-5.3-codex`）
4. **图像尺寸硬编码**：测试使用固定的 2304x864 像素图像

### 边界情况

1. **大图像处理**：超大图像（>10MB）的内存使用未测试
2. **并发图像加载**：多个图像同时处理的性能未测试
3. **格式支持**：仅测试 PNG，其他格式（JPEG、WebP、GIF）覆盖有限
4. **颜色空间**：未测试非 sRGB 颜色空间的图像

### 改进建议

1. **增加测试覆盖率**：
   - 添加更多图像格式（JPEG、WebP、GIF）的测试
   - 测试透明通道处理（PNG alpha）
   - 测试 CMYK 颜色空间转换

2. **性能测试**：
   - 添加大图像处理性能基准
   - 测试并发图像加载的内存使用

3. **错误场景**：
   - 测试损坏的图像文件处理
   - 测试权限不足的文件访问
   - 测试磁盘空间不足的情况

4. **可维护性**：
   - 提取图像创建辅助函数
   - 使用参数化测试减少重复代码
   - 添加图像哈希验证而非仅尺寸检查

### 平台支持

当前测试在 Windows 上被完全排除：
```rust
#![cfg(not(target_os = "windows"))]
```

**建议**：
- 分析 Windows 不支持的原因（可能是路径处理或图像库限制）
- 考虑添加 Windows 特定的测试实现
- 或明确文档说明 Windows 限制

### 相关 TODO

文件中未明确标记 TODO，但测试中有注释说明某些测试在 Bazel/RBE 环境下可能较慢：
```rust
// Empirically, image attachment can be slow under Bazel/RBE.
Duration::from_secs(10),
```
