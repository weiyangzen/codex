# Frame 21 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 21 是 HBARS 动画序列的第二十一帧，位于第二阶段的中期。此帧继续展示波浪形态的演变，条块分布进一步分散，是整个 36 帧循环中第二阶段发展的重要帧。

在 36 帧循环中，Frame 21 代表了约 58.3% 的进度（21/36），标志着第二阶段进入中期发展的关键阶段。

## 功能点目的

1. **中期关键**：第二阶段中期的关键帧
2. **分散深化**：深化条块的分散程度
3. **视觉丰富**：提供更丰富的视觉体验
4. **节奏维持**：维持动画的整体节奏

## 具体技术实现

### Unicode 字符集
使用标准 Unicode 块元素字符：
- `▁▂▃▄▅▆▇█` (U+2581-U+2588)

### 帧规格
- **行数**：17 行（包含首尾空行）
- **宽度**：约 40 字符
- **帧索引**：20（在 FRAMES_HBARS 数组中）
- **显示时序**：第 1600-1680ms

### 视觉特征
Frame 21 的特征：
- 条块分布非常分散
- 波浪形态更加开放和动态
- 为 Frame 22-28 的高复杂度波形做铺垫

## 关键代码路径与文件引用

### 帧数据
```rust
// codex-rs/tui_app_server/src/frames.rs
include_str!(concat!("../frames/", "hbars", "/frame_21.txt"))
```

### 动画时序
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
// Frame 21 在动画开始后 1600ms 显示
```

### 尺寸检查
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
let show_animation = self.animations_enabled
    && layout_area.height >= MIN_ANIMATION_HEIGHT
    && layout_area.width >= MIN_ANIMATION_WIDTH;
```

## 依赖与外部交互

### 核心组件关系
```
WelcomeWidget
├── AsciiAnimation
│   ├── FrameRequester
│   └── frames (FRAMES_HBARS)
└── layout_area
```

### 渲染流程
1. `render_ref` 被调用
2. 检查 `animations_enabled` 和尺寸
3. 调用 `current_frame()` 获取 Frame 21
4. 转换为 `Line` 并渲染

## 风险、边界与改进建议

### 风险与边界

1. **尺寸变化**
   - 终端尺寸变化时，动画可能突然显示/消失
   - 用户体验不一致

2. **焦点丢失**
   - 终端失去焦点时，动画继续运行
   - 浪费 CPU 资源

3. **多实例冲突**
   - 多个 Codex 实例同时运行时，动画可能冲突
   - 终端输出可能混乱

### 改进建议

1. **焦点感知**
   - 检测终端焦点状态
   - 失去焦点时暂停动画

2. **平滑显示/隐藏**
   - 添加淡入淡出效果
   - 避免突然的显示/消失

3. **资源限制**
   - 检测系统负载
   - 高负载时降低帧率或暂停动画

### 调试技巧

```rust
// 添加调试日志
tracing::debug!(
    "Rendering frame {} at {:?}",
    frame_idx,
    Instant::now()
);
```
