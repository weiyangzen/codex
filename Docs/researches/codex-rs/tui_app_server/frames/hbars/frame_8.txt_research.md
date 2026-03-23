# Frame 8 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 8 是 HBARS 动画序列的第八帧，位于中期阶段。此帧展现出波浪形态的进一步演变，条块分布开始呈现收缩趋势，为后续帧的密集波形做准备。

在 36 帧循环中，Frame 8 代表了约 22.2% 的进度（8/36），是中期阶段向密集阶段过渡的前奏。

## 功能点目的

1. **收缩预示**：开始展示波浪的收缩趋势
2. **过渡准备**：为 Frame 9-12 的密集波形做准备
3. **视觉变化**：提供与前帧不同的视觉体验
4. **循环维持**：维持整体循环的连贯性

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
- **帧索引**：7（在 FRAMES_HBARS 数组中）
- **显示时序**：第 560-640ms

### 视觉模式
Frame 8 展示了收缩趋势：
- 顶部：波峰开始向中心收缩
- 中部：条块分布更加集中
- 底部：开始出现聚集迹象

## 关键代码路径与文件引用

### 帧定义
```rust
// codex-rs/tui_app_server/src/frames.rs
pub(crate) const FRAMES_HBARS: [&str; 36] = frames_for!("hbars");
// Frame 8: FRAMES_HBARS[7]
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

### 欢迎组件
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
pub(crate) struct WelcomeWidget {
    pub is_logged_in: bool,
    animation: AsciiAnimation,
    animations_enabled: bool,
    layout_area: Cell<Option<Rect>>,
}
```

## 依赖与外部交互

### 模块依赖图
```
frames.rs
    ↓
ascii_animation.rs ← FrameRequester (tui module)
    ↓
welcome.rs → ratatui
```

### 外部 crate
- **ratatui**: 0.29+ (Widget, Paragraph, Line)
- **crossterm**: 0.28+ (KeyEvent, KeyCode)
- **rand**: 0.9+ (随机变体选择)

## 风险、边界与改进建议

### 风险与边界

1. **变体数量限制**
   - `ALL_VARIANTS` 硬编码 10 个变体
   - 添加新变体需要修改多处代码

2. **帧数量固定**
   - 每个变体必须恰好 36 帧
   - 帧数不一致会导致编译错误

3. **内存不可变性**
   - 帧数据编译后不可修改
   - 无法运行时自定义动画

### 改进建议

1. **配置化变体**
   - 从配置文件加载帧数据

2. **动态帧率**
   - 根据系统负载调整帧率

3. **帧验证宏**
   - 添加编译时验证确保帧格式正确

### 文件验证

```bash
# 验证帧文件存在且格式正确
for i in $(seq 1 36); do
    file="codex-rs/tui_app_server/frames/hbars/frame_$i.txt"
    lines=$(wc -l < "$file")
    if [ "$lines" -ne 17 ]; then
        echo "Error: $file has $lines lines, expected 17"
    fi
done
```
