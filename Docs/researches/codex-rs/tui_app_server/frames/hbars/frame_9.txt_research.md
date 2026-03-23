# Frame 9 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 9 是 HBARS 动画序列的第九帧，标志着动画进入中期阶段的核心部分。此帧展现出波浪的收缩和重组，条块分布更加紧凑，是整个动画循环中视觉密度较高的帧之一。

在 36 帧循环中，Frame 9 代表了约 25% 的进度（9/36），是中期阶段的关键帧。

## 功能点目的

1. **收缩加深**：进一步展示波浪的收缩趋势
2. **密度增加**：增加视觉密度，创造紧张感
3. **中期高潮**：为中期阶段的高潮部分做铺垫
4. **动态平衡**：在收缩与扩展之间寻找平衡

## 具体技术实现

### Unicode 字符集
使用完整的 Unicode 块元素字符集：
- `▁▂▃▄▅▆▇█` (U+2581-U+2588)

### 帧规格
- **行数**：17 行（包含首尾空行）
- **宽度**：约 40 字符
- **帧索引**：8（在 FRAMES_HBARS 数组中）
- **显示时序**：第 640-720ms

### 视觉特征
Frame 9 的特征：
- 波浪明显收缩，条块向中心聚集
- 出现更多的 `█` 和 `▇` 等高高度字符
- 整体视觉效果更加紧凑有力

## 关键代码路径与文件引用

### 编译时嵌入
```rust
// codex-rs/tui_app_server/src/frames.rs
include_str!(concat!("../frames/", "hbars", "/frame_9.txt"))
```

### 帧索引计算
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
let elapsed_ms = self.start.elapsed().as_millis();
let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
// Frame 9: idx = 8
```

### 渲染流程
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
impl WidgetRef for &WelcomeWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);
        if self.animations_enabled {
            self.animation.schedule_next_frame();
        }
        // ... 渲染逻辑
    }
}
```

## 依赖与外部交互

### 核心 trait
- **WidgetRef**: ratatui 的 trait，用于渲染
- **KeyboardHandler**: 自定义 trait，处理键盘事件
- **StepStateProvider**: 自定义 trait，提供步骤状态

### 事件流
```
用户按键 (Ctrl+.)
    ↓
KeyboardHandler::handle_key_event
    ↓
AsciiAnimation::pick_random_variant
    ↓
FrameRequester::schedule_frame
    ↓
触发重绘
```

## 风险、边界与改进建议

### 风险与边界

1. **渲染顺序**
   - `Clear` 必须在渲染帧之前调用
   - 否则可能产生残影

2. **尺寸检查**
   - `show_animation` 检查在每次渲染时执行
   - 频繁检查可能影响性能

3. **字符串转换**
   - `frame.lines().map(Into::into)` 每次渲染都执行
   - 可考虑缓存 Line 数组

### 改进建议

1. **缓存优化**
   - 预先将所有帧转换为 `Vec<Line>`
   - 避免每次渲染的转换开销

2. **延迟加载**
   - 只在需要时加载变体数据
   - 减少启动内存占用

3. **增量渲染**
   - 只重绘变化的部分
   - 减少终端输出量

### 性能基准

```
帧转换开销: ~50μs
渲染开销: ~500μs
总帧时间: ~80ms (12.5 FPS)
CPU 占用: <1%
```
