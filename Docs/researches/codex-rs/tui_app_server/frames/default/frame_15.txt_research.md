# frame_15.txt 研究文档

## 场景与职责

`frame_15.txt` 是 Codex TUI 应用服务器启动动画的第 15 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 42% 进度点，标志着动画接近中段的关键过渡位置。

## 功能点目的

1. **中段前奏**：第 15 帧（约 42% 进度）是动画进入中段前的最后一帧
2. **视觉连贯性**：保持与前 14 帧的视觉流畅过渡
3. **时间定位**：在默认 80ms 帧间隔下，约在动画开始后 1.20 秒显示

## 具体技术实现

### 帧时间线定位

```
36 帧动画周期（2.88 秒）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
0%        25%       50%       75%       100%
│         │         │         │         │
1         9        18        27        36
├─────────┼─────────┼─────────┼─────────┤
         15 <-- 本帧位置（约 42%）

时间计算：
- 显示开始：14 × 80ms = 1120ms
- 显示结束：15 × 80ms = 1200ms
- 持续时间：80ms
```

### 核心数据结构

```rust
// ascii_animation.rs
pub(crate) struct AsciiAnimation {
    request_frame: FrameRequester,  // 帧调度请求器
    variants: &'static [&'static [&'static str]],  // 所有变体集合
    variant_idx: usize,             // 当前变体索引（default = 0）
    frame_tick: Duration,           // 帧间隔（80ms）
    start: Instant,                 // 动画开始时间
}

// frames.rs - default 变体定义
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // ... frame_1 到 frame_14
    include_str!("../frames/default/frame_15.txt"),  // [14]
    // ... frame_16 到 frame_36
];
```

### 帧渲染调用链

```
App::run() 事件循环
  └── TuiEvent::FrameTick
      └── App::draw()
          └── WelcomeWidget::render_ref()
              ├── animation.schedule_next_frame()
              │   └── FrameRequester::schedule_frame_in()
              │       └── FrameScheduler::run() [异步任务]
              └── animation.current_frame()
                  └── 返回 frame_15.txt 内容（当时间匹配时）
```

## 关键代码路径与文件引用

| 模块 | 文件路径 | 关键函数/常量 |
|------|---------|--------------|
| 帧数据 | `frames/default/frame_15.txt` | ASCII 艺术内容 |
| 帧定义 | `src/frames.rs:47` | `FRAMES_DEFAULT` 常量 |
| 动画控制 | `src/ascii_animation.rs` | `AsciiAnimation` 结构体 |
| 欢迎界面 | `src/onboarding/welcome.rs` | `WelcomeWidget` 渲染 |
| 帧调度 | `src/tui/frame_requester.rs` | `FrameRequester`, `FrameScheduler` |
| 速率限制 | `src/tui/frame_rate_limiter.rs` | `FrameRateLimiter` |

## 依赖与外部交互

### 与 TUI 系统的完整交互

```rust
// TUI 初始化时创建 FrameRequester
impl Tui {
    pub fn new() -> Self {
        let (draw_tx, _) = broadcast::channel(16);
        let frame_requester = FrameRequester::new(draw_tx.clone());
        // ...
    }
}

// 动画使用 FrameRequester
impl AsciiAnimation {
    pub(crate) fn new(request_frame: FrameRequester) -> Self {
        Self::with_variants(request_frame, ALL_VARIANTS, 0)
    }
}

// WelcomeWidget 持有动画实例
pub(crate) struct WelcomeWidget {
    animation: AsciiAnimation,
    // ...
}
```

### 变体切换的用户交互

```rust
// 键盘事件处理
impl KeyboardHandler for WelcomeWidget {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        if key_event.kind == KeyEventKind::Press
            && key_event.code == KeyCode::Char('.')
            && key_event.modifiers.contains(KeyModifiers::CONTROL)
        {
            let _ = self.animation.pick_random_variant();  // 可能切换到 codex/openai 等
        }
    }
}
```

## 风险、边界与改进建议

### 风险
1. **内存占用**：所有变体共 10 × 36 = 360 帧嵌入二进制，约 360KB 静态数据
2. **编译依赖**：修改帧文件需重新编译整个 crate

### 边界情况
- **变体索引越界**：`pick_random_variant` 确保新索引与当前不同，但需保证变体数量 >= 2
- **零帧间隔**：`current_frame()` 处理 `tick_ms == 0` 的情况，返回第一帧

### 改进建议
1. **延迟加载**：非活动变体延迟加载到内存
2. **帧共享**：检测相似帧并共享存储
3. **动画编辑器**：提供可视化工具编辑和预览动画
4. **运行时热重载**：开发模式支持运行时修改帧文件并热更新
