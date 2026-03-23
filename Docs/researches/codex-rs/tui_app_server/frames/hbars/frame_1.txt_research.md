# Frame 1 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 1 是 HBARS（水平条）动画序列的起始帧，标志着动画循环的开始。作为 36 帧循环中的第一帧，它建立了整个动画的视觉基调和流动模式。该帧展示了初始的波浪形态，为后续帧的渐进变形奠定基础。

在 Codex TUI 应用服务器的欢迎屏幕中，此帧作为用户首次进入应用时看到的第一个视觉元素之一，承担着建立品牌第一印象的重要职责。

## 功能点目的

1. **动画起始锚点**：作为 36 帧循环的起点，Frame 1 定义了波浪动画的初始状态
2. **视觉节奏建立**：通过特定的 Unicode 块字符排列，建立水平条动画的流动节奏
3. **循环衔接准备**：Frame 1 的视觉布局与 Frame 36 形成呼应，确保循环播放时的平滑过渡
4. **品牌视觉呈现**：通过动态的 ASCII 艺术展示 Codex 的技术美学

## 具体技术实现

### Unicode 字符集
本帧使用以下 Unicode 块元素字符（从下往上递增高度）：
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
- **帧索引**：0（在 FRAMES_HBARS 数组中）
- **动画时序**：在 80ms 帧间隔下，此帧显示时间为第 0-80ms

### 视觉模式分析
Frame 1 展示了分散式波浪图案：
- 顶部区域：中等高度的条块形成初始波峰
- 中部区域：高低交错的条块创造层次感
- 底部区域：逐渐收敛的图案为 Frame 2 的演变做准备

## 关键代码路径与文件引用

### 帧定义与编译时嵌入
```rust
// codex-rs/tui_app_server/src/frames.rs
pub(crate) const FRAMES_HBARS: [&str; 36] = frames_for!("hbars");
```

`frames_for!` 宏在编译时将 `frame_1.txt` 嵌入为静态字符串，存储在 FRAMES_HBARS[0]。

### 动画驱动与帧选择
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]  // 当 idx == 0 时返回 Frame 1
}
```

### 欢迎屏幕渲染
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
const MIN_ANIMATION_HEIGHT: u16 = 37;
const MIN_ANIMATION_WIDTH: u16 = 60;

if show_animation {
    let frame = self.animation.current_frame();
    lines.extend(frame.lines().map(Into::into));
}
```

## 依赖与外部交互

### FrameRequester 依赖
- `ascii_animation.rs` 通过 `FrameRequester` 调度下一帧渲染
- `schedule_next_frame()` 计算下一帧的延迟时间（80ms - 已过去的时间）
- 使用 `tokio::time` 实现异步帧调度

### ratatui 渲染
- 通过 `Paragraph::new(lines)` 渲染帧内容
- 使用 `Line::from()` 将每行 ASCII 艺术转换为 ratatui 的 Line 类型
- 通过 `Clear` widget 在渲染前清除区域，避免残影

### 用户交互
- **Ctrl+.**: 触发 `pick_random_variant()`，切换到其他动画变体（如 DOTS、VBARS 等）
- 动画变体切换时会立即调用 `schedule_frame()` 刷新显示

## 风险、边界与改进建议

### 风险与边界

1. **终端兼容性**
   - Unicode 块字符在某些老旧终端可能显示为方框或问号
   - 建议：检测终端 Unicode 支持，提供 ASCII 回退方案

2. **尺寸约束**
   - 最小高度 37 行、宽度 60 列的限制可能导致小终端无法显示
   - 当前实现：直接跳过动画，仅显示文字欢迎语
   - 风险：用户体验不一致

3. **性能考虑**
   - 每 80ms 的全屏刷新在远程 SSH 连接上可能产生闪烁
   - 建议：检测连接类型，动态调整帧率

4. **内存占用**
   - 36 帧 × 约 680 字节 ≈ 24KB 静态内存（每个变体）
   - 10 个变体总计约 240KB，可接受

### 改进建议

1. **帧间插值**
   - 当前：离散帧切换（80ms 间隔）
   - 建议：实现字符级别的渐变过渡，创造更流畅的动画效果

2. **响应式宽度**
   - 当前：固定约 40 字符宽度
   - 建议：根据终端宽度动态缩放或裁剪

3. **颜色支持**
   - 当前：纯单色 ASCII 艺术
   - 建议：为不同高度的条块添加渐变色，增强视觉吸引力

4. **帧压缩**
   - 当前：纯文本存储
   - 建议：使用差分编码存储帧间变化，减少二进制体积

5. **可访问性**
   - 当前：无替代文本描述
   - 建议：添加 `--no-animation` 标志和屏幕阅读器友好的描述

### 调试与测试

```bash
# 查看帧内容
cat codex-rs/tui_app_server/frames/hbars/frame_1.txt

# 运行相关测试
cargo test -p codex-tui-app-server welcome_renders_animation_on_first_draw
```
