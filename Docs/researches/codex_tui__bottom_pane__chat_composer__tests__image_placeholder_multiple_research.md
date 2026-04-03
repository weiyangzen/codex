# Chat Composer - Image Placeholder Multiple 研究报告

## 1. 场景与职责

### UI场景
该快照展示了 **Chat Composer** 组件在 **多张图片附件** 场景下的渲染效果。当用户通过粘贴或拖拽添加了多张图片到输入区域时，系统会在文本区域显示 `[Image #1][Image #2]` 等占位符，表示这些位置将插入图片。

### 组件职责
- **图片占位符管理**: 为每张附加图片生成唯一占位符
- **图片编号**: 为本地和远程图片维护统一的编号系统
- **占位符渲染**: 在文本区域渲染不可编辑的图片占位符
- **图片操作**: 支持通过键盘选择和管理图片

## 2. 功能点目的

### 核心功能
1. **占位符生成**: 为每张图片生成 `[Image #N]` 格式的占位符
2. **统一编号**: 远程图片和本地图片共享连续的编号空间
3. **视觉指示**: 清晰指示输入中包含的图片附件
4. **编辑隔离**: 占位符不可编辑，防止用户误修改

### 用户体验目标
- 让用户清楚了解已附加的图片数量和位置
- 保持文本编辑的流畅性
- 支持通过键盘管理图片附件

## 3. 具体技术实现

### 关键数据结构

```rust
/// 本地图片附件
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct LocalImageAttachment {
    pub(crate) placeholder: String,  // 如 "[Image #2]"
    pub(crate) path: PathBuf,        // 本地文件路径
}

/// 图片附件（内部使用）
#[derive(Clone, Debug, PartialEq)]
struct AttachedImage {
    placeholder: String,
    path: PathBuf,
}

pub(crate) struct ChatComposer {
    attached_images: Vec<AttachedImage>,  // 本地图片附件
    remote_image_urls: Vec<String>,       // 远程图片 URL
    selected_remote_image_index: Option<usize>, // 当前选中的远程图片
    // ... 其他字段
}
```

### 占位符编号规则

```rust
impl ChatComposer {
    /// 重新编号本地图片并更新占位符
    fn relabel_attached_images_and_update_placeholders(&mut self) {
        let remote_count = self.remote_image_urls.len();
        
        for (idx, img) in self.attached_images.iter_mut().enumerate() {
            // 本地图片编号从远程图片数量之后开始
            let new_num = remote_count + idx + 1;
            let new_placeholder = format!("[Image #{new_num}]");
            
            // 更新文本区域中的占位符
            let _ = self.textarea.replace_element_by_id(
                &img.placeholder, 
                &new_placeholder
            );
            
            img.placeholder = new_placeholder;
        }
    }
    
    /// 获取下一个本地图片占位符
    fn next_image_placeholder(&self) -> String {
        let num = self.remote_image_urls.len() + self.attached_images.len() + 1;
        format!("[Image #{num}]")
    }
}
```

### 图片附加流程

```rust
impl ChatComposer {
    /// 附加本地图片
    fn attach_image(&mut self, path: PathBuf) {
        let placeholder = self.next_image_placeholder();
        
        // 插入占位符元素到文本区域
        self.textarea.insert_element(&placeholder);
        
        // 记录附件
        self.attached_images.push(AttachedImage {
            placeholder,
            path,
        });
    }
    
    /// 设置远程图片 URL
    pub(crate) fn set_remote_image_urls(&mut self, urls: Vec<String>) {
        self.remote_image_urls = urls;
        self.selected_remote_image_index = None;
        // 重新编号本地图片
        self.relabel_attached_images_and_update_placeholders();
        self.sync_popups();
    }
}
```

### 远程图片行渲染

```rust
fn remote_images_lines(&self, width: u16) -> Vec<Line<'static>> {
    self.remote_image_urls
        .iter()
        .enumerate()
        .map(|(idx, _url)| {
            let num = idx + 1;
            let is_selected = self.selected_remote_image_index == Some(idx);
            
            let style = if is_selected {
                Style::default().add_modifier(Modifier::REVERSED)
            } else {
                Style::default()
            };
            
            Line::from(vec![
                Span::styled(format!("[Image #{num}]"), style),
                // ...
            ])
        })
        .collect()
}
```

### 键盘导航

```rust
impl ChatComposer {
    fn handle_key_event(&mut self, key_event: KeyEvent) -> (InputResult, bool) {
        match key_event.code {
            KeyCode::Up => {
                if self.textarea.cursor() == 0 {
                    // 光标在开头，进入远程图片选择
                    if !self.remote_image_urls.is_empty() {
                        self.selected_remote_image_index = 
                            Some(self.remote_image_urls.len() - 1);
                        return (InputResult::None, true);
                    }
                }
                // ...
            }
            KeyCode::Down => {
                if let Some(idx) = self.selected_remote_image_index {
                    if idx + 1 >= self.remote_image_urls.len() {
                        // 最后一个图片，返回文本区域
                        self.selected_remote_image_index = None;
                    } else {
                        self.selected_remote_image_index = Some(idx + 1);
                    }
                    return (InputResult::None, true);
                }
                // ...
            }
            KeyCode::Delete | KeyCode::Backspace => {
                if let Some(idx) = self.selected_remote_image_index.take() {
                    // 删除选中的远程图片
                    self.remote_image_urls.remove(idx);
                    self.relabel_attached_images_and_update_placeholders();
                    return (InputResult::None, true);
                }
                // ...
            }
            // ...
        }
    }
}
```

## 4. 关键代码路径与文件引用

### 主要源文件
| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/chat_composer.rs` | ChatComposer 图片管理 |
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/textarea.rs` | 占位符元素管理 |

### 关键代码路径

1. **图片附加**:
   ```
   chat_composer.rs:823-834 -> attach_image()
   ```

2. **占位符重新编号**:
   ```
   chat_composer.rs:920-939 -> relabel_attached_images_and_update_placeholders()
   ```

3. **远程图片设置**:
   ```
   chat_composer.rs:953-958 -> set_remote_image_urls()
   ```

4. **远程图片行渲染**:
   ```
   chat_composer.rs:684-687 -> remote_images_lines()
   ```

## 5. 依赖与外部交互

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `codex_protocol::user_input::TextElement` | 占位符元素类型 |
| `crate::bottom_pane::LocalImageAttachment` | 本地图片附件结构 |
| `crate::bottom_pane::textarea::TextArea` | 文本编辑和占位符管理 |

### 外部交互

1. **图片粘贴**:
   ```rust
   pub fn handle_paste_image_path(&mut self, pasted: String) -> bool
   ```
   - 检测粘贴内容是否为图片路径
   - 验证图片并附加

2. **提交时处理**:
   - 占位符在提交前被替换为实际的图片数据
   - 远程图片 URL 作为独立附件发送

## 6. 风险、边界与改进建议

### 潜在风险

1. **编号混乱**:
   - 风险: 删除远程图片后本地图片编号变化可能导致混淆
   - 缓解: 重新编号时同步更新所有引用

2. **占位符冲突**:
   - 风险: 用户手动输入 `[Image #N]` 可能导致冲突
   - 缓解: 使用更独特的格式或内部 ID

3. **图片过多**:
   - 风险: 大量图片可能导致占位符占用过多空间
   - 缓解: 考虑折叠显示

### 边界情况

1. **空图片列表**:
   - 无图片时不显示远程图片行

2. **图片删除后**:
   - 删除远程图片后立即重新编号本地图片

3. **占位符编辑**:
   - 占位符作为元素插入，不可直接编辑

### 改进建议

1. **图片预览**:
   - 建议: 悬停占位符显示图片缩略图

2. **拖放支持**:
   - 建议: 支持拖放调整图片顺序

3. **批量操作**:
   - 建议: 支持多选删除图片

4. **图片信息**:
   - 建议: 显示图片大小、尺寸等元数据

5. **占位符样式**:
   - 建议: 使用不同颜色区分本地和远程图片
