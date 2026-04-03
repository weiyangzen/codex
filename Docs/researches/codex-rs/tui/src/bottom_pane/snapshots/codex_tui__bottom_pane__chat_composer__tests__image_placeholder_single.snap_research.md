# 快照研究文档: Chat Composer - Image Placeholder Single

## 基本信息
- **快照文件名**: `codex_tui__bottom_pane__chat_composer__tests__image_placeholder_single.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **测试函数**: `image_placeholder_single_snapshot`
- **对应结构体**: `ChatComposer`

---

## 1. 场景与职责

### 1.1 功能场景
此快照展示了**单张图片附件的界面状态**，当用户粘贴或附加一张图片时显示。具体场景包括：
- 用户粘贴图片路径
- 系统检测到图片并创建附件
- 在输入框中显示图片占位符

### 1.2 业务职责
- **图片识别**: 检测粘贴内容是否为图片路径
- **附件管理**: 创建本地图片附件
- **占位符显示**: 用"[Image #N]"表示图片附件

---

## 2. 功能点目的

### 2.1 核心功能
| 功能 | 说明 |
|------|------|
| 图片检测 | 通过文件扩展名和维度检测图片 |
| 占位符显示 | "[Image #1]"表示第一张图片 |
| 附件追踪 | 维护attached_images列表 |

### 2.2 显示内容
```
› [Image #1]
```

---

## 3. 具体技术实现

### 3.1 图片检测
```rust
pub fn handle_paste_image_path(&mut self, pasted: String) -> bool {
    let Some(path_buf) = normalize_pasted_path(&pasted) else {
        return false;
    };
    
    match image::image_dimensions(&path_buf) {
        Ok((width, height)) => {
            self.attach_image(path_buf);
            true
        }
        Err(_) => false,
    }
}
```

### 3.2 图片附加
```rust
fn attach_image(&mut self, path: PathBuf) {
    let placeholder = format!("[Image #{}]", self.remote_image_urls.len() + self.attached_images.len() + 1);
    self.attached_images.push(AttachedImage {
        placeholder: placeholder.clone(),
        path,
    });
    self.textarea.insert_element(&placeholder);
}
```

### 3.3 数据结构
```rust
struct AttachedImage {
    placeholder: String,
    path: PathBuf,
}
```

---

## 4. 关键代码路径

### 4.1 图片编号
- 远程图片（remote_image_urls）先编号
- 本地图片（attached_images）后编号
- 统一使用"[Image #N]"格式

---

## 5. 风险边界

### 5.1 边界情况
- 图片文件不存在
- 图片格式不支持
- 大图片文件处理
