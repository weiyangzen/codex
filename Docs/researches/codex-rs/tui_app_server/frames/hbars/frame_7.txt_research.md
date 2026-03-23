# Frame 7 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 7 是 HBARS 动画序列的第七帧，位于中期阶段的早期。此帧继续推进波浪的动态演变，展现出更加流畅和自然的流动效果，是动画流畅性的重要组成部分。

在 36 帧循环中，Frame 7 代表了约 19.4% 的进度（7/36），是中期阶段的关键帧之一。

## 功能点目的

1. **流动增强**：增强波浪的流动感和自然度
2. **过渡平滑**：确保与前后帧的平滑过渡
3. **视觉保持**：维持用户的视觉兴趣
4. **节奏稳定**：保持稳定的 80ms 动画节奏

## 具体技术实现

### Unicode 字符集
使用标准 Unicode 块元素字符：
- `▁▂▃▄▅▆▇█` (U+2581-U+2588)

### 帧规格
- **行数**：17 行（包含首尾空行）
- **宽度**：约 40 字符
- **帧索引**：6（在 FRAMES_HBARS 数组中）
- **显示时序**：第 480-560ms

### 视觉特征
Frame 7 的特征：
- 波浪形态更加圆润流畅
- 条块高度变化更加渐进
- 整体视觉效果更加和谐

## 关键代码路径与文件引用

### 帧数据
```rust
// codex-rs/tui_app_server/src/frames.rs
include_str!(concat!("../frames/", "hbars", "/frame_7.txt"))
```

### 时序计算
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
let idx = ((elapsed_ms / 80) % 36) as usize;
// Frame 7: elapsed_ms 在 480-560ms 时 idx = 6
```

### 渲染
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
Paragraph::new(lines)
    .wrap(Wrap { trim: false })
    .render(area, buf);
```

## 依赖与外部交互

### 核心依赖
- **std::time**: 时间计算
- **ratatui**: UI 渲染
- **tokio**: 异步调度

### 事件循环
1. `current_frame()` 计算当前帧索引
2. `schedule_next_frame()` 调度下一帧
3. `render_ref()` 渲染到终端

## 风险、边界与改进建议

### 风险与边界

1. **时间精度**
   - `Instant::now()` 的精度取决于操作系统
   - Windows 上可能只有 1ms 精度

2. **终端刷新率**
   - 某些终端限制刷新率为 60Hz
   - 80ms 间隔（12.5Hz）理论上可行，但可能与其他输出冲突

3. **并发渲染**
   - 如果终端同时输出其他内容，可能导致动画闪烁

### 改进建议

1. **VSync 支持**
   - 检测终端刷新率，同步动画

2. **双缓冲**
   - 使用终端的双缓冲模式减少闪烁

3. **帧插值**
   - 在帧之间插入中间帧，提高流畅度

### 监控指标

```rust
// 可添加的性能监控
let render_start = Instant::now();
// ... 渲染代码 ...
let render_time = render_start.elapsed();
if render_time > Duration::from_millis(10) {
    tracing::warn!("Slow frame render: {:?}", render_time);
}
```
