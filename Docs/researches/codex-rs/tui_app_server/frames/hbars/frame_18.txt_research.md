# Frame 18 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 18 是 HBARS 动画序列的第十八帧，位于第二阶段的早期。此帧继续展示新的波浪形态，条块分布进一步演变，是整个 36 帧循环中第二阶段发展的重要帧。

在 36 帧循环中，Frame 18 代表了约 50% 的进度（18/36），是动画循环的中点帧。

## 功能点目的

1. **中点标记**：标记动画循环的中点
2. **波形发展**：继续发展第二阶段的波形
3. **视觉延续**：延续 Frame 17 建立的视觉基调
4. **节奏维持**：维持动画的整体节奏

## 具体技术实现

### Unicode 字符集
- `▁` (U+2581) - Lower one eighth block
- `▂` (U+2582) - Lower one quarter block
- `▃` (U+2583) - Lower three eighths block
- `▄` (U+2584) - Lower half block
- `▅` (U+2585) - Lower five eighths block
- `▆` (U+2586) - Lower three quarters block
- `▇` (U+2587) - Lower seven eighths block
- `█` (U+2588) - Full block

### 帧规格
- **行数**：17 行（包含首尾空行）
- **宽度**：约 40 字符
- **帧索引**：17（在 FRAMES_HBARS 数组中）
- **显示时序**：第 1360-1440ms

### 视觉模式
Frame 18 展示了中点状态：
- 波浪形态与 Frame 1 形成对比
- 条块分布达到第二阶段的局部平衡点
- 为后续帧的复杂化做准备

## 关键代码路径与文件引用

### 帧定义
```rust
// codex-rs/tui_app_server/src/frames.rs
pub(crate) const FRAMES_HBARS: [&str; 36] = frames_for!("hbars");
// Frame 18: FRAMES_HBARS[17]
```

### 动画结构
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
pub(crate) struct AsciiAnimation {
    request_frame: FrameRequester,
    variants: &'static [&'static [&'static str]],
    variant_idx: usize,
    frame_tick: Duration,
    start: Instant,
}
```

### 欢迎屏幕
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
impl StepStateProvider for WelcomeWidget {
    fn get_step_state(&self) -> StepState {
        match self.is_logged_in {
            true => StepState::Hidden,
            false => StepState::Complete,
        }
    }
}
```

## 依赖与外部交互

### 中点意义
- Frame 18 是 36 帧循环的精确中点
- 标志着动画已完成一半的循环
- 是检查动画同步性的好时机

### 第二阶段结构
```
Frame 17-20: 早期，建立新波形
Frame 21-28: 中期，波形复杂化
Frame 29-36: 后期，准备循环
```

## 风险、边界与改进建议

### 风险与边界

1. **中点同步**
   - 如果动画在中点出现卡顿，会很明显
   - 需要确保 Frame 18 的渲染性能

2. **视觉对比**
   - Frame 18 应与 Frame 1 形成良好对比
   - 避免过于相似或过于不同

3. **循环检测**
   - 用户可能在循环中点注意到重复
   - 需要足够的帧变化来掩盖循环

### 改进建议

1. **中点特效**
   - 在 Frame 18 添加微妙的视觉特效
   - 如颜色变化或亮度调整

2. **循环随机化**
   - 每次循环随机调整帧顺序
   - 减少重复感

3. **性能监控**
   - 在中点检查渲染性能
   - 及时发现性能问题

### 中点检测代码

```rust
// 检测动画中点
pub(crate) fn is_at_midpoint(&self) -> bool {
    let frames = self.frames();
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / self.frame_tick.as_millis()) % frames.len() as u128) as usize;
    idx == frames.len() / 2
}
```
