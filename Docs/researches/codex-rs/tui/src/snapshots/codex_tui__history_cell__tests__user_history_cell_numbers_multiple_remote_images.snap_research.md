# Research Document: User History Cell Numbers Multiple Remote Images Snapshot

## 场景与职责

此快照测试验证 **UserHistoryCell** 组件在渲染包含多张远程图片的用户消息时的行为。当用户上传多张图片并附带描述性文字时，组件需要清晰展示图片引用和消息内容。

该组件负责：
- 展示用户输入的文本消息
- 渲染远程图片 URL 列表（显示为 `[Image #N]` 标签）
- 处理文本换行和缩进
- 保持图片引用与消息内容的视觉关联

## 功能点目的

**主要功能**：验证 UserHistoryCell 对多图片用户消息的渲染效果：

1. **图片编号**：多张图片显示为 `[Image #1]`、`[Image #2]`
2. **消息展示**：用户消息 `"describe both"` 以 `›` 前缀展示
3. **视觉分隔**：图片列表和消息之间有空行分隔
4. **统一缩进**：图片和消息都使用 `"  "` 缩进

**预期输出结构**：
```

  [Image #1]
  [Image #2]

› describe both
```

## 具体技术实现

### 核心数据结构

**UserHistoryCell**（位于 `history_cell.rs` 第 199-206 行）：
```rust
#[derive(Debug)]
pub(crate) struct UserHistoryCell {
    pub message: String,
    pub text_elements: Vec<TextElement>,
    pub local_image_paths: Vec<PathBuf>,
    pub remote_image_urls: Vec<String>,  // 远程图片 URL
}
```

### 渲染流程

**display_lines 方法**（第 288-372 行）：
```rust
impl HistoryCell for UserHistoryCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 1. 计算换行宽度（预留前缀空间）
        let wrap_width = width
            .saturating_sub(LIVE_PREFIX_COLS + 1)
            .max(1);
        
        // 2. 渲染远程图片
        let wrapped_remote_images = if self.remote_image_urls.is_empty() {
            None
        } else {
            Some(adaptive_wrap_lines(
                self.remote_image_urls
                    .iter()
                    .enumerate()
                    .map(|(idx, _url)| {
                        remote_image_display_line(element_style, idx.saturating_add(1))
                    }),
                RtOptions::new(usize::from(wrap_width))
                    .wrap_algorithm(textwrap::WrapAlgorithm::FirstFit),
            ))
        };
        
        // 3. 渲染消息文本
        let wrapped_message = if self.message.is_empty() && self.text_elements.is_empty() {
            None
        } else {
            // 处理文本换行...
        };
        
        // 4. 组装输出
        let mut lines: Vec<Line<'static>> = vec![Line::from("").style(style)];
        
        if let Some(wrapped_remote_images) = wrapped_remote_images {
            lines.extend(prefix_lines(
                wrapped_remote_images,
                "  ".into(),  // 首行前缀
                "  ".into(),  // 续行前缀
            ));
            if wrapped_message.is_some() {
                lines.push(Line::from("").style(style));  // 空行分隔
            }
        }
        
        if let Some(wrapped_message) = wrapped_message {
            lines.extend(prefix_lines(
                wrapped_message,
                "› ".bold().dim(),  // 首行前缀
                "  ".into(),        // 续行前缀
            ));
        }
        
        lines.push(Line::from("").style(style));
        lines
    }
}
```

### 图片标签生成

**remote_image_display_line 函数**（第 274-276 行）：
```rust
fn remote_image_display_line(style: Style, index: usize) -> Line<'static> {
    Line::from(local_image_label_text(index)).style(style)
}
```

**local_image_label_text 函数**（位于 `codex-protocol/src/models.rs`）：
```rust
pub fn local_image_label_text(label_number: usize) -> String {
    format!("[Image #{label_number}]")
}
```

### 样式应用

- 图片标签：`element_style`（青色）
- 消息首行：`"› ".bold().dim()`
- 消息续行：`"  "`
- 空行：使用 `user_message_style()`

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | `UserHistoryCell` 实现（第 199-372 行） |
| `codex-rs/tui/src/history_cell.rs` | `remote_image_display_line`（第 274-276 行） |
| `codex-rs/protocol/src/models.rs` | `local_image_label_text` 函数 |
| `codex-rs/tui/src/wrapping.rs` | `adaptive_wrap_lines` 自适应换行 |
| `codex-rs/tui/src/render/line_utils.rs` | `prefix_lines` 行前缀添加 |

### 测试代码位置

```rust
// history_cell.rs 第 3891-3907 行
#[test]
fn user_history_cell_numbers_multiple_remote_images() {
    let cell = UserHistoryCell {
        message: "describe both".to_string(),
        text_elements: Vec::new(),
        local_image_paths: Vec::new(),
        remote_image_urls: vec![
            "https://example.com/one.png".to_string(),
            "https://example.com/two.png".to_string(),
        ],
    };
    
    let rendered = render_lines(&cell.display_lines(80)).join("\n");
    
    assert!(rendered.contains("[Image #1]"));
    assert!(rendered.contains("[Image #2]"));
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 内部依赖

- **ratatui**: `Line`、`Span` 类型
- **textwrap**: 换行算法
- **codex-protocol**: `TextElement`、`local_image_label_text`

### 数据流

```
用户输入
    ├── message: "describe both"
    ├── remote_image_urls: ["https://.../one.png", "https://.../two.png"]
    └── UserHistoryCell::display_lines
            ├── 渲染图片列表
            │       ├── [Image #1]
            │       └── [Image #2]
            ├── 空行分隔
            └── 渲染消息
                    └── › describe both
```

## 风险、边界与改进建议

### 已知风险

1. **图片数量过多**：大量图片可能导致历史记录过长
2. **URL 长度**：超长 URL 换行后可能破坏布局
3. **图片加载状态**：当前仅显示标签，不显示加载/错误状态

### 边界情况

| 场景 | 当前行为 |
|------|---------|
| 0 张图片 | 仅显示消息 |
| 1 张图片 | 显示 `[Image #1]` |
| 消息为空 | 仅显示图片列表 |
| 图片和消息都为空 | 返回空 Vec |
| 包含 data URL | 同样显示为 `[Image #N]` |

### 改进建议

1. **图片预览**：
   - 支持终端图片协议（iTerm2、Kitty）显示缩略图
   - 提供图片尺寸和格式信息

2. **交互性**：
   - 点击图片标签在新窗口打开原图
   - 支持删除已添加的图片

3. **可访问性**：
   - 为图片添加 alt 文本描述
   - 支持屏幕阅读器朗读图片信息

4. **性能优化**：
   - 延迟加载图片信息
   - 缓存图片元数据

5. **UI 改进**：
   - 图片标签支持悬停显示完整 URL
   - 增加图片删除按钮
