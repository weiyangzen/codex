# 快照研究文档: Chat Composer - Image Placeholder Multiple

## 基本信息
- **快照文件名**: `codex_tui__bottom_pane__chat_composer__tests__image_placeholder_multiple.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **测试函数**: `image_placeholder_multiple_snapshot`
- **对应结构体**: `ChatComposer`

---

## 1. 场景与职责

### 1.1 功能场景
此快照展示了**多张图片附件的界面状态**，当用户附加多张图片时显示。具体场景包括：
- 用户连续粘贴多张图片
- 需要显示多个图片占位符
- 占位符按顺序编号

### 1.2 业务职责
- **多附件管理**: 维护多个图片附件
- **顺序编号**: 为每个图片分配唯一编号
- **批量显示**: 在同一行显示多个占位符

---

## 2. 功能点目的

### 2.1 核心功能
| 功能 | 说明 |
|------|------|
| 多图片支持 | 支持附加多张图片 |
| 连续编号 | "[Image #1]", "[Image #2]" |
| 紧凑显示 | 多个占位符连续显示 |

### 2.2 显示内容
```
› [Image #1][Image #2]
```

---

## 3. 具体技术实现

### 3.1 编号逻辑
```rust
fn next_image_number(&self) -> usize {
    self.remote_image_urls.len() + self.attached_images.len() + 1
}
```

### 3.2 重新编号
当远程图片被删除时，本地图片占位符需要重新编号：
```rust
fn relabel_attached_images_and_update_placeholders(&mut self) {
    let remote_count = self.remote_image_urls.len();
    for (idx, img) in self.attached_images.iter_mut().enumerate() {
        let new_placeholder = format!("[Image #{}]", remote_count + idx + 1);
        // 更新textarea中的占位符
        self.textarea.replace_element(&img.placeholder, &new_placeholder);
        img.placeholder = new_placeholder;
    }
}
```

---

## 4. 关键代码路径

### 4.1 测试逻辑
```rust
#[test]
fn image_placeholder_multiple_snapshot() {
    composer.attach_image(PathBuf::from("/tmp/img1.png"));
    composer.attach_image(PathBuf::from("/tmp/img2.png"));
}
```

---

## 5. 风险边界

### 5.1 边界情况
- 大量图片附件的性能
- 占位符编号冲突
- 图片路径验证
