# Frame 35 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 35 是 HBARS 动画序列的第三十五帧，位于第二阶段的最后阶段。此帧继续展示波浪形态的演变，条块分布进一步变化，是整个 36 帧循环中第二阶段向循环结束过渡的关键帧。

在 36 帧循环中，Frame 35 代表了约 97.2% 的进度（35/36），标志着第二阶段即将结束，准备回到 Frame 1。

## 功能点目的

1. **循环结束准备**：为循环回到 Frame 1 做准备
2. **变化最后**：第二阶段的最后变化
3. **视觉衔接**：确保与 Frame 36 和 Frame 1 的视觉衔接
4. **循环闭合**：完成 36 帧循环的闭合

## 具体技术实现

### Unicode 字符集
使用标准 Unicode 块元素字符：
- `▁▂▃▄▅▆▇█` (U+2581-U+2588)

### 帧规格
- **行数**：17 行（包含首尾空行）
- **宽度**：约 40 字符
- **帧索引**：34（在 FRAMES_HBARS 数组中）
- **显示时序**：第 2720-2800ms

### 视觉特征
Frame 35 的特征：
- 条块分布非常接近 Frame 1 的状态
- 波浪形态为回到 Frame 1 做准备
- 与 Frame 36 形成完美的循环衔接

## 关键代码路径与文件引用

### 帧数据
```rust
// codex-rs/tui_app_server/src/frames.rs
include_str!(concat!("../frames/", "hbars", "/frame_35.txt"))
```

### 动画时序
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
// Frame 35 在动画开始后 2720ms 显示
```

### 尺寸检查
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
let show_animation = self.animations_enabled
    && layout_area.height >= MIN_ANIMATION_HEIGHT
    && layout_area.width >= MIN_ANIMATION_WIDTH;
```

## 依赖与外部交互

### 核心常量
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
const MIN_ANIMATION_HEIGHT: u16 = 37;
const MIN_ANIMATION_WIDTH: u16 = 60;
```

### 尺寸计算
- 动画帧：17 行
- 欢迎文本：2 行（空行 + 文本行）
- 总计：19 行
- 最小高度 37 行提供了额外的边距

## 风险、边界与改进建议

### 风险与边界

1. **高度计算**
   - `MIN_ANIMATION_HEIGHT = 37` 远大于实际需要
   - 可能过于保守，导致更多终端无法显示动画

2. **宽度约束**
   - `MIN_ANIMATION_WIDTH = 60` 也可能过于保守
   - 帧实际宽度约 40 字符

3. **边距分配**
   - 未明确分配上下边距
   - 可能导致视觉不平衡

### 改进建议

1. **动态尺寸计算**
   - 根据实际帧内容计算最小尺寸
   - 避免硬编码

2. **响应式边距**
   - 根据可用空间动态分配边距
   - 保持视觉平衡

3. **尺寸提示**
   - 当动画被隐藏时，提示用户调整终端尺寸
   - 改善用户体验

### 尺寸优化

```rust
// 动态计算最小尺寸
fn calculate_min_size(frames: &[&str]) -> (u16, u16) {
    let max_width = frames.iter()
        .map(|f| f.lines().map(|l| l.len()).max().unwrap_or(0))
        .max()
        .unwrap_or(0) as u16;
    let line_count = frames[0].lines().count() as u16;
    
    // 添加边距
    let min_width = max_width + 20; // 左右各 10 字符边距
    let min_height = line_count + 4; // 上下各 2 行边距 + 欢迎文本
    
    (min_width, min_height)
}
```
