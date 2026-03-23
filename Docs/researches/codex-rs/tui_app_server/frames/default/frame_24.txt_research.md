# frame_24.txt 研究文档

## 场景与职责

`frame_24.txt` 是 Codex TUI 应用服务器启动动画的第 24 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 67% 进度点（2/3 位置），是动画后半段的重要里程碑帧。

## 功能点目的

1. **三分之二里程碑**：第 24 帧是 36 帧动画的 2/3 位置，具有时间对称意义
2. **动画深化**：继续展示标志的动态变化，接近动画尾声
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 1.92 秒显示

## 具体技术实现

### 数学定位

```
36 帧动画的 2/3 位置：

帧：    1        12        24        36
        │         │         │         │
       0%       33%       67%      100%
        ├─────────┼─────────┼─────────┤
                            │
                            ▼
                        frame_24
                      （2/3 里程碑）

frame_24 数学参数：
- 索引：23（0-based）
- 1-based 位置：24/36 = 2/3 ≈ 66.7%
- 显示时段：[1840ms, 1920ms)
- 距离周期结束：12 帧（960ms）
```

### 代码集成

```rust
// frames.rs - 第 24 帧在数组中的位置
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-22] frame_1 到 frame_23
    include_str!("../frames/default/frame_24.txt"),  // [23]
    // [24-35] frame_25 到 frame_36
];

// 计算验证
const_assert_eq!(FRAMES_DEFAULT.len(), 36);
const_assert_eq!(FRAMES_DEFAULT[23], include_str!("../frames/default/frame_24.txt"));
```

### 帧访问模式

```rust
impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let tick_ms = self.frame_tick.as_millis();  // 80
        let elapsed_ms = self.start.elapsed().as_millis();
        
        // 当 elapsed_ms = 1840 时：
        // (1840 / 80) % 36 = 23 % 36 = 23
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        
        frames[idx]  // 返回 frame_24.txt 内容
    }
}
```

## 关键代码路径与文件引用

| 组件 | 文件路径 | 关键内容 |
|------|---------|---------|
| 帧数据 | `frames/default/frame_24.txt` | 24 行 ASCII 艺术 |
| 帧定义 | `src/frames.rs:27` | `include_str!(".../frame_24.txt")` |
| 帧集合 | `src/frames.rs:47` | `FRAMES_DEFAULT` 数组 |
| 动画控制 | `src/ascii_animation.rs` | `AsciiAnimation` 实现 |
| 欢迎界面 | `src/onboarding/welcome.rs` | 渲染上下文 |
| 帧调度 | `src/tui/frame_requester.rs` | `FrameScheduler` |

## 依赖与外部交互

### 与 FrameRequester 的完整交互

```rust
// 创建 FrameRequester
let (draw_tx, _) = broadcast::channel(16);
let frame_requester = FrameRequester::new(draw_tx);

// 创建动画
let animation = AsciiAnimation::new(frame_requester.clone());

// 渲染时调度下一帧
impl WidgetRef for &WelcomeWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        if self.animations_enabled {
            self.animation.schedule_next_frame();
            // 内部调用：
            // frame_requester.schedule_frame_in(Duration::from_millis(80))
        }
    }
}

// FrameScheduler 异步处理
async fn run(mut self) {
    loop {
        tokio::select! {
            draw_at = self.receiver.recv() => {
                // 处理 frame_25 的调度请求
                let draw_at = self.rate_limiter.clamp_deadline(draw_at);
                next_deadline = Some(next_deadline.map_or(draw_at, |cur| cur.min(draw_at)));
            }
            _ = deadline => {
                // 发送重绘通知
                let _ = self.draw_tx.send(());
            }
        }
    }
}
```

### 与 TUI 事件循环的集成

```
TUI Event Loop
    │
    ├── FrameScheduler 发送 draw 通知
    │       │
    │       ▼
    ├── App::draw()
    │       │
    │       ├── WelcomeWidget::render_ref()
    │       │       ├── animation.schedule_next_frame()
    │       │       └── animation.current_frame() -> frame_24.txt
    │       │
    │       └── 其他 widgets 渲染
    │
    └── 继续事件循环
```

## 风险、边界与改进建议

### 风险
1. **广播通道溢出**：`broadcast::channel(16)` 容量有限，高频请求可能丢失
2. **时间精度**：`Instant` 的精度依赖于平台，可能影响动画流畅度

### 边界情况
- **通道满**：若 `draw_tx` 缓冲区满，新的绘制通知会失败（当前使用 `let _ =` 忽略错误）
- **长时间运行**：`elapsed_ms` 可能溢出 `u128`（虽然实际上几乎不可能）

### 改进建议
1. **通道扩容**：根据实际需求调整 broadcast channel 容量
2. **错误处理**：处理 `draw_tx.send()` 失败的情况
3. **性能指标**：添加 histogram 记录帧间隔的实际分布
4. **自适应质量**：根据系统负载动态调整动画复杂度
