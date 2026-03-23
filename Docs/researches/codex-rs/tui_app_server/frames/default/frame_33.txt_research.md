# frame_33.txt 研究文档

## 场景与职责

`frame_33.txt` 是 Codex TUI 应用服务器启动动画的第 33 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 92% 进度点，是动画接近尾声的关键帧。

## 功能点目的

1. **接近结束**：第 33 帧距离动画周期结束还有 4 帧
2. **最后阶段展示**：展示动画最后约 8% 阶段的视觉效果
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 2.64 秒显示

## 具体技术实现

### 帧周期分析

```
36 帧动画的最后阶段：

89%      92%      94%      97%     100%
│        │        │        │        │
32       33       34       35       36
├────────┼────────┼────────┼────────┤
          │
          ▼
      frame_33
      (91.7%)

frame_33 参数：
- 索引：32（0-based）
- 显示时段：[2560ms, 2640ms)
- 周期位置：91.7%
- 距离结束：3 帧（240ms）
```

### 代码中的定义

```rust
// frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-31] frame_1 到 frame_32
    include_str!("../frames/default/frame_33.txt"),  // [32]
    // [33-35] frame_34 到 frame_36
];

// 变体集合
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,   // [0] 包含 frame_33.txt
    &FRAMES_CODEX,     // [1]
    &FRAMES_OPENAI,    // [2]
    // ... 其他变体
];
```

### 帧访问模式

```rust
impl AsciiAnimation {
    fn frames(&self) -> &'static [&'static str] {
        self.variants[self.variant_idx]
    }
    
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let tick_ms = self.frame_tick.as_millis();
        let elapsed_ms = self.start.elapsed().as_millis();
        
        // 当 elapsed_ms = 2560 时：
        // (2560 / 80) % 36 = 32 % 36 = 32
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        
        frames[idx]  // 返回 frame_33.txt
    }
}
```

## 关键代码路径与文件引用

| 组件 | 路径 | 说明 |
|------|------|------|
| 帧数据 | `frames/default/frame_33.txt` | 第 33 帧 ASCII 艺术 |
| 帧定义 | `src/frames.rs:36` | `include_str!(".../frame_33.txt")` |
| 帧集合 | `src/frames.rs:47` | `FRAMES_DEFAULT` |
| 动画器 | `src/ascii_animation.rs` | 帧控制逻辑 |
| 欢迎组件 | `src/onboarding/welcome.rs` | 渲染 |

## 依赖与外部交互

### 与 FrameScheduler 的完整交互

```rust
// FrameRequester 创建
pub fn new(draw_tx: broadcast::Sender<()>) -> Self {
    let (tx, rx) = mpsc::unbounded_channel();
    let scheduler = FrameScheduler::new(rx, draw_tx);
    tokio::spawn(scheduler.run());  // 启动调度器任务
    Self { frame_schedule_tx: tx }
}

// 调度 frame_34（当 frame_33 显示时）
pub fn schedule_frame_in(&self, dur: Duration) {
    let _ = self.frame_schedule_tx.send(Instant::now() + dur);
}

// FrameScheduler 处理
async fn run(mut self) {
    const ONE_YEAR: Duration = Duration::from_secs(60 * 60 * 24 * 365);
    let mut next_deadline: Option<Instant> = None;
    
    loop {
        let target = next_deadline.unwrap_or_else(|| Instant::now() + ONE_YEAR);
        let deadline = tokio::time::sleep_until(target.into());
        tokio::pin!(deadline);
        
        tokio::select! {
            draw_at = self.receiver.recv() => {
                let Some(draw_at) = draw_at else { break };
                let draw_at = self.rate_limiter.clamp_deadline(draw_at);
                next_deadline = Some(next_deadline.map_or(draw_at, |cur| cur.min(draw_at)));
            }
            _ = &mut deadline => {
                if next_deadline.is_some() {
                    next_deadline = None;
                    self.rate_limiter.mark_emitted(target);
                    let _ = self.draw_tx.send(());
                }
            }
        }
    }
}
```

### 与 TUI 的集成

```
TUI 初始化
    │
    ├── 创建 broadcast channel (draw_tx/draw_rx)
    ├── 创建 FrameRequester
    │       └── 启动 FrameScheduler 任务
    ├── 创建 WelcomeWidget
    │       └── 创建 AsciiAnimation
    └── 进入事件循环
            │
            ├── 接收 draw 通知
            ├── 调用所有 widget 的 render_ref()
            │       └── WelcomeWidget::render_ref()
            │               ├── animation.schedule_next_frame()
            │               └── animation.current_frame()
            └── 继续循环
```

## 风险、边界与改进建议

### 风险
1. **资源泄漏**：FrameScheduler 任务在应用退出时可能未正确清理
2. **时间漂移**：长时间运行后 `Instant` 可能有微秒级漂移

### 边界情况
- **一年边界**：`ONE_YEAR` 常量用于处理无调度请求的情况
- **时区变化**：`Instant` 不受系统时间变化影响

### 改进建议
1. **优雅关闭**：实现 FrameScheduler 的优雅关闭机制
2. **健康检查**：添加 FrameScheduler 健康检查
3. **指标收集**：收集帧调度延迟等指标
4. **动态调整**：根据系统负载动态调整动画帧率
