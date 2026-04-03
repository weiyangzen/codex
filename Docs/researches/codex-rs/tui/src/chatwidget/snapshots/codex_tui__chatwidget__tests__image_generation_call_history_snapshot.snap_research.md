# 研究文档: image_generation_call_history_snapshot.snap

## 场景与职责

该快照文件测试图像生成调用在历史记录中的渲染效果。

## 功能点目的

1. **图像生成记录**: 记录AI图像生成操作
2. **结果展示**: 显示生成的图像信息
3. **历史追溯**: 允许用户回顾过去的图像生成

## 具体技术实现

### 图像生成事件

```rust
codex_protocol::protocol::ImageGenerationEndEvent {
    call_id: String,
    status: String,           // "completed"
    revised_prompt: Option<String>,
    result: String,           // base64编码的图像
    saved_path: Option<PathBuf>,
}
```

### 渲染输出

```
🖼️  Generated image
   Prompt: "A tiny blue square"
   Saved: /tmp/ig-1.png
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 6447-6466)
- **图像处理**: `codex-rs/tui/src/image_support.rs`

## 依赖与外部交互

1. **图像生成API**: OpenAI DALL-E 或其他图像生成服务
2. **图像显示**: 终端图像显示支持

## 改进建议
1. 在终端直接显示图像预览
2. 添加图像元数据显示
3. 支持图像下载/分享
