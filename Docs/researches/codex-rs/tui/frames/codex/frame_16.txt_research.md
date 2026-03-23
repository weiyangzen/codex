# frame_16.txt 研究文档

## 场景与职责

`frame_16.txt` 是 Codex TUI 欢迎界面 ASCII 动画序列的第 16 帧。该帧位于 36 帧动画循环的中后段，展示 Codex 标志在收缩状态下的最后几帧之一，即将开始向展开状态过渡。

## 功能点目的

1. **收缩阶段尾声**：作为第 16 帧，标志收缩阶段的最后展示
2. **过渡关键帧**：为后续展开动画提供起始形态
3. **视觉稳定**：在展开前提供最后的稳定视觉帧

## 具体技术实现

### 文件规格
- **帧序号**：16 / 36
- **动画进度**：44.4%（16/36）
- **显示时间**：动画开始后约 1200ms
- **文件大小**：662 字节

### 动画阶段定位
```
帧 1-12:  ▓▓▓▓▓▓▓▓▓▓▓▓ 展开→收缩
帧 13-16: ▓▓▓▓          收缩保持（本帧位于此处）
帧 17-24: ░░░░          最小状态
帧 25-36: ████████████  展开返回
```

### 技术细节
```rust
// FrameScheduler 调度逻辑
async fn run(mut self) {
    loop {
        tokio::select! {
            draw_at = self.receiver.recv() => {
                // 处理帧请求，计算下一次绘制时间
                let draw_at = self.rate_limiter.clamp_deadline(draw_at);
                next_deadline = Some(next_deadline.map_or(draw_at, |cur| cur.min(draw_at)));
            }
            _ = &mut deadline => {
                // 触发绘制，frame_16.txt 可能在此显示
                let _ = self.draw_tx.send(());
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 引用路径
```
frame_16.txt
  → include_str! → FRAMES_CODEX[15]
    → AsciiAnimation::current_frame()
      → WelcomeWidget::render_ref()
        → Terminal::draw()
```

### 相关配置
- **帧率**：`FRAME_TICK_DEFAULT = 80ms`
- **最小终端尺寸**：60×37

## 依赖与外部交互

### 模块依赖
- `frames.rs`：静态数据定义
- `ascii_animation.rs`：动画控制
- `frame_requester.rs`：调度器
- `welcome.rs`：渲染

## 风险、边界与改进建议

### 风险分析
1. **帧丢失**：系统负载高时可能跳过某些帧
2. **闪烁**：终端刷新率与动画帧率不匹配可能导致闪烁

### 改进建议
1. **VSync**：与终端刷新率同步
2. **帧缓冲**：双缓冲避免撕裂
3. **降级策略**：性能不足时自动降低帧率或禁用动画
