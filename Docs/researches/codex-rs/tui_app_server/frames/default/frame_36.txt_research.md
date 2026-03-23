# frame_36.txt 研究文档

## 场景与职责

`frame_36.txt` 是 Codex TUI 应用服务器启动动画的第 36 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于 100% 进度点，是动画周期的最后一帧，下一帧将循环回到 frame_1。

## 功能点目的

1. **周期结束帧**：第 36 帧是 36 帧动画周期的最后一帧
2. **循环衔接**：负责与 frame_1 形成平滑的视觉循环
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 2.88 秒显示

## 具体技术实现

### 帧周期位置

```
36 帧动画的循环结构：

97%     100%      0%       3%
│        │        │        │
35       36        1        2
├────────┼────────┼────────┤
          │        │
          ▼        ▼
      frame_36  frame_1
      (100%)    (0%)

frame_36 参数：
- 索引：35（0-based）
- 显示时段：[2800ms, 2880ms)
- 周期位置：100%
- 周期时长：2880ms（36 × 80ms）
- 下一帧：循环回到 frame_1
```

### 循环逻辑

```rust
// frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-34] frame_1 到 frame_35
    include_str!("../frames/default/frame_36.txt"),  // [35] - 最后一帧
];

// 循环计算
impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let tick_ms = self.frame_tick.as_millis();  // 80
        let elapsed_ms = self.start.elapsed().as_millis();
        
        // 关键循环计算：
        // 当 elapsed_ms = 2800 时：(2800 / 80) % 36 = 35 -> frame_36
        // 当 elapsed_ms = 2880 时：(2880 / 80) % 36 = 36 % 36 = 0 -> frame_1
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        
        frames[idx]
    }
}
```

### 循环衔接

```
frame_35.txt ──► frame_36.txt ──► frame_1.txt
    [34]            [35]            [0]
   2720ms          2800ms          2880ms
    │               │               │
    └───────────────┴───────────────┘
              无缝循环

循环衔接要求：
1. 视觉上：frame_36 应该能平滑过渡到 frame_1
2. 时间上：2880ms 后回到 0ms 状态（周期性）
3. 逻辑上：% 36 运算确保循环
```

## 关键代码路径与文件引用

| 文件 | 行号 | 说明 |
|------|------|------|
| `frames/default/frame_36.txt` | 1-17 | 第 36 帧 ASCII 艺术 |
| `src/frames.rs` | 39 | `include_str!(".../frame_36.txt")` |
| `src/frames.rs` | 47 | `FRAMES_DEFAULT` 常量 |
| `src/frames.rs` | 58-69 | `ALL_VARIANTS` 变体集合 |
| `src/ascii_animation.rs` | 65-77 | `current_frame()` 循环逻辑 |

## 依赖与外部交互

### 与所有变体的循环一致性

```rust
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,   // [0] 36 帧，frame_36 循环到 frame_1
    &FRAMES_CODEX,     // [1] 36 帧
    &FRAMES_OPENAI,    // [2] 36 帧
    &FRAMES_BLOCKS,    // [3] 36 帧
    &FRAMES_DOTS,      // [4] 36 帧
    &FRAMES_HASH,      // [5] 36 帧
    &FRAMES_HBARS,     // [6] 36 帧
    &FRAMES_VBARS,     // [7] 36 帧
    &FRAMES_SHAPES,    // [8] 36 帧
    &FRAMES_SLUG,      // [9] 36 帧
];

// 所有变体都有相同的帧数和循环逻辑
```

### 与 FrameScheduler 的协作

```rust
// FrameScheduler 处理 frame_36 的调度
// 并安排循环后的 frame_1
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
                    let _ = self.draw_tx.send(());  // 触发渲染
                }
            }
        }
    }
}
```

## 风险、边界与改进建议

### 风险
1. **循环不连贯**：frame_36 到 frame_1 的视觉过渡若不自然，会破坏动画体验
2. **时间漂移**：长时间运行后，计时可能有微秒级累积误差

### 边界情况
- **精确循环点**：`elapsed_ms = 2880` 时，`(2880/80) % 36 = 0`，显示 frame_1
- **变体切换**：在 frame_36 显示时切换变体，新变体也显示其第 36 帧

### 改进建议
1. **循环验证**：CI 检查确保 frame_36 和 frame_1 视觉衔接自然
2. **循环预览**：提供工具预览循环衔接效果
3. **动态循环**：支持非固定帧数的循环（如 30 帧或 40 帧）
4. **循环统计**：记录循环次数和平均周期时间
