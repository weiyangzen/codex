# Frame 2 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 2 是 HBARS 动画序列的第二帧，承接 Frame 1 建立的初始波浪形态，开始展示水平条块的渐进演变。作为循环早期的过渡帧，它负责将初始状态平滑地引导至动画的中期发展阶段。

在 36 帧的完整循环中，Frame 2 代表了约 2.8% 的进度（2/36），标志着波浪从起始状态向更复杂模式的过渡。

## 功能点目的

1. **过渡承接**：承接 Frame 1 的视觉状态，开始第一波形的演变
2. **动态建立**：通过条块位置的微调，建立动画的持续运动感
3. **视觉连续性**：确保与 Frame 1 和 Frame 3 之间的视觉连贯性
4. **节奏维持**：保持 80ms 帧间隔下的流畅视觉节奏

## 具体技术实现

### Unicode 字符集
使用标准 Unicode 块元素字符：
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
- **帧索引**：1（在 FRAMES_HBARS 数组中）
- **显示时序**：在 80ms 帧间隔下，此帧显示时间为第 80-160ms

### 与 Frame 1 的差异
Frame 2 相较于 Frame 1 的主要变化：
- 顶部波峰区域：高度略有增加，波形更加明显
- 中部区域：条块分布更加分散，创造更强烈的流动感
- 底部区域：开始形成新的波谷形态

## 关键代码路径与文件引用

### 帧数组定义
```rust
// codex-rs/tui_app_server/src/frames.rs
pub(crate) const FRAMES_HBARS: [&str; 36] = frames_for!("hbars");
// Frame 2 对应索引 1
```

### 动画时序计算
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
// 当 elapsed_ms 在 80-160ms 范围时，idx = 1，显示 Frame 2
```

### 欢迎屏幕集成
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
impl WidgetRef for &WelcomeWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        if self.animations_enabled {
            self.animation.schedule_next_frame();
        }
        let frame = self.animation.current_frame(); // 可能返回 Frame 2
        lines.extend(frame.lines().map(Into::into));
    }
}
```

## 依赖与外部交互

### 核心依赖
- **FrameRequester**: 负责调度下一帧的渲染请求
- **ratatui**: 提供终端 UI 渲染能力
- **tokio**: 异步运行时，处理帧调度定时器

### 变体切换交互
用户可通过 `Ctrl+.` 切换到其他动画变体：
- FRAMES_DEFAULT
- FRAMES_CODEX
- FRAMES_OPENAI
- FRAMES_BLOCKS
- FRAMES_DOTS
- FRAMES_HASH
- FRAMES_VBARS
- FRAMES_SHAPES
- FRAMES_SLUG

## 风险、边界与改进建议

### 风险与边界

1. **帧率同步**
   - 在系统负载高时，80ms 的帧间隔可能无法保证
   - 可能导致 Frame 2 被跳过或显示时间不一致

2. **终端渲染延迟**
   - 某些终端模拟器（如 Windows CMD）渲染 Unicode 块字符较慢
   - 可能影响动画流畅度

3. **尺寸适配**
   - 固定 40 字符宽度在小屏幕终端上可能被截断

### 改进建议

1. **自适应帧率**
   - 监测实际帧渲染时间，动态调整帧间隔
   - 在慢速终端上自动降低帧率

2. **帧内容优化**
   - Frame 2 与 Frame 1 的差异较小，可考虑合并或增加变化幅度
   - 增强视觉冲击力

3. **调试支持**
   - 添加 `CODEX_DEBUG_ANIMATION=1` 环境变量，显示当前帧索引和时序信息

### 测试验证

```bash
# 验证帧文件存在
ls -la codex-rs/tui_app_server/frames/hbars/frame_2.txt

# 查看帧内容
cat codex-rs/tui_app_server/frames/hbars/frame_2.txt

# 运行动画相关测试
cargo test -p codex-tui-app-server ascii_animation
```
