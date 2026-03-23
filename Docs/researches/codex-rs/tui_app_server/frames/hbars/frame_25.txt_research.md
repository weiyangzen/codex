# Frame 25 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 25 是 HBARS 动画序列的第二十五帧，位于第二阶段的后期。此帧继续展示波浪形态的演变，条块分布进一步变化，是整个 36 帧循环中第二阶段后期的重要帧。

在 36 帧循环中，Frame 25 代表了约 69.4% 的进度（25/36），标志着第二阶段进入后期深化阶段。

## 功能点目的

1. **后期深化**：深化第二阶段后期的波形发展
2. **变化继续**：继续条块分布的变化
3. **视觉动态**：提供更动态的视觉体验
4. **循环准备**：为 Frame 26-36 的循环结束做准备

## 具体技术实现

### Unicode 字符集
使用标准 Unicode 块元素字符：
- `▁▂▃▄▅▆▇█` (U+2581-U+2588)

### 帧规格
- **行数**：17 行（包含首尾空行）
- **宽度**：约 40 字符
- **帧索引**：24（在 FRAMES_HBARS 数组中）
- **显示时序**：第 1920-2000ms

### 视觉特征
Frame 25 的特征：
- 条块分布进一步变化
- 波浪形态更加动态
- 为 Frame 26-36 的循环结束做铺垫

## 关键代码路径与文件引用

### 帧数据
```rust
// codex-rs/tui_app_server/src/frames.rs
include_str!(concat!("../frames/", "hbars", "/frame_25.txt"))
```

### 动画时序
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
// Frame 25 在动画开始后 1920ms 显示
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
