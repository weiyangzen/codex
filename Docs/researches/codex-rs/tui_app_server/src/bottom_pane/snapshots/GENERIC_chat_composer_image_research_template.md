# Chat Composer Image Generic Research Template

## 场景与职责

该文档是聊天输入框图片处理的通用研究模板，适用于以下快照文件：
- `image_placeholder_single.snap`
- `remote_image_rows.snap`
- `remote_image_rows_after_delete_first.snap`
- `remote_image_rows_selected.snap`

### 业务场景
- 用户粘贴或附加图片到输入框
- 图片以占位符或行形式显示
- 支持远程图片和本地图片

### 图片显示类型
| 类型 | 描述 |
|------|------|
| Placeholder | 紧凑的占位符显示 |
| Remote Rows | 远程图片以行形式显示 |
| Selected | 选中的图片行 |

## 功能点目的

### 核心功能
1. **图片显示**：以不同形式显示图片
2. **占位符管理**：管理图片占位符
3. **选择支持**：支持选择图片行

### 用户体验目标
- **视觉简洁**：不占用过多空间
- **操作便捷**：支持键盘操作图片
- **状态清晰**：清楚显示图片数量和状态

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct ChatComposer {
    attached_images: Vec<AttachedImage>,
    remote_image_urls: Vec<String>,
    selected_remote_image_index: Option<usize>,
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`

## 依赖与外部交互

### 内部依赖
- `AttachedImage` - 附加图片

### 外部交互
- **图片处理**：验证图片格式和尺寸

## 风险、边界与改进建议

### 潜在风险
1. **占位符冲突**：占位符文本可能与用户输入冲突
2. **编号混乱**：删除图片后编号可能不连续

### 改进建议
1. **缩略图预览**：小尺寸显示图片缩略图
2. **悬停提示**：悬停显示图片详情

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
