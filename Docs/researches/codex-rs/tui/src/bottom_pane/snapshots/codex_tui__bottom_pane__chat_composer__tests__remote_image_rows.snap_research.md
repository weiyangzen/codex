# 快照研究文档: Chat Composer - Remote Image Rows

## 基本信息
- **快照文件名**: `codex_tui__bottom_pane__chat_composer__tests__remote_image_rows.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **测试函数**: `remote_image_rows_snapshot`
- **对应结构体**: `ChatComposer`

---

## 1. 场景与职责

### 1.1 功能场景
此快照展示了**远程图片行显示界面**，当从历史记录恢复或从服务器获取远程图片URL时显示。具体场景包括：
- 用户回溯历史消息包含远程图片
- 远程图片以独立行显示在textarea上方
- 用户可以删除不需要的远程图片

### 1.2 业务职责
- **远程图片展示**: 在历史记录中显示远程图片附件
- **独立行渲染**: 远程图片与输入文本分开显示
- **删除支持**: 支持选择并删除远程图片

---

## 2. 功能点目的

### 2.1 核心功能
| 功能 | 说明 |
|------|------|
| 远程图片行 | 在textarea上方显示远程图片占位符 |
| 编号显示 | "[Image #1]", "[Image #2]" |
| 文本输入 | textarea中可输入描述文字 |

### 2.2 布局结构
```
  [Image #1]
  [Image #2]

› describe these
```

---

## 3. 具体技术实现

### 3.1 布局计算
```rust
fn layout_areas(&self, area: Rect) -> [Rect; 4] {
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

### 3.2 远程图片渲染
```rust
fn render_remote_images(&self, area: Rect, buf: &mut Buffer) {
    for (idx, url) in self.remote_image_urls.iter().enumerate() {
        let line = format!("  [Image #{}]", idx + 1);
        // 渲染到对应位置
    }
}
```

---

## 4. 关键代码路径

### 4.1 远程图片设置
```rust
pub(crate) fn set_remote_image_urls(&mut self, urls: Vec<String>) {
    self.remote_image_urls = urls;
    self.selected_remote_image_index = None;
    self.relabel_attached_images_and_update_placeholders();
    self.sync_popups();
}
```

---

## 5. 风险边界

### 5.1 边界情况
- 大量远程图片的滚动
- 远程图片URL失效
- 远程图片与本地图片编号冲突
