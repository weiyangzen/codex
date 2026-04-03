# 研究文档：user_history_cell_numbers_multiple_remote_images.snap

## 场景与职责

此快照测试验证用户历史记录单元格中多个远程图片的编号显示。当用户上传多张远程图片时，每张图片应该有唯一的编号标识。

## 功能点目的

1. **图片编号**：为多张图片分配编号（[Image #1], [Image #2]...）
2. **清晰标识**：用户可以引用特定图片
3. **批量处理**：支持同时显示多张图片

## 具体技术实现

### 快照输出分析

```

  [Image #1]
  [Image #2]

› describe both
```

设计特点：
- 每张图片单独一行显示
- 使用 `[Image #N]` 格式编号
- 用户提示语在图片列表之后

### 图片处理逻辑

```rust
fn render_user_images(images: &[RemoteImage]) -> Vec<Line> {
    let mut lines = vec![];
    
    for (i, image) in images.iter().enumerate() {
        let label = format!("[Image #{}]", i + 1);
        lines.push(Line::from(label));
    }
    
    lines
}
```

## 关键代码路径与文件引用

1. **用户单元格**：
   - `codex-rs/tui/src/history_cell.rs` - UserHistoryCell

2. **图片类型**：
   - `codex_protocol::models::WebSearchAction`
   - `codex_protocol::models::local_image_label_text`

## 依赖与外部交互

### 图片处理
- `image::DynamicImage` - 图片处理
- `image::ImageReader` - 图片读取

## 风险、边界与改进建议

### 潜在风险
1. **图片过多**：大量图片可能导致显示过长
2. **编号混淆**：用户可能混淆图片编号

### 边界情况
1. 单张图片
2. 大量图片（>10）
3. 图片加载失败

### 改进建议
1. 添加图片缩略图预览
2. 支持图片网格布局
3. 添加图片元信息显示（尺寸、格式）
4. 支持点击复制图片 URL
