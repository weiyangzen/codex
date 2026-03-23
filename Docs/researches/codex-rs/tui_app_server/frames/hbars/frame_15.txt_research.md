# Frame 15 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 15 是 HBARS 动画序列的第十五帧，位于后期阶段。此帧继续展示波浪向初始状态的回归，条块分布进一步接近 Frame 1，是整个动画循环中循环闭合的关键帧。

在 36 帧循环中，Frame 15 代表了约 41.7% 的进度（15/36），是后期阶段的重要过渡帧。

## 功能点目的

1. **回归深化**：深化向 Frame 1 的回归
2. **循环准备**：为 Frame 36 到 Frame 1 的循环做准备
3. **视觉连贯**：确保与 Frame 1 的视觉连贯性
4. **节奏稳定**：维持稳定的动画节奏

## 具体技术实现

### Unicode 字符集
使用标准 Unicode 块元素字符：
- `▁▂▃▄▅▆▇█` (U+2581-U+2588)

### 帧规格
- **行数**：17 行（包含首尾空行）
- **宽度**：约 40 字符
- **帧索引**：14（在 FRAMES_HBARS 数组中）
- **显示时序**：第 1120-1200ms

### 视觉特征
Frame 15 的特征：
- 条块分布与 Frame 1 非常接近
- 波峰和波谷的位置几乎一致
- 循环闭合的迹象明显

## 关键代码路径与文件引用

### 帧数据
```rust
// codex-rs/tui_app_server/src/frames.rs
include_str!(concat!("../frames/", "hbars", "/frame_15.txt"))
```

### 动画时序
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
// Frame 15 在动画开始后 1120ms 显示
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
