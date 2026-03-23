# image_rollout.rs 深度研究文档

## 场景与职责

`image_rollout.rs` 是 Codex 核心测试套件中验证**图像输入持久化**功能的集成测试文件。该功能确保用户通过复制粘贴或拖拽方式输入的图像能够正确保存到 rollout 文件中，并在后续恢复时保持完整。

测试覆盖两种图像输入方式：
1. **本地图像文件**（LocalImage）：用户复制粘贴本地文件路径
2. **Data URL 图像**（Image）：用户拖拽图像或粘贴 base64 编码图像

## 功能点目的

### 1. 本地图像持久化
- **目的**：验证本地图像文件被正确读取并保存到 rollout
- **机制**：
  - 读取本地图像文件
  - 转换为 base64 data URL
  - 包装在特殊的 XML 标签中

### 2. Data URL 图像持久化
- **目的**：验证直接传入的 data URL 图像正确保存
- **机制**：
  - 直接使用传入的 data URL
  - 包装在标准图像标签中

### 3. Rollout 格式验证
- **目的**：确保图像在 rollout 文件中的格式符合预期
- **验证点**：
  - 图像标签正确包裹
  - URL 格式正确
  - 与其他输入内容顺序正确

## 具体技术实现

### 图像输入类型

```rust
// codex-rs/protocol/src/user_input.rs
pub enum UserInput {
    Text { text: String, text_elements: Vec<TextElement> },
    LocalImage { path: PathBuf },  // 本地图像文件
    Image { image_url: String },   // Data URL 或远程 URL
    // ...
}
```

### 本地图像处理流程

```rust
// 1. 用户提交 LocalImage
UserInput::LocalImage { path: abs_path.clone() }

// 2. 转换为 ResponseItem::Message
ResponseItem::Message {
    role: "user".to_string(),
    content: vec![
        ContentItem::InputText {
            text: codex_protocol::models::local_image_open_tag_text(1),
        },
        ContentItem::InputImage { image_url },  // base64 data URL
        ContentItem::InputText {
            text: codex_protocol::models::image_close_tag_text(),
        },
        ContentItem::InputText {
            text: "pasted image".to_string(),
        },
    ],
    ...
}
```

### 图像标签常量

```rust
// codex-rs/protocol/src/models.rs
pub fn local_image_open_tag_text(index: usize) -> String {
    format!("<local_image index=\"{}\">", index)
}

pub fn image_open_tag_text() -> String {
    "<image>".to_string()
}

pub fn image_close_tag_text() -> String {
    "</image>".to_string()
}
```

### Rollout 条目结构

```rust
// RolloutLine 格式
{
  "item": {
    "type": "message",
    "role": "user",
    "content": [
      {"type": "input_text", "text": "<local_image index=\"1\">"},
      {"type": "input_image", "image_url": "data:image/png;base64,..."},
      {"type": "input_text", "text": "</image>"},
      {"type": "input_text", "text": "pasted image"}
    ]
  }
}
```

### 测试中的图像生成

```rust
use image::ImageBuffer;
use image::Rgba;

fn write_test_png(path: &Path, color: [u8; 4]) -> anyhow::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    // 创建 2x2 像素的测试图像
    let image = ImageBuffer::from_pixel(2, 2, Rgba(color));
    image.save(path)?;
    Ok(())
}

// 使用示例
write_test_png(&abs_path, [12, 34, 56, 255])?;
```

### Rollout 读取与验证

```rust
async fn read_rollout_text(path: &Path) -> anyhow::Result<String> {
    for _ in 0..50 {
        if path.exists()
            && let Ok(text) = std::fs::read_to_string(path)
            && !text.trim().is_empty()
        {
            return Ok(text);
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    std::fs::read_to_string(path)
        .with_context(|| format!("read rollout file at {}", path.display()))
}

fn find_user_message_with_image(text: &str) -> Option<ResponseItem> {
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() { continue; }
        
        let rollout: RolloutLine = match serde_json::from_str(trimmed) {
            Ok(rollout) => rollout,
            Err(_) => continue,
        };
        
        // 查找包含 InputImage 的用户消息
        if let RolloutItem::ResponseItem(ResponseItem::Message { role, content, .. }) = &rollout.item
            && role == "user"
            && content.iter().any(|span| matches!(span, ContentItem::InputImage { .. }))
        {
            return Some(rollout.item.clone());
        }
    }
    None
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/image_rollout.rs` - 本测试文件

### 核心实现
- `codex-rs/protocol/src/user_input.rs` - 用户输入类型
  - `UserInput::LocalImage`
  - `UserInput::Image`

- `codex-rs/protocol/src/models.rs` - 模型类型
  - `ContentItem::InputImage`
  - `ResponseItem::Message`
  - 图像标签辅助函数

- `codex-rs/core/src/rollout/recorder.rs` - Rollout 记录器
  - 持久化图像内容到 JSONL

### 协议类型
- `codex-rs/protocol/src/protocol.rs`
  - `RolloutItem::ResponseItem`
  - `RolloutLine`

### 图像处理
- `image` crate - 测试图像生成

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `codex_protocol::user_input` | 用户输入类型 |
| `codex_protocol::models` | 内容项类型 |
| `codex_protocol::protocol` | Rollout 类型 |
| `core_test_support` | 测试基础设施 |

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `image` crate | 测试 PNG 图像生成 |

### 测试数据
```rust
// 测试用 base64 PNG（1x1 像素，透明）
const TEST_PNG_DATA_URL: &str = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=";
```

### 测试流程
```rust
// 1. 创建测试图像
let abs_path = cwd.path().join("images/paste.png");
write_test_png(&abs_path, [12, 34, 56, 255])?;

// 2. 提交用户回合（包含图像）
codex.submit(Op::UserTurn {
    items: vec![
        UserInput::LocalImage { path: abs_path.clone() },
        UserInput::Text { text: "pasted image".to_string(), ... },
    ],
    ...
}).await?;

// 3. 等待完成并关闭
wait_for_event(&codex, |event| matches!(event, EventMsg::TurnComplete(_))).await;
codex.submit(Op::Shutdown).await?;
wait_for_event(&codex, |event| matches!(event, EventMsg::ShutdownComplete)).await;

// 4. 验证 rollout 内容
let rollout_path = codex.rollout_path().expect("rollout path");
let rollout_text = read_rollout_text(&rollout_path).await?;
let actual = find_user_message_with_image(&rollout_text).expect("...");

// 5. 断言格式正确
assert_eq!(actual, expected);
```

## 风险、边界与改进建议

### 已知风险

1. **图像大小限制**
   - 风险：大图像可能导致 rollout 文件过大
   - 现状：测试中仅使用 2x2 像素小图像

2. **格式支持**
   - 当前：支持 PNG（通过 data URL）
   - 风险：其他格式（JPEG、WebP）支持不明确

3. **并发写入**
   - 风险：rollout 文件并发修改
   - 缓解：单线程测试避免此问题

### 边界情况

1. **图像文件不存在**
   - 处理：应在提交时返回错误

2. **无效图像格式**
   - 处理：图像库应返回错误

3. **超大图像**
   - 风险：base64 编码后超出请求大小限制
   - 需要：图像压缩或缩放

4. **空图像路径**
   - 处理：应在构建 UserInput 时验证

### 改进建议

1. **图像优化**
   - 自动压缩大图像
   - 支持多种格式（JPEG、WebP、GIF）
   - 图像尺寸限制和警告

2. **安全增强**
   - 验证图像内容（防止恶意构造）
   - 限制图像文件访问范围（沙箱内）

3. **用户体验**
   - 图像预览功能
   - 图像大小提示

4. **测试增强**
   - 添加大图像测试
   - 添加并发图像提交测试
   - 添加无效图像格式测试
   - 添加图像恢复测试（从 rollout 恢复后图像完整）

5. **格式标准化**
   - 统一 LocalImage 和 Image 的处理流程
   - 考虑移除 local_image 特殊标签，统一使用 image 标签

6. **元数据保留**
   - 保留原始文件路径（用于调试）
   - 记录图像尺寸信息
