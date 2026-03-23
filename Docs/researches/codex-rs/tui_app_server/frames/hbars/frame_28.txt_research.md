# Frame 28 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 28 是 HBARS 动画序列的第二十八帧，位于第二阶段的后期。此帧继续展示波浪形态的演变，条块分布进一步变化，是整个 36 帧循环中第二阶段后期的重要帧。

在 36 帧循环中，Frame 28 代表了约 77.8% 的进度（28/36），标志着第二阶段进入后期关键阶段。

## 功能点目的

1. **后期关键**：第二阶段后期的关键帧
2. **变化深化**：深化条块分布的变化
3. **视觉动态**：提供更动态的视觉体验
4. **循环准备**：为 Frame 29-36 的循环结束做准备

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
- **帧索引**：27（在 FRAMES_HBARS 数组中）
- **显示时序**：第 2160-2240ms

### 视觉模式
Frame 28 展示了后期关键状态：
- 条块分布进一步变化
- 波浪形态更加动态
- 为 Frame 29-36 的循环结束做铺垫

## 关键代码路径与文件引用

### 帧定义
```rust
// codex-rs/tui_app_server/src/frames.rs
pub(crate) const FRAMES_HBARS: [&str; 36] = frames_for!("hbars");
// Frame 28: FRAMES_HBARS[27]
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

### 状态管理
- `StepState::Hidden`: 已登录用户不显示欢迎屏幕
- `StepState::Complete`: 未登录用户显示欢迎屏幕

### 动画变体
用户可通过 `Ctrl+.` 在以下变体间切换：
- DEFAULT, CODEX, OPENAI, BLOCKS, DOTS, HASH, HBARS, VBARS, SHAPES, SLUG

## 风险、边界与改进建议

### 风险与边界

1. **登录状态检测**
   - `is_logged_in` 可能不准确
   - 导致动画显示/隐藏异常

2. **变体持久化**
   - 当前变体选择不保存
   - 每次启动重置为 DEFAULT

3. **无障碍支持**
   - 动画对屏幕阅读器用户造成干扰
   - 缺少关闭动画的选项

### 改进建议

1. **偏好持久化**
   - 将动画变体选择保存到配置文件
   - 下次启动时恢复

2. **无障碍选项**
   - 添加 `--no-animation` 命令行选项
   - 检测 `NO_ANIMATION` 环境变量

3. **动画开关**
   - 在设置界面添加动画开关
   - 允许用户永久关闭动画

### 配置示例

```toml
# ~/.config/codex/config.toml
[ui]
animation_variant = "hbars"
animation_enabled = true
animation_fps = 12.5
```
