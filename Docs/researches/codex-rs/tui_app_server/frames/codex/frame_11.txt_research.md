# frame_11.txt 研究文档

## 场景与职责

`frame_11.txt` 是 Codex TUI 应用服务器中 ASCII 动画系统的第 11 帧，属于 `codex` 变体动画序列。

**动画序列位置**：第 11/36 帧
**时序位置**：800ms（第 11 个 80ms 间隔）

## 功能点目的

1. **动画序列延续**：作为 36 帧循环的第 11 帧，超过 1/4 周期点
2. **旋转效果**：展示 Codex 图标旋转约 100° 后的状态
3. **用户体验**：在终端启动期间提供持续的视觉反馈

## 具体技术实现

### 帧时序
```
frame_1:   0ms    (idx=0)
frame_2:  80ms    (idx=1)
...
frame_11: 800ms   (idx=10)  <- 本帧
...
frame_36: 2800ms  (idx=35)
```

### 帧内容规格
```
文件：frame_11.txt
大小：662 字节
尺寸：17 行 × 40 列
字符：e, o, c, d, x, 空格
索引：FRAMES_CODEX[10]
```

### 渲染时序
```rust
// FrameScheduler 每 80ms 触发一次
async fn run(mut self) {
    loop {
        tokio::select! {
            _ = deadline => {
                self.draw_tx.send(());  // 触发重绘
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 文件包含
```rust
// frames.rs
macro_rules! frames_for {
    ("codex") => {
        [
            // ... frame_1 到 frame_10
            include_str!("../frames/codex/frame_11.txt"),  // 索引 10
            // ... frame_12 到 frame_36
        ]
    };
}
```

### 渲染路径
```
main loop
  └─> TUI::draw()
      └─> WelcomeWidget::render_ref()
          └─> AsciiAnimation::current_frame() -> FRAMES_CODEX[10]
              └─> Paragraph::new(frame_content)
                  └─> Buffer::render()
```

## 依赖与外部交互

### 模块依赖图
```
frame_11.txt
    ↑
frames.rs ───────┐
    ↑            │
ascii_animation.rs
    ↑            │
welcome.rs       │
    ↑            │
lib.rs ──────────┘
```

### 外部 crate
- `tokio::sync::broadcast`：帧调度通知
- `ratatui::widgets::Paragraph`：渲染
- `crossterm::event`：键盘事件

## 风险、边界与改进建议

### 边界情况
1. **动画跳过**：如果渲染耗时超过 80ms，可能跳过后续帧
2. **变体切换**：切换时动画从 frame_1 重新开始
3. **终端大小**：小于 60x37 时动画被隐藏

### 优化建议
1. **帧预解析**：启动时预先将所有帧解析为 `Vec<Line>`
2. **智能调度**：根据系统负载动态调整帧率
3. **内存映射**：大帧文件可使用内存映射

### 监控建议
```rust
// 添加性能监控
let start = Instant::now();
let frame = animation.current_frame();
let render_time = start.elapsed();
if render_time > Duration::from_millis(16) {  // > 60 FPS 阈值
    tracing::warn!("Frame render took {:?}", render_time);
}
```
