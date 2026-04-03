# Chat Composer Image Placeholder Multiple Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `chat_composer.rs` 模块的测试快照，用于验证**聊天输入框中多个图片占位符**的渲染。当用户粘贴或附加多张图片时，显示此界面。

### 业务场景
- 用户粘贴了多张图片到输入框
- 图片以占位符形式显示，不占用过多空间
- 占位符统一编号，便于用户识别

### 图片占位符特性
- 显示为 `[Image #1][Image #2]` 格式
- 不可编辑，作为整体处理
- 支持删除和重新排序

## 功能点目的

### 核心功能
1. **占位符显示**：用紧凑的占位符表示多张图片
2. **统一编号**：按顺序编号，便于识别
3. **空间优化**：占位符比完整图片路径更节省空间
4. **编辑支持**：支持删除和重新排序

### 用户体验目标
- **视觉简洁**：不占用过多输入框空间
- **清晰标识**：用户知道有多少张图片已附加
- **便捷操作**：支持键盘操作占位符

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct ChatComposer {
    attached_images: Vec<AttachedImage>,
    remote_image_urls: Vec<String>,
    // ...
}

pub(crate) struct AttachedImage {
    placeholder: String,  // 如 "[Image #2]"
    path: PathBuf,
}
```

### 占位符生成
```rust
fn relabel_attached_images_and_update_placeholders(&mut self) {
    let remote_count = self.remote_image_urls.len();
    
    for (idx, img) in self.attached_images.iter_mut().enumerate() {
        let new_placeholder = format!("[Image #{}]", remote_count + idx + 1);
        // 更新占位符...
    }
}
```

### 渲染逻辑
```rust
fn render(&self, area: Rect, buf: &mut Buffer) {
    // 渲染远程图片行
    for (idx, url) in self.remote_image_urls.iter().enumerate() {
        let placeholder = format!("[Image #{}]", idx + 1);
        // 渲染占位符...
    }
    
    // 渲染本地图片占位符
    for img in &self.attached_images {
        // img.placeholder 如 "[Image #2]"
        // 渲染占位符...
    }
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
- **测试函数**: `image_placeholder_multiple` (在 tests 模块中)

### 渲染输出分析
```
"                                                                                                    "
"› [Image #1][Image #2]                                                                              "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                 100% context left  "
```

- 第 2 行：输入框显示两个图片占位符
- 占位符紧凑排列
- 底部显示上下文信息

## 依赖与外部交互

### 内部依赖
- `AttachedImage` - 附加图片结构
- `TextArea` - 支持元素插入的文本区域

### 外部交互
- **图片处理**：验证图片格式和尺寸
- **文件系统**：读取本地图片文件

## 风险、边界与改进建议

### 潜在风险
1. **占位符冲突**：占位符文本可能与用户输入冲突
2. **编号混乱**：删除图片后编号可能不连续
3. **大量图片**：大量图片时占位符可能过长

### 边界情况
1. **空图片列表**：无图片时的显示
2. **图片删除**：删除图片后的占位符更新
3. **远程+本地混合**：远程图片和本地图片的编号

### 改进建议
1. **缩略图预览**：小尺寸显示图片缩略图
2. **悬停提示**：悬停显示图片详情
3. **拖拽排序**：支持拖拽调整图片顺序
4. **批量操作**：支持批量删除图片

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
