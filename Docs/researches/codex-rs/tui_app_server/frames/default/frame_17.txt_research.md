# frame_17.txt 研究文档

## 场景与职责

`frame_17.txt` 是 Codex TUI 应用服务器启动动画的第 17 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 47% 进度点，是动画中段的关键帧之一。

## 功能点目的

1. **中段核心帧**：第 17 帧接近动画周期的中点（50%），是视觉上最重要的帧之一
2. **视觉高潮**：通常展示标志最完整或最突出的姿态
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 1.36 秒显示

## 具体技术实现

### 帧定位分析

```
36 帧动画周期可视化：

帧:  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 ... 36
    ├──────────────────────────────────────────────────────────┤
    0%                          50%                          100%
                                ▲
                              frame_17
                              (47.2%)

时间计算：
- 帧索引：16（0-based）
- 显示时段：[1280ms, 1360ms)
- 周期位置：47.2%
```

### 核心算法实现

```rust
// ascii_animation.rs
impl AsciiAnimation {
    /// 获取当前应该显示的帧内容
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        if frames.is_empty() {
            return "";
        }
        
        let tick_ms = self.frame_tick.as_millis();  // 80
        if tick_ms == 0 {
            return frames[0];
        }
        
        let elapsed_ms = self.start.elapsed().as_millis();
        // 当 elapsed_ms = 1280 时，(1280/80) % 36 = 16，返回 frame_17.txt
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        frames[idx]
    }
    
    /// 安排下一帧重绘
    pub(crate) fn schedule_next_frame(&self) {
        let tick_ms = self.frame_tick.as_millis();
        if tick_ms == 0 {
            self.request_frame.schedule_frame();
            return;
        }
        
        let elapsed_ms = self.start.elapsed().as_millis();
        let rem_ms = elapsed_ms % tick_ms;  // 当前帧已过去的时间
        let delay_ms = if rem_ms == 0 { 
            tick_ms  // 恰好在帧边界
        } else { 
            tick_ms - rem_ms  // 到下一帧的剩余时间
        };
        
        if let Ok(delay_ms_u64) = u64::try_from(delay_ms) {
            self.request_frame.schedule_frame_in(Duration::from_millis(delay_ms_u64));
        } else {
            self.request_frame.schedule_frame();
        }
    }
}
```

### 与欢迎界面的集成

```rust
// onboarding/welcome.rs
pub(crate) struct WelcomeWidget {
    pub is_logged_in: bool,
    animation: AsciiAnimation,
    animations_enabled: bool,
    layout_area: Cell<Option<Rect>>,
}

impl WelcomeWidget {
    pub(crate) fn new(
        is_logged_in: bool,
        request_frame: FrameRequester,
        animations_enabled: bool,
    ) -> Self {
        Self {
            is_logged_in,
            animation: AsciiAnimation::new(request_frame),  // 使用 default 变体
            animations_enabled,
            layout_area: Cell::new(None),
        }
    }
}
```

## 关键代码路径与文件引用

| 组件 | 路径 | 关键内容 |
|------|------|---------|
| 帧数据 | `frames/default/frame_17.txt` | 17 行 ASCII 艺术 |
| 帧集合 | `src/frames.rs:20` | `include_str!(".../frame_17.txt")` |
| 动画器 | `src/ascii_animation.rs:12-18` | `AsciiAnimation` 结构体 |
| 欢迎组件 | `src/onboarding/welcome.rs:26-31` | `WelcomeWidget` 定义 |
| 渲染实现 | `src/onboarding/welcome.rs:67-96` | `WidgetRef` trait 实现 |
| 测试 | `src/onboarding/welcome.rs:108-169` | 单元测试 |

## 依赖与外部交互

### 变体随机切换

```rust
pub(crate) fn pick_random_variant(&mut self) -> bool {
    if self.variants.len() <= 1 {
        return false;
    }
    let mut rng = rand::rng();
    let mut next = self.variant_idx;
    while next == self.variant_idx {
        next = rng.random_range(0..self.variants.len());
    }
    self.variant_idx = next;
    self.request_frame.schedule_frame();  // 立即触发重绘
    true
}
```

### 与 TUI 事件循环的交互

```
┌─────────────────────────────────────────┐
│           TUI Event Loop                │
├─────────────────────────────────────────┤
│  1. 接收 FrameScheduler 的绘制通知      │
│  2. 调用 App::draw()                    │
│  3. 遍历所有 Widget 调用 render_ref()   │
│  4. WelcomeWidget::render_ref()         │
│     ├── animation.schedule_next_frame() │
│     └── animation.current_frame()       │
│         └── 返回 frame_17.txt（如匹配） │
└─────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 风险
1. **随机数依赖**：`pick_random_variant` 依赖 `rand` crate，需确保确定性测试
2. **时间精度**：`Instant::elapsed()` 的精度依赖于平台实现

### 边界情况
- **单变体模式**：若只配置一个变体，`pick_random_variant` 返回 false
- **零帧间隔**：`tick_ms == 0` 时始终返回第一帧

### 改进建议
1. **确定性随机**：测试模式下使用固定种子
2. **帧插值**：支持在帧之间进行颜色/位置插值
3. **音频同步**：考虑与启动音效同步
4. **性能分析**：添加 span 追踪动画渲染耗时
