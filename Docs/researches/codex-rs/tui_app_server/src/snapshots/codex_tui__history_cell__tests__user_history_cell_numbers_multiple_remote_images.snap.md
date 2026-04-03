# UserHistoryCell 多远程图片编号渲染测试

## 场景与职责

该快照测试验证 `UserHistoryCell` 在处理包含多张远程图片的用户输入时的渲染行为。当用户通过对话界面提交包含多个远程图片URL的消息时，TUI需要正确地：

1. 为每张远程图片显示编号标签（如 `[Image #1]`、`[Image #2]`）
2. 将图片标签与用户的文本消息一起渲染
3. 保持适当的视觉分隔和格式

这是Codex TUI中用户输入历史展示的核心功能，支持多模态交互（文本+图片）。

## 功能点目的

### 核心功能
- **远程图片标签化**：将远程图片URL转换为简洁的 `[Image #N]` 标签，避免在界面中显示冗长的URL
- **多图片支持**：正确处理多张图片，按顺序编号
- **图文混排**：将图片标签与用户文本消息一起渲染，保持可读性

### 测试覆盖场景
测试用例创建了一个包含两张远程图片和一条文本消息的场景：
```rust
UserHistoryCell {
    message: "describe both".to_string(),
    text_elements: Vec::new(),
    local_image_paths: Vec::new(),
    remote_image_urls: vec![
        "https://example.com/one.png".to_string(),
        "https://example.com/two.png".to_string(),
    ],
}
```

## 具体技术实现

### 数据结构
```rust
#[derive(Debug)]
pub(crate) struct UserHistoryCell {
    pub message: String,
    pub text_elements: Vec<TextElement>,
    pub local_image_paths: Vec<PathBuf>,
    pub remote_image_urls: Vec<String>,
}
```

### 渲染流程

1. **图片标签生成**（`display_lines` 方法，第299-312行）：
   ```rust
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
   ```

2. **标签文本生成**（`remote_image_display_line` 函数，第274-276行）：
   ```rust
   fn remote_image_display_line(style: Style, index: usize) -> Line<'static> {
       Line::from(local_image_label_text(index)).style(style)
   }
   ```
   其中 `local_image_label_text` 来自 `codex_protocol::models` 模块。

3. **行前缀处理**（第350-359行）：
   ```rust
   if let Some(wrapped_remote_images) = wrapped_remote_images {
       lines.extend(prefix_lines(
           wrapped_remote_images,
           "  ".into(),
           "  ".into(),
       ));
       if wrapped_message.is_some() {
           lines.push(Line::from("").style(style));
       }
   }
   ```

4. **消息文本渲染**（第361-367行）：
   ```rust
   if let Some(wrapped_message) = wrapped_message {
       lines.extend(prefix_lines(
           wrapped_message,
           "› ".bold().dim(),
           "  ".into(),
       ));
   }
   ```

### 快照输出解析
```
  [Image #1]
  [Image #2]

› describe both
```

- 图片标签使用两个空格缩进（`"  "`）
- 图片标签与消息之间有一个空行
- 用户消息使用 `› ` 作为前缀（粗体+暗淡样式）
- 消息续行使用两个空格缩进

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | `UserHistoryCell` 实现，第199-372行 |
| `codex-rs/tui/src/history_cell.rs:274-276` | `remote_image_display_line` 函数 |
| `codex-rs/tui/src/history_cell.rs:288-372` | `HistoryCell for UserHistoryCell` trait实现 |

### 依赖模块
| 模块 | 用途 |
|-----|------|
| `codex_protocol::models::local_image_label_text` | 生成 `[Image #N]` 标签文本 |
| `crate::wrapping::adaptive_wrap_lines` | 自适应文本换行 |
| `crate::render::line_utils::prefix_lines` | 为行添加前缀 |

### 测试代码位置
- 文件：`codex-rs/tui/src/history_cell.rs`
- 行号：3891-3907
- 测试函数：`user_history_cell_numbers_multiple_remote_images`

## 依赖与外部交互

### 外部依赖
1. **ratatui**：文本渲染、样式、Line/Span结构
2. **textwrap**：文本换行算法
3. **codex_protocol**：`local_image_label_text` 函数

### 内部依赖
- `crate::wrapping` 模块：自适应换行逻辑
- `crate::render::line_utils` 模块：行工具函数
- `crate::style` 模块：样式定义

### 数据流
```
UserHistoryCell {
    remote_image_urls: ["url1", "url2"],
    message: "describe both"
}
    ↓
remote_image_display_line() → [Image #1], [Image #2]
    ↓
prefix_lines() + adaptive_wrap_lines()
    ↓
渲染输出:
  [Image #1]
  [Image #2]

› describe both
```

## 风险、边界与改进建议

### 潜在风险

1. **图片数量过多时的性能**
   - 当前实现会为每张图片生成一行，当图片数量很多时可能导致历史记录过长
   - 建议：考虑对大量图片进行折叠或摘要显示

2. **URL隐私泄露**
   - 虽然显示的是 `[Image #N]` 标签，但原始URL仍存储在内存中
   - 在日志或调试输出中可能意外暴露

3. **编号不一致**
   - 使用 `idx.saturating_add(1)` 进行编号，在极端情况下（usize溢出）可能行为异常
   - 实际场景中不太可能发生，因为图片数量受API限制

### 边界情况

| 场景 | 当前行为 | 建议 |
|-----|---------|------|
| 空图片列表 | 跳过图片渲染，只显示消息 | ✅ 合理 |
| 空消息 | 只显示图片标签 | ✅ 合理 |
| 图片+消息都为空 | 返回空Vec | ✅ 合理 |
| 单张图片 | 显示 `[Image #1]` | ✅ 合理 |

### 改进建议

1. **添加图片URL悬停提示**
   ```rust
   // 可考虑在标签上添加URL作为悬停提示
   Span::styled(label).with_url(url.clone())
   ```

2. **支持图片预览指示器**
   - 对于支持的终端，可以添加图片预览功能
   - 在标签旁添加小图标表示可预览

3. **优化大量图片的显示**
   ```rust
   const MAX_DISPLAYED_IMAGES: usize = 10;
   if remote_image_urls.len() > MAX_DISPLAYED_IMAGES {
       // 显示前N张 + "...and X more"
   }
   ```

4. **添加点击/选择支持**
   - 允许用户选择图片标签查看原始URL
   - 支持在浏览器中打开图片链接

### 相关测试覆盖
- `user_history_cell_renders_remote_image_urls`：单张图片场景
- `user_history_cell_summarizes_inline_data_urls`：Data URL场景
- `user_history_cell_height_matches_rendered_lines_with_remote_images`：高度计算验证
