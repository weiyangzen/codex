# frame_30.txt 研究文档

## 场景与职责

`frame_30.txt` 是 Codex TUI 应用服务器启动动画的第 30 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 83% 进度点（5/6 位置），是动画最后阶段的重要帧。

## 功能点目的

1. **六分之五里程碑**：第 30 帧是 36 帧动画的 5/6 位置，接近动画结束
2. **最后阶段展示**：距离动画周期结束还有 7 帧
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 2.40 秒显示

## 具体技术实现

### 数学定位

```
36 帧动画的 5/6 位置：

0%      17%      33%      50%      67%      83%     100%
│        │        │        │        │        │        │
1        6       12       18       24       30       36
├────────┼────────┼────────┼────────┼────────┼────────┤
                                          │
                                          ▼
                                      frame_30
                                     （5/6 里程碑）

frame_30 数学参数：
- 索引：29（0-based）
- 1-based 位置：30/36 = 5/6 ≈ 83.3%
- 显示时段：[2320ms, 2400ms)
- 距离周期结束：6 帧（480ms）
```

### 代码中的定义

```rust
// frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-28] frame_1 到 frame_29
    include_str!("../frames/default/frame_30.txt"),  // [29]
    // [30-35] frame_31 到 frame_36
];

// 验证 5/6 位置
const TOTAL_FRAMES: usize = 36;
const FIVE_SIXTHS: usize = TOTAL_FRAMES * 5 / 6;  // 30
const_assert_eq!(FIVE_SIXTHS, 30);
```

### 帧访问

```rust
impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let tick_ms = self.frame_tick.as_millis();
        let elapsed_ms = self.start.elapsed().as_millis();
        
        // 当 elapsed_ms = 2320 时：
        // (2320 / 80) % 36 = 29 % 36 = 29
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        
        frames[idx]  // 返回 frame_30.txt
    }
}
```

## 关键代码路径与文件引用

| 组件 | 路径 | 说明 |
|------|------|------|
| 帧数据 | `frames/default/frame_30.txt` | 第 30 帧 ASCII 艺术 |
| 帧定义 | `src/frames.rs:33` | `include_str!(".../frame_30.txt")` |
| 帧集合 | `src/frames.rs:47` | `FRAMES_DEFAULT` |
| 动画器 | `src/ascii_animation.rs` | 帧控制逻辑 |
| 欢迎组件 | `src/onboarding/welcome.rs` | 渲染 |

## 依赖与外部交互

### 与 FrameScheduler 的协作

```rust
// FrameScheduler 处理 frame_30 的调度
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
                    let _ = self.draw_tx.send(());  // 触发 frame_30 渲染
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
            │       └── 调度 frame_31（80ms 后）
            └── if show_animation {
                    let frame = animation.current_frame();
                    // 当时间匹配时，frame == frame_30.txt
                    lines.extend(frame.lines().map(Into::into));
                }
```

## 风险、边界与改进建议

### 风险
1. **最后阶段重要性**：最后几帧影响用户对动画完整性的感知
2. **循环衔接**：frame_36 到 frame_1 的过渡需要特别平滑

### 边界情况
- **循环边界**：frame_36 结束后立即回到 frame_1
- **变体切换**：在最后阶段切换变体可能显得突兀

### 改进建议
1. **循环平滑**：确保 frame_36 和 frame_1 视觉衔接自然
2. **结束效果**：考虑在动画最后添加特殊效果
3. **可配置性**：允许用户调整动画速度或禁用
4. **性能优化**：最后阶段可考虑降低渲染复杂度
