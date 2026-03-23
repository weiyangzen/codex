# Frame 14 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 14 是 HBARS 动画序列的第十四帧，位于后期阶段。此帧继续展示波浪的分散过程，条块分布接近 Frame 1 的状态，是整个动画循环中循环回归的关键帧。

在 36 帧循环中，Frame 14 代表了约 38.9% 的进度（14/36），是后期阶段向循环结束过渡的帧。

## 功能点目的

1. **回归继续**：继续向 Frame 1 的状态回归
2. **循环闭合**：为循环回到 Frame 1 做准备
3. **视觉准备**：为新一轮循环做视觉准备
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
- **帧索引**：13（在 FRAMES_HBARS 数组中）
- **显示时序**：第 1040-1120ms

### 视觉模式
Frame 14 展示了回归状态：
- 条块分布接近初始状态
- 波峰和波谷的位置与 Frame 1 相似
- 为无缝循环创造条件

## 关键代码路径与文件引用

### 帧定义
```rust
// codex-rs/tui_app_server/src/frames.rs
pub(crate) const FRAMES_HBARS: [&str; 36] = frames_for!("hbars");
// Frame 14: FRAMES_HBARS[13]
```

### 循环逻辑
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
// % 36 确保循环回到 Frame 0 (Frame 1)
```

### 测试
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
#[test]
fn welcome_renders_animation_on_first_draw() {
    let widget = WelcomeWidget::new(false, FrameRequester::test_dummy(), true);
    let area = Rect::new(0, 0, MIN_ANIMATION_WIDTH, MIN_ANIMATION_HEIGHT);
    let mut buf = Buffer::empty(area);
    let frame_lines = widget.animation.current_frame().lines().count() as u16;
    (&widget).render(area, &mut buf);

    let welcome_row = row_containing(&buf, "Welcome");
    assert_eq!(welcome_row, Some(frame_lines + 1));
}
```

## 依赖与外部交互

### 测试依赖
- `FrameRequester::test_dummy()`: 测试用的虚拟帧请求器
- `Buffer::empty()`: 创建空的渲染缓冲区
- `row_containing()`: 辅助函数，查找包含文本的行

### 测试验证点
1. 欢迎文本显示在动画帧之后
2. 动画帧行数正确（17 行）
3. 欢迎文本位置正确

## 风险、边界与改进建议

### 风险与边界

1. **测试脆弱性**
   - 测试依赖具体的帧行数
   - 修改帧文件可能导致测试失败

2. **缓冲区大小**
   - 测试使用固定大小的缓冲区
   - 可能无法覆盖所有边界情况

3. **文本匹配**
   - `row_containing` 使用字符串匹配
   - 可能被其他文本误匹配

### 改进建议

1. **快照测试**
   - 使用 insta 进行渲染结果快照测试
   - 更容易发现意外的视觉变化

2. **参数化测试**
   - 测试多种终端尺寸
   - 确保动画在各种尺寸下正确显示

3. **帧内容测试**
   - 验证每帧的字符有效性
   - 确保没有非法字符

### 测试扩展

```rust
#[test]
fn all_frames_have_same_dimensions() {
    let first_frame = FRAMES_HBARS[0];
    let line_count = first_frame.lines().count();
    let max_width = first_frame.lines().map(|l| l.len()).max();
    
    for (i, frame) in FRAMES_HBARS.iter().enumerate() {
        assert_eq!(
            frame.lines().count(),
            line_count,
            "Frame {} has different line count",
            i + 1
        );
    }
}
```
