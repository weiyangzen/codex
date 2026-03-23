# frame_6.txt 研究文档

## 场景与职责

`frame_6.txt` 是 Codex TUI 应用服务器启动动画的第 6 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 17% 进度点（1/6 位置），标志着动画早期阶段的推进。

## 功能点目的

1. **六分之一里程碑**：第 6 帧是 36 帧动画的 1/6 位置
2. **早期动画推进**：继续推进动画序列的早期展示
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 400ms 显示

## 具体技术实现

### 数学定位

```
36 帧动画的 1/6 位置：

0%      17%      33%      50%      67%      83%     100%
│        │        │        │        │        │        │
1        6       12       18       24       30       36
├────────┼────────┼────────┼────────┼────────┼────────┤
          │
          ▼
      frame_6
     （1/6 里程碑）

frame_6 数学参数：
- 索引：5（0-based）
- 1-based 位置：6/36 = 1/6 ≈ 16.7%
- 显示时段：[400ms, 480ms)
- 周期位置：约 17%
```

### 代码中的定义

```rust
// frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-4] frame_1 到 frame_5
    include_str!("../frames/default/frame_6.txt"),  // [5]
    // [6-35] frame_7 到 frame_36
];

// 验证 1/6 位置
const TOTAL_FRAMES: usize = 36;
const ONE_SIXTH: usize = TOTAL_FRAMES / 6;  // 6
const_assert_eq!(ONE_SIXTH, 6);
```

### 帧访问

```rust
impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let tick_ms = self.frame_tick.as_millis();
        let elapsed_ms = self.start.elapsed().as_millis();
        
        // 当 elapsed_ms = 400 时：
        // (400 / 80) % 36 = 5 % 36 = 5
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        
        frames[idx]  // 返回 frame_6.txt
    }
}
```

## 关键代码路径与文件引用

| 组件 | 路径 | 说明 |
|------|------|------|
| 帧数据 | `frames/default/frame_6.txt` | 第 6 帧 ASCII 艺术 |
| 帧定义 | `src/frames.rs:12` | `include_str!(".../frame_6.txt")` |
| 帧集合 | `src/frames.rs:47` | `FRAMES_DEFAULT` |
| 动画器 | `src/ascii_animation.rs` | 帧控制逻辑 |
| 欢迎组件 | `src/onboarding/welcome.rs` | 渲染 |

## 依赖与外部交互

### 与 FrameScheduler 的协作

```rust
// FrameScheduler 处理 frame_6 的调度
async fn run(mut self) {
    loop {
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
                    let _ = self.draw_tx.send(());  // 触发 frame_6 渲染
                }
            }
        }
    }
}
```

### 与 TUI 的集成

```
TUI 渲染流程：

App::draw()
    └── WelcomeWidget::render_ref(area, buf)
            ├── Clear.render(area, buf)
            ├── animation.schedule_next_frame()
            │       └── 调度 frame_7（80ms 后）
            └── if show_animation {
                    let frame = animation.current_frame();
                    // 当时间匹配时，frame == frame_6.txt
                    lines.extend(frame.lines().map(Into::into));
                }
```

## 风险、边界与改进建议

### 风险
1. **早期帧重要性**：前几帧建立用户对动画质量的第一印象
2. **循环衔接**：frame_36 到 frame_1 的过渡必须自然

### 边界情况
- **启动延迟**：应用启动慢时用户可能错过前几帧
- **快速切换**：用户可能在 frame_6 显示时切换变体

### 改进建议
1. **首帧优化**：确保早期帧设计精美
2. **启动同步**：动画与应用初始化同步
3. **慢启动模式**：允许前几帧显示更长时间
4. **里程碑效果**：在 1/6、1/3、1/2 等位置添加微妙效果
