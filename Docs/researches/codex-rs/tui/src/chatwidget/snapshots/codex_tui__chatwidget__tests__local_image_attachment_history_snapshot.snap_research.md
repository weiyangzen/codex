# 研究文档: local_image_attachment_history_snapshot.snap

## 场景与职责

该快照文件测试本地图像附件在历史记录中的渲染效果。

## 功能点目的

1. **图像附件展示**: 显示用户附加的本地图像
2. **历史记录**: 在对话历史中保留图像引用
3. **视觉反馈**: 确认图像已成功附加

## 具体技术实现

### 图像附件事件

```rust
codex_protocol::protocol::ViewImageToolCallEvent {
    call_id: String,
    path: PathBuf,  // 本地图像路径
}
```

### 渲染输出

```
📎 Image: example.png
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 6428-6445)

## 依赖与外部交互

1. **图像处理**: 本地图像加载和显示

## 改进建议
1. 在终端显示图像缩略图
2. 添加图像尺寸和格式信息
3. 支持图像预览
