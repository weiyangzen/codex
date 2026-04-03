# 研究文档：user_history_cell_renders_remote_image_urls.snap

## 场景与职责

此快照测试验证用户历史记录单元格中单张远程图片的显示。当用户上传单张远程图片时，应该正确显示图片标识。

## 功能点目的

1. **单图片显示**：正确显示单张远程图片
2. **URL 处理**：处理远程图片 URL
3. **简洁显示**：单张图片时保持简洁

## 具体技术实现

### 快照输出分析

```

  [Image #1]

› describe these
```

设计特点：
- 单张图片使用 `[Image #1]` 标识
- 用户提示语紧随其后

### 远程图片处理

```rust
pub struct RemoteImage {
    pub url: String,
    pub alt_text: Option<String>,
}

fn render_remote_image(image: &RemoteImage, index: usize) -> Line {
    Line::from(format!("[Image #{}]", index + 1))
}
```

## 关键代码路径与文件引用

1. **图片渲染**：
   - `codex-rs/tui/src/history_cell.rs`
   - `codex_protocol::models`

## 依赖与外部交互

### 图片加载
- `base64::Engine` - base64 编码
- `std::io::Cursor` - 内存缓冲区

## 风险、边界与改进建议

### 边界情况
1. 无效的图片 URL
2. 图片加载超时
3. 不支持的图片格式

### 改进建议
1. 添加图片加载状态指示
2. 显示图片尺寸信息
3. 支持图片预览
