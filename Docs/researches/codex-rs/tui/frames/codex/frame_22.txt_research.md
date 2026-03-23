# frame_22.txt 研究文档

## 场景与职责

`frame_22.txt` 是 Codex TUI 欢迎界面 ASCII 动画序列的第 22 帧。该帧展示 Codex 标志在展开过程中的一个过渡形态，位于 36 帧动画循环的后半段中段。

## 功能点目的

1. **展开中段**：作为第 22 帧，标志展开到中段位置
2. **接近初始**：距离回到初始状态还有 14 帧
3. **视觉恢复**：用户可以看到标志正在恢复到初始形态

## 具体技术实现

### 文件规格
- **帧序号**：22 / 36
- **循环位置**：61.1%（22/36）
- **显示时间**：动画开始后约 1680ms
- **文件大小**：662 字节

### 剩余循环分析
```
已完成: 22 帧 = 1760ms
剩余: 14 帧 = 1120ms
总循环: 36 帧 = 2880ms
```

### 技术实现
```rust
// FrameRequester 调度
pub fn schedule_frame_in(&self, dur: Duration) {
    let _ = self.frame_schedule_tx.send(Instant::now() + dur);
}

// 在 welcome.rs 中使用
if self.animations_enabled {
    self.animation.schedule_next_frame();  // 调度下一帧
}
```

## 关键代码路径与文件引用

### 引用链
```
frame_22.txt
  ↓ include_str!("../frames/codex/frame_22.txt")
FRAMES_CODEX[21]
  ↓
AsciiAnimation::current_frame()
  ↓
WelcomeWidget::render_ref() → Paragraph::new()
```

### 相关测试
- `welcome.rs:130-139`：验证动画渲染位置

## 依赖与外部交互

### 模块依赖
```
frames.rs (FRAMES_CODEX[21])
  ↑
ascii_animation.rs (current_frame())
  ↑
frame_requester.rs (schedule_next_frame())
  ↑
welcome.rs (render_ref())
```

## 风险、边界与改进建议

### 边界条件
- **时间边界**：在 2.88 秒循环中位于 1.68 秒位置
- **帧边界**：作为第 22 帧，与 frame_14 形成对称关系

### 改进建议
1. **对称优化**：验证 frame_22 与 frame_14 的视觉对称性
2. **用户控制**：添加加速/减速动画的快捷键
3. **记录状态**：记住用户最后选择的动画变体
