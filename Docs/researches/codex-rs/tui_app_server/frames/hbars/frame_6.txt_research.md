# Frame 6 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 6 是 HBARS 动画序列的第六帧，标志着动画从早期阶段正式进入中期阶段。此帧展现出波浪形态的显著变化，条块分布更加动态和复杂，是整个动画循环中视觉变化较明显的帧之一。

在 36 帧循环中，Frame 6 代表了约 16.7% 的进度（6/36），是中期阶段的起始帧。

## 功能点目的

1. **阶段转换**：标志从早期阶段向中期阶段的过渡
2. **动态增强**：显著增加波浪的动态感和复杂度
3. **视觉冲击**：提供更强烈的视觉变化，吸引用户注意
4. **节奏加速**：通过更明显的变化创造加速感

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
- **帧索引**：5（在 FRAMES_HBARS 数组中）
- **显示时序**：第 400-480ms

### 视觉模式
Frame 6 展示了动态增强的波浪：
- 顶部：波峰开始快速移动
- 中部：出现多个交错的波峰和波谷
- 底部：条块快速重组，创造流动感

## 关键代码路径与文件引用

### 帧数组
```rust
// codex-rs/tui_app_server/src/frames.rs
pub(crate) const FRAMES_HBARS: [&str; 36] = frames_for!("hbars");
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,
    &FRAMES_CODEX,
    // ... &FRAMES_HBARS 在索引 6
];
```

### 随机变体选择
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
pub(crate) fn pick_random_variant(&mut self) -> bool {
    let mut rng = rand::rng();
    let mut next = self.variant_idx;
    while next == self.variant_idx {
        next = rng.random_range(0..self.variants.len());
    }
    self.variant_idx = next;
    self.request_frame.schedule_frame();
    true
}
```

### 键盘处理
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
impl KeyboardHandler for WelcomeWidget {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        if key_event.code == KeyCode::Char('.')
            && key_event.modifiers.contains(KeyModifiers::CONTROL) {
            let _ = self.animation.pick_random_variant();
        }
    }
}
```

## 依赖与外部交互

### 外部 crate
- **rand**: 随机数生成，用于变体切换
- **ratatui**: 终端 UI 渲染
- **crossterm**: 键盘事件处理

### 内部模块
- `frames`: 帧数据定义
- `ascii_animation`: 动画控制逻辑
- `tui::FrameRequester`: 帧调度

## 风险、边界与改进建议

### 风险与边界

1. **随机数生成**
   - `pick_random_variant` 使用 `rand::rng()`，在测试时需要 mock
   - 建议：提供确定性模式用于测试

2. **变体切换延迟**
   - 切换变体后，当前帧索引保持不变
   - 可能导致视觉跳跃

3. **内存布局**
   - 36 个 `&str` 的数组在栈上分配
   - 虽然 36×16=576 字节不大，但变体多时累积

### 改进建议

1. **平滑变体过渡**
   - 变体切换时淡入淡出

2. **帧缓存**
   - 缓存渲染结果，减少重复计算

3. **性能监控**
   - 添加指标收集帧渲染时间

### 测试代码示例

```rust
#[test]
fn frame_6_content_valid() {
    let frame = FRAMES_HBARS[5];
    assert!(!frame.is_empty());
    assert!(frame.lines().count() == 17);
    // 验证只包含允许的字符
    for ch in frame.chars() {
        assert!(ch.is_whitespace() || "▁▂▃▄▅▆▇█".contains(ch));
    }
}
```
