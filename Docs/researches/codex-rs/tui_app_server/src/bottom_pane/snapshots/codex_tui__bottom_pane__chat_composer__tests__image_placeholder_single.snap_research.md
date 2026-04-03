# Chat Composer Image Placeholder Single Snapshot 研究文档

## 场景与职责

该快照文件测试了聊天编辑器在**单张图片附件**状态下的显示。当用户附加一张图片时，编辑器显示图片占位符。

### 业务场景
- 用户粘贴或附加一张图片
- 编辑器显示 `[Image #1]` 占位符
- 图片作为附件随消息一起发送

## 功能点目的

### 核心功能
1. **图片占位符**：使用 `[Image #N]` 格式标识图片附件
2. **编号管理**：自动为图片分配编号
3. **附件追踪**：跟踪本地和远程图片附件

### UI 设计特点
- 占位符格式：`[Image #1]`
- 占位符作为不可编辑元素插入
- 底部显示上下文剩余百分比

## 具体技术实现

### 图片附件结构
```rust
#[derive(Clone, Debug, PartialEq)]
struct AttachedImage {
    placeholder: String,  // "[Image #1]"
    path: PathBuf,        // 本地图片路径
}

pub(crate) struct ChatComposer {
    attached_images: Vec<AttachedImage>,
    remote_image_urls: Vec<String>,
    // ...
}
```

### 图片附加流程
```rust
fn attach_image(&mut self, path: PathBuf) {
    let placeholder = self.next_image_placeholder();
    self.attached_images.push(AttachedImage {
        placeholder: placeholder.clone(),
        path,
    });
    self.textarea.insert_element(&placeholder);
}

fn next_image_placeholder(&mut self) -> String {
    let remote_count = self.remote_image_urls.len();
    let local_index = self.attached_images.len() + 1;
    format!("[Image #{}]", remote_count + local_index)
}
```

### 远程图片处理
```rust
pub(crate) fn set_remote_image_urls(&mut self, urls: Vec<String>) {
    self.remote_image_urls = urls;
    self.selected_remote_image_index = None;
    self.relabel_attached_images_and_update_placeholders();
    self.sync_popups();
}
```

## 关键代码路径

### 主要源文件
- `codex-rs/tui/src/bottom_pane/chat_composer.rs`

### 相关测试
- `image_placeholder_single` - 本快照（单张图片）
- `image_placeholder_multiple` - 多张图片
- `remote_image_rows` - 远程图片行
- `remote_image_rows_selected` - 选中的远程图片
- `remote_image_rows_after_delete_first` - 删除后的远程图片
