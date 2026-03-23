# Frame 4 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 4 是 HBARS 动画序列的第四帧，位于循环早期阶段。此帧继续推进波浪形态的演变，展现出更加分散和动态的条块分布，标志着动画从简单波形向复杂模式的过渡。

在 36 帧循环中，Frame 4 代表了约 11.1% 的进度（4/36），是早期阶段向中期阶段过渡的关键帧。

## 功能点目的

1. **复杂度提升**：在前三帧基础上增加波浪的复杂度
2. **空间分散**：条块分布更加分散，创造更广阔的视觉空间
3. **动态过渡**：为中期帧的密集波形做铺垫
4. **视觉节奏**：维持 80ms 间隔下的流畅节奏感

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
- **帧索引**：3（在 FRAMES_HBARS 数组中）
- **显示时序**：第 240-320ms

### 视觉模式
Frame 4 展示了扩展式波浪：
- 顶部：波峰向两侧扩展
- 中部：出现多个小波峰和波谷
- 底部：条块开始向中心聚集

## 关键代码路径与文件引用

### 帧定义
```rust
// codex-rs/tui_app_server/src/frames.rs
pub(crate) const FRAMES_HBARS: [&str; 36] = frames_for!("hbars");
// Frame 4 存储在 FRAMES_HBARS[3]
```

### 动画控制
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
// Frame 4 在动画开始 240ms 后显示
```

### 欢迎屏幕渲染
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
const MIN_ANIMATION_HEIGHT: u16 = 37;
const MIN_ANIMATION_WIDTH: u16 = 60;
```

## 依赖与外部交互

### 核心组件
- **frames.rs**: 定义 FRAMES_HBARS 数组
- **ascii_animation.rs**: 控制帧选择和时序
- **welcome.rs**: 渲染帧到终端

### 外部库
- **ratatui**: 终端 UI 渲染
- **crossterm**: 终端控制和事件处理
- **rand**: 变体随机选择

## 风险、边界与改进建议

### 风险与边界

1. **终端宽度限制**
   - Frame 4 的分散模式需要较宽的显示区域
   - 在窄终端上可能丢失视觉细节

2. **字符渲染一致性**
   - 不同终端对 Unicode 块字符的渲染高度可能略有差异
   - 可能导致波浪边缘不够平滑

3. **颜色主题影响**
   - 在某些暗色主题下，低高度条块可能与背景难以区分

### 改进建议

1. **动态宽度调整**
   - 根据终端宽度动态选择窄版或宽版帧

2. **帧验证测试**
   - 添加测试确保所有帧的字符都在有效 Unicode 范围内

3. **渲染优化**
   - 使用 ratatui 的 `Span` 和 `Style` 为不同高度添加颜色渐变

### 调试命令

```bash
# 查看 Frame 4 内容
head -n 17 codex-rs/tui_app_server/frames/hbars/frame_4.txt

# 检查文件编码
file codex-rs/tui_app_server/frames/hbars/frame_4.txt

# 验证 Unicode 字符
hexdump -C codex-rs/tui_app_server/frames/hbars/frame_4.txt | head -20
```
