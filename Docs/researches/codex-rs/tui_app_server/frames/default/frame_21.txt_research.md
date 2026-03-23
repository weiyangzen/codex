# frame_21.txt 研究文档

## 场景与职责

`frame_21.txt` 是 Codex TUI 应用服务器启动动画的第 21 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 58% 进度点，继续后半段的动画叙事。

## 功能点目的

1. **动画延续**：第 21 帧继续展示标志的动态变化
2. **视觉流动**：与前 20 帧配合形成流畅的视觉流动效果
3. **时间标记**：在 80ms 帧间隔下，约在动画开始后 1.68 秒显示

## 具体技术实现

### 帧定位

```
36 帧动画中的 frame_21：

帧索引：20（0-based）
1-based 位置：21/36 = 58.3%
显示时段：[1600ms, 1680ms)

与其他关键帧的关系：
- frame_18：中点帧（50%）
- frame_19：后半段开始（53%）
- frame_20：后半段第 2 帧（56%）
- frame_21：后半段第 3 帧（58%） <-- 本文件
- frame_36：循环结束（100%）
```

### 代码集成

```rust
// frames.rs - 第 21 帧嵌入位置
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-19] frame_1 到 frame_20
    include_str!("../frames/default/frame_21.txt"),  // [20]
    // [21-35] frame_22 到 frame_36
];

// 访问方式
const FRAME_21_INDEX: usize = 20;
let frame_21_content: &str = FRAMES_DEFAULT[FRAME_21_INDEX];
```

### 动画控制器使用

```rust
impl AsciiAnimation {
    // 创建新动画实例（默认使用 default 变体）
    pub(crate) fn new(request_frame: FrameRequester) -> Self {
        Self::with_variants(request_frame, ALL_VARIANTS, /*variant_idx*/ 0)
    }
    
    // 获取当前帧（可能是 frame_21.txt）
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let tick_ms = self.frame_tick.as_millis();
        let elapsed_ms = self.start.elapsed().as_millis();
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        // 当 idx == 20 时返回 frame_21.txt
        frames[idx]
    }
}
```

## 关键代码路径与文件引用

| 组件 | 路径 | 说明 |
|------|------|------|
| 帧数据 | `frames/default/frame_21.txt` | 第 21 帧 ASCII 艺术 |
| 帧定义 | `src/frames.rs:24` | `include_str!(".../frame_21.txt")` |
| 动画器 | `src/ascii_animation.rs` | 帧选择与时间管理 |
| 欢迎组件 | `src/onboarding/welcome.rs` | 渲染上下文 |

## 依赖与外部交互

### 与 ratatui 的渲染集成

```rust
use ratatui::text::Line;
use ratatui::widgets::Paragraph;

// 在 WelcomeWidget 中渲染 frame_21
let frame = self.animation.current_frame();
let lines: Vec<Line> = frame
    .lines()
    .map(Into::into)
    .collect();

Paragraph::new(lines).render(area, buf);
```

### 与 tokio 的异步集成

```rust
// FrameScheduler 作为 tokio 任务运行
let scheduler = FrameScheduler::new(rx, draw_tx);
tokio::spawn(scheduler.run());  // 在独立任务中运行调度器
```

## 风险、边界与改进建议

### 风险
1. **跨平台差异**：不同操作系统对 `Instant` 的实现可能有微秒级差异
2. **终端兼容性**：某些终端对快速刷新支持不佳，可能导致闪烁

### 边界情况
- **最小尺寸**：终端高度 < 37 或宽度 < 60 时，frame_21 不显示
- **禁用动画**：`animations_enabled = false` 时跳过所有帧

### 改进建议
1. **帧率自适应**：根据终端性能动态调整帧率
2. **降级策略**：性能不足时降低帧率或显示静态帧
3. **帧内容校验**：CI 检查所有帧的字符编码一致性
4. **文档生成**：自动生成动画预览文档或 GIF
