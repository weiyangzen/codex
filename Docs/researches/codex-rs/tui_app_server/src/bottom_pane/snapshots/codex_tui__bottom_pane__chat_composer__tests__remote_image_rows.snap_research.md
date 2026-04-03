# Chat Composer Remote Image Rows Snapshot 研究文档

## 场景与职责

该快照文件测试了聊天编辑器在**远程图片行**状态下的显示。远程图片 URL 显示为不可编辑的行，位于文本编辑区域上方。

### 业务场景
- 用户从历史记录中恢复包含远程图片的消息
- 远程图片 URL 显示为 `[Image #N]` 行
- 用户可以删除这些图片行但不能编辑

## 功能点目的

### 核心功能
1. **远程图片显示**：在历史记录中显示远程图片
2. **行选择**：支持键盘导航选择图片行
3. **删除操作**：支持删除选中的图片行

### UI 设计特点
- 远程图片行显示在输入框上方
- 格式：`[Image #1]`、`[Image #2]`
- 输入框前缀 `>` 位于图片行下方

## 具体技术实现

### 远程图片管理
```rust
pub(crate) struct ChatComposer {
    remote_image_urls: Vec<String>,
    selected_remote_image_index: Option<usize>,
    // ...
}
```

### 布局计算
```rust
fn layout_areas(&self, area: Rect) -> [Rect; 4] {
    // ...
    let remote_images_height = self
        .remote_images_lines(textarea_rect.width)
        .len()
        .try_into()
        .unwrap_or(u16::MAX)
        .min(textarea_rect.height.saturating_sub(1));
    
    let remote_images_rect = Rect {
        x: textarea_rect.x,
        y: textarea_rect.y,
        width: textarea_rect.width,
        height: remote_images_height,
    };
    // ...
}
```

### 键盘导航
```rust
// Up 键：从输入框进入远程图片选择
// Down 键：在图片行间移动，最后一个后返回输入框
// Delete/Backspace：删除选中的图片行
```

## 关键代码路径

### 主要源文件
- `codex-rs/tui/src/bottom_pane/chat_composer.rs`

### 相关测试
- `remote_image_rows` - 本快照
- `remote_image_rows_selected` - 选中状态
- `remote_image_rows_after_delete_first` - 删除第一张后
