# 快照研究文档: Chat Composer - Remote Image Rows Selected

## 基本信息
- **快照文件名**: `codex_tui__bottom_pane__chat_composer__tests__remote_image_rows_selected.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **测试函数**: `remote_image_rows_selected_snapshot`
- **对应结构体**: `ChatComposer`

---

## 1. 场景与职责

### 1.1 功能场景
此快照展示了**远程图片行选中状态**，当用户使用键盘导航选择远程图片时显示。具体场景包括：
- 用户按Up键从textarea进入远程图片区域
- 显示当前选中的远程图片
- 用户可以删除选中的图片

### 1.2 业务职责
- **键盘导航**: Up/Down键在远程图片间移动
- **选中指示**: 高亮显示当前选中的图片行
- **删除支持**: Delete/Backspace删除选中图片

---

## 2. 功能点目的

### 2.1 核心功能
| 功能 | 说明 |
|------|------|
| 选中状态 | 高亮显示选中的远程图片行 |
| 键盘导航 | Up/Down移动选择 |
| 删除操作 | Delete/Backspace删除选中图片 |

---

## 3. 具体技术实现

### 3.1 选中索引
```rust
pub(crate) struct ChatComposer {
    selected_remote_image_index: Option<usize>,  // None表示未选中
}
```

### 3.2 键盘处理
```rust
fn handle_key_event(&mut self, key_event: KeyEvent) {
    match key_event.code {
        KeyCode::Up => {
            if self.textarea.cursor_at_start() {
                // 进入远程图片选择模式
                self.selected_remote_image_index = Some(self.remote_image_urls.len() - 1);
            } else if let Some(idx) = self.selected_remote_image_index {
                // 向上移动选择
                self.selected_remote_image_index = Some(idx.saturating_sub(1));
            }
        }
        KeyCode::Delete | KeyCode::Backspace => {
            if let Some(idx) = self.selected_remote_image_index {
                self.remote_image_urls.remove(idx);
                // 重新编号本地图片
                self.relabel_attached_images_and_update_placeholders();
            }
        }
        // ...
    }
}
```

---

## 4. 关键代码路径

### 4.1 选中渲染
```rust
fn render_remote_images(&self, area: Rect, buf: &mut Buffer) {
    for (idx, url) in self.remote_image_urls.iter().enumerate() {
        let is_selected = self.selected_remote_image_index == Some(idx);
        let style = if is_selected { selected_style() } else { default_style() };
        // 渲染...
    }
}
```

---

## 5. 风险边界

### 5.1 边界情况
- 删除最后一个远程图片后的焦点恢复
- 所有远程图片删除后的状态
- 快速连续删除操作
