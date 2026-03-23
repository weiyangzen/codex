# frame_26.txt 研究文档

## 场景与职责

`frame_26.txt` 是 Codex TUI 应用服务器启动动画的第 26 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 72% 进度点，继续展示动画后半段的动态效果。

## 功能点目的

1. **动画延续**：第 26 帧继续后半段动画的视觉展示
2. **接近结束**：距离动画周期结束还有 11 帧
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 2.08 秒显示

## 具体技术实现

### 帧时间线

```
36 帧动画的后半段（frame_19 到 frame_36）：

frame_19 ──┐
frame_20   │
...        ├ 后半段
frame_25   │
frame_26 ──┤  <-- 本文件（约 72%）
frame_27   │
...        │
frame_36 ──┘

frame_26 参数：
- 索引：25（0-based）
- 显示时段：[2000ms, 2080ms)
- 周期位置：72.2%
- 距离结束：10 帧（800ms）
```

### 代码集成

```rust
// frames.rs - 第 26 帧定义
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-24] frame_1 到 frame_25
    include_str!("../frames/default/frame_26.txt"),  // [25]
    // [26-35] frame_27 到 frame_36
];

// 变体集合
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,    // [0]
    &FRAMES_CODEX,      // [1]
    &FRAMES_OPENAI,     // [2]
    &FRAMES_BLOCKS,     // [3]
    &FRAMES_DOTS,       // [4]
    &FRAMES_HASH,       // [5]
    &FRAMES_HBARS,      // [6]
    &FRAMES_VBARS,      // [7]
    &FRAMES_SHAPES,     // [8]
    &FRAMES_SLUG,       // [9]
];
```

### 帧调度算法

```rust
impl AsciiAnimation {
    pub(crate) fn schedule_next_frame(&self) {
        let tick_ms = self.frame_tick.as_millis();  // 80
        
        if tick_ms == 0 {
            self.request_frame.schedule_frame();
            return;
        }
        
        let elapsed_ms = self.start.elapsed().as_millis();
        let rem_ms = elapsed_ms % tick_ms;  // 当前帧内已过去的时间
        
        // 计算到下一帧的延迟
        let delay_ms = if rem_ms == 0 {
            tick_ms  // 恰好在帧边界，等待完整一帧
        } else {
            tick_ms - rem_ms  // 等待剩余时间
        };
        
        // 调度 frame_27（如果当前是 frame_26）
        if let Ok(delay_ms_u64) = u64::try_from(delay_ms) {
            self.request_frame.schedule_frame_in(Duration::from_millis(delay_ms_u64));
        } else {
            self.request_frame.schedule_frame();
        }
    }
}
```

## 关键代码路径与文件引用

| 层级 | 文件 | 说明 |
|-----|------|------|
| 数据 | `frames/default/frame_26.txt` | 第 26 帧 ASCII 艺术 |
| 嵌入 | `src/frames.rs:29` | `include_str!(".../frame_26.txt")` |
| 控制 | `src/ascii_animation.rs` | 动画控制 |
| 渲染 | `src/onboarding/welcome.rs` | 欢迎界面 |
| 调度 | `src/tui/frame_requester.rs` | 帧调度器 |

## 依赖与外部交互

### 与 ratatui 的集成

```rust
use ratatui::text::Line;
use ratatui::widgets::{Paragraph, Clear, Wrap};

// WelcomeWidget 渲染
impl WidgetRef for &WelcomeWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);
        
        if self.animations_enabled {
            self.animation.schedule_next_frame();
        }
        
        let mut lines: Vec<Line> = Vec::new();
        
        if show_animation {
            let frame = self.animation.current_frame();
            lines.extend(frame.lines().map(Into::into));
            lines.push("".into());
        }
        
        // 欢迎文本
        lines.push(Line::from(vec![
            "  ".into(),
            "Welcome to ".into(),
            "Codex".bold(),
            ", OpenAI's command-line coding agent".into(),
        ]));
        
        Paragraph::new(lines)
            .wrap(Wrap { trim: false })
            .render(area, buf);
    }
}
```

### 与 tokio 的集成

```rust
// FrameScheduler 作为 tokio 任务
let scheduler = FrameScheduler::new(rx, draw_tx);
tokio::spawn(scheduler.run());

// 使用 tokio::select! 处理并发
async fn run(mut self) {
    loop {
        tokio::select! {
            draw_at = self.receiver.recv() => { /* ... */ },
            _ = deadline => { /* ... */ },
        }
    }
}
```

## 风险、边界与改进建议

### 风险
1. **任务泄漏**：`tokio::spawn` 创建的 FrameScheduler 任务可能泄漏
2. **精度损失**：`u128` 到 `u64` 转换可能截断（虽然实际上不会）

### 边界情况
- **u64 溢出**：`delay_ms` 转换时若超过 `u64::MAX` 会失败
- **负数时间**：`rem_ms` 计算不会出现负数（`%` 运算结果非负）

### 改进建议
1. **任务管理**：使用 `AbortHandle` 管理 FrameScheduler 生命周期
2. **饱和转换**：使用 `saturating_cast` 替代 `try_from`
3. **帧缓存**：缓存已渲染的 `Line` 对象避免重复解析
4. **可访问性**：提供关闭动画的选项
