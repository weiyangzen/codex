# Research Document: User History Cell Renders Remote Image URLs Snapshot

## 场景与职责

此快照测试验证 **UserHistoryCell** 组件在渲染包含单张远程图片的用户消息时的基本行为。这是图片上传功能的最基础场景，确保图片引用能正确显示并与消息文本关联。

该组件负责：
- 识别并展示远程图片 URL
- 将图片 URL 转换为友好的 `[Image #N]` 标签
- 保持消息文本与图片引用的视觉关联
- 支持 data URL（Base64 编码的图片）

## 功能点目的

**主要功能**：验证 UserHistoryCell 对单图片用户消息的渲染效果：

1. **图片标签化**：将远程 URL 显示为 `[Image #1]` 而非原始 URL
2. **消息关联**：用户消息 `"describe these"` 与图片标签关联展示
3. **视觉层次**：空行分隔图片和消息，消息以 `›` 前缀标识
4. **隐私保护**：不直接暴露完整 URL

**预期输出结构**：
```

  [Image #1]

› describe these
```

## 具体技术实现

### 图片标签生成

**remote_image_display_line 函数**：
```rust
fn remote_image_display_line(style: Style, index: usize) -> Line<'static> {
    Line::from(local_image_label_text(index)).style(style)
}
```

**local_image_label_text 函数**：
```rust
// codex-protocol/src/models.rs
pub fn local_image_label_text(label_number: usize) -> String {
    format!("[Image #{label_number}]")
}
```

### 渲染流程

**关键代码**（`UserHistoryCell::display_lines`）：
```rust
// 1. 渲染远程图片列表
let wrapped_remote_images = if self.remote_image_urls.is_empty() {
    None
} else {
    Some(adaptive_wrap_lines(
        self.remote_image_urls
            .iter()
            .enumerate()
            .map(|(idx, _url)| {
                // idx 从 0 开始，显示时 +1
                remote_image_display_line(element_style, idx.saturating_add(1))
            }),
        RtOptions::new(usize::from(wrap_width))
            .wrap_algorithm(textwrap::WrapAlgorithm::FirstFit),
    ))
};

// 2. 应用缩进
if let Some(wrapped_remote_images) = wrapped_remote_images {
    lines.extend(prefix_lines(
        wrapped_remote_images,
        "  ".into(),  // 首行前缀：2 空格
        "  ".into(),  // 续行前缀：2 空格
    ));
    if wrapped_message.is_some() {
        lines.push(Line::from("").style(style));  // 空行分隔
    }
}
```

### 特殊处理：Data URL

```rust
// 测试代码中验证 data URL 同样显示为 [Image #1]
#[test]
fn user_history_cell_summarizes_inline_data_urls() {
    let cell = UserHistoryCell {
        message: "describe inline image".to_string(),
        text_elements: Vec::new(),
        local_image_paths: Vec::new(),
        remote_image_urls: vec!["data:image/png;base64,aGVsbG8=".to_string()],
    };
    // 断言：显示 [Image #1] 而非完整 data URL
}
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | `UserHistoryCell` 实现（第 288-372 行） |
| `codex-rs/tui/src/history_cell.rs` | `remote_image_display_line`（第 274-276 行） |
| `codex-rs/protocol/src/models.rs` | `local_image_label_text` 函数 |
| `codex-rs/tui/src/history_cell.rs` | 测试用例（第 3860-3873 行） |

### 测试代码位置

```rust
// history_cell.rs 第 3860-3873 行
#[test]
fn user_history_cell_renders_remote_image_urls() {
    let cell = UserHistoryCell {
        message: "describe these".to_string(),
        text_elements: Vec::new(),
        local_image_paths: Vec::new(),
        remote_image_urls: vec!["https://example.com/example.png".to_string()],
    };
    
    let rendered = render_lines(&cell.display_lines(80)).join("\n");
    
    assert!(rendered.contains("[Image #1]"));
    assert!(rendered.contains("describe these"));
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 内部依赖

- **codex-protocol**: `local_image_label_text`
- **ratatui**: 文本渲染

### 支持的图片 URL 类型

| 类型 | 示例 | 显示 |
|------|------|------|
| HTTP(S) URL | `https://example.com/img.png` | `[Image #1]` |
| Data URL | `data:image/png;base64,...` | `[Image #1]` |
| 本地路径 | （通过 `local_image_paths`） | 单独处理 |

## 风险、边界与改进建议

### 已知风险

1. **URL 隐私**：虽然隐藏了 URL，但日志中可能仍保留完整 URL
2. **图片验证**：不验证 URL 是否指向有效图片
3. **重复添加**：同一 URL 多次添加会显示多个标签

### 边界情况

| 场景 | 当前行为 |
|------|---------|
| URL 为空字符串 | 仍显示 `[Image #1]` |
| URL 格式无效 | 仍显示 `[Image #1]` |
| 消息为空 | 仅显示 `[Image #1]` |
| 同时有本地和远程图片 | 分别处理，编号独立 |

### 改进建议

1. **URL 验证**：
   - 验证 URL 格式有效性
   - 检查图片 MIME 类型

2. **去重**：
   - 相同 URL 只显示一个标签
   - 提供重复提示

3. **元数据展示**：
   - 悬停显示图片尺寸
   - 显示文件大小

4. **错误处理**：
   - 无效 URL 显示警告图标
   - 加载失败显示错误状态
