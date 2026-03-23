# Frame 11 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 11 是 HBARS 动画序列的第十一帧，标志着中期阶段开始向后期阶段过渡。此帧展现出波浪从密集状态开始释放，条块分布逐渐分散，是整个动画循环中从紧到松的关键过渡帧。

在 36 帧循环中，Frame 11 代表了约 30.6% 的进度（11/36），是中期到后期的过渡帧。

## 功能点目的

1. **释放开始**：开始从密集状态释放
2. **过渡引导**：引导视觉从紧张到放松
3. **后期铺垫**：为后期阶段的分散波形做准备
4. **节奏放缓**：开始放缓动画节奏

## 具体技术实现

### Unicode 字符集
使用标准 Unicode 块元素字符：
- `▁▂▃▄▅▆▇█` (U+2581-U+2588)

### 帧规格
- **行数**：17 行（包含首尾空行）
- **宽度**：约 40 字符
- **帧索引**：10（在 FRAMES_HBARS 数组中）
- **显示时序**：第 800-880ms

### 视觉特征
Frame 11 的特征：
- 条块高度开始降低
- 波峰变得平缓
- 整体视觉效果开始放松

## 关键代码路径与文件引用

### 帧数据
```rust
// codex-rs/tui_app_server/src/frames.rs
include_str!(concat!("../frames/", "hbars", "/frame_11.txt"))
```

### 动画时序
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
// Frame 11 在动画开始后 800ms 显示
```

### 渲染检查
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
3. 调用 `current_frame()` 获取 Frame 11
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
