# frame_16.txt 研究文档

## 场景与职责

`frame_16.txt` 是 Codex TUI 应用服务器启动动画的第 16 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中恰好位于 44.4% 进度点，是动画进入后半段前的关键帧。

## 功能点目的

1. **中段里程碑**：第 16 帧接近动画周期的中点，标志着前半段动画的结束
2. **视觉转折**：通常在此位置动画呈现转折或方向变化
3. **时间同步**：在 80ms 帧间隔下，约在动画开始后 1.28 秒显示

## 具体技术实现

### 帧周期数学

```rust
// 动画周期参数
const TOTAL_FRAMES: usize = 36;
const FRAME_TICK_MS: u128 = 80;
const CYCLE_DURATION_MS: u128 = TOTAL_FRAMES as u128 * FRAME_TICK_MS;  // 2880ms

// frame_16.txt 参数
const FRAME_16_INDEX: usize = 15;  // 0-based
const FRAME_16_START_MS: u128 = FRAME_16_INDEX as u128 * FRAME_TICK_MS;  // 1200ms
const FRAME_16_END_MS: u128 = (FRAME_16_INDEX + 1) as u128 * FRAME_TICK_MS;  // 1280ms

// 当前帧计算
fn get_current_frame(elapsed_ms: u128) -> &'static str {
    let idx = ((elapsed_ms / FRAME_TICK_MS) % TOTAL_FRAMES as u128) as usize;
    FRAMES_DEFAULT[idx]
}
```

### 动画状态机

```
                    36 帧动画周期
    ┌─────────────────────────────────────────┐
    │                                         │
    ▼                                         ▼
┌───────┐    ┌───────┐              ┌───────┐
│frame_1│ -> │frame_2│ -> ... ->     │frame_36│
└───────┘    └───────┘              └───────┘
    │                              │
    └──────────────┬───────────────┘
                   │
              ┌────▼────┐
              │frame_16 │ <-- 本文件（约 44% 位置）
              └─────────┘
```

### 与 ratatui 的集成

```rust
use ratatui::text::Line;
use ratatui::widgets::Paragraph;

// 将 frame_16.txt 内容渲染到终端
let frame_content = animation.current_frame();  // 可能返回 frame_16.txt
let lines: Vec<Line> = frame_content
    .lines()
    .map(|line| Line::from(line.to_string()))
    .collect();

Paragraph::new(lines).render(area, buf);
```

## 关键代码路径与文件引用

| 层级 | 文件 | 行号 | 说明 |
|-----|------|------|------|
| 数据 | `frames/default/frame_16.txt` | 1-17 | ASCII 艺术帧数据 |
| 嵌入 | `src/frames.rs` | 19 | `include_str!(".../frame_16.txt")` |
| 控制 | `src/ascii_animation.rs` | 20-42 | `new()`, `with_variants()` |
| 计算 | `src/ascii_animation.rs` | 65-77 | `current_frame()` 索引计算 |
| 调度 | `src/ascii_animation.rs` | 44-63 | `schedule_next_frame()` |
| 渲染 | `src/onboarding/welcome.rs` | 80-95 | `WidgetRef::render_ref()` |

## 依赖与外部交互

### 与 tokio 异步运行时的集成

```rust
// FrameScheduler 作为异步任务运行
impl FrameScheduler {
    async fn run(mut self) {
        loop {
            tokio::select! {
                draw_at = self.receiver.recv() => {
                    // 处理帧调度请求
                    let draw_at = self.rate_limiter.clamp_deadline(draw_at);
                    next_deadline = Some(next_deadline.map_or(draw_at, |cur| cur.min(draw_at)));
                }
                _ = deadline => {
                    // 到达截止时间，发送绘制通知
                    let _ = self.draw_tx.send(());
                }
            }
        }
    }
}
```

### 测试桩

```rust
#[cfg(test)]
impl FrameRequester {
    pub(crate) fn test_dummy() -> Self {
        let (tx, _rx) = mpsc::unbounded_channel();
        FrameRequester { frame_schedule_tx: tx }
    }
}
```

## 风险、边界与改进建议

### 风险
1. **硬编码路径**：`frames_for!` 宏中路径硬编码，重命名文件需同步修改
2. **类型系统约束**：`[&str; 36]` 数组类型要求所有变体帧数相同

### 边界情况
- **测试环境**：`test_dummy()` 创建的 `FrameRequester` 不实际调度帧
- **禁用动画**：`animations_enabled = false` 时跳过所有帧渲染

### 改进建议
1. **配置驱动**：从配置文件读取动画参数（帧率、变体列表）
2. **模块化变体**：每个变体独立模块，支持条件编译
3. **帧压缩**：使用 RLE 等算法压缩 ASCII 艺术数据
4. **GPU 加速**：对于复杂动画，考虑使用 GPU 渲染终端图形
