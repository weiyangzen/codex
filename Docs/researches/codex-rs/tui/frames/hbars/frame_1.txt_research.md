# frame_1.txt 研究文档

## 场景与职责

`frame_1.txt` 是 Codex TUI（终端用户界面）欢迎界面动画的 36 帧序列中的第 1 帧。该文件属于 `hbars`（水平条形图）动画变体，用于在用户启动 Codex CLI 时展示动态 ASCII 艺术效果，提升用户体验和视觉吸引力。

该帧在动画循环中作为起始帧，展示了一个复杂的水平条形图案，由 Unicode 块字符（Block Elements）组成，形成一个对称的、类似声波或数据可视化的图案。

## 功能点目的

1. **视觉欢迎效果**：作为 Codex 品牌标识的一部分，在用户登录前展示动态视觉效果
2. **动画序列起始**：36 帧循环动画的第 1 帧，建立动画的初始视觉状态
3. **变体区分**：`hbars` 变体使用水平条形字符（▁▂▃▄▅▆▇█）创建独特的视觉风格，与其他变体（如 `vbars` 垂直条形、`dots` 点阵等）区分

## 具体技术实现

### 数据结构

- **文件格式**：纯文本文件，17 行，每行 39 个字符（含空格）
- **字符集**：Unicode Block Elements（U+2581-U+2588）
  - `▁` (U+2581) - 下 1/8 块
  - `▂` (U+2582) - 下 1/4 块
  - `▃` (U+2583) - 下 3/8 块
  - `▄` (U+2584) - 下 1/2 块
  - `▅` (U+2585) - 下 5/8 块
  - `▆` (U+2586) - 下 3/4 块
  - `▇` (U+2587) - 下 7/8 块
  - `█` (U+2588) - 完整块

### 关键代码路径

1. **编译时嵌入**：
   ```rust
   // codex-rs/tui/src/frames.rs
   macro_rules! frames_for {
       ($dir:literal) => {
           [
               include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
               // ... frame_2.txt 到 frame_36.txt
           ]
       };
   }
   pub(crate) const FRAMES_HBARS: [&str; 36] = frames_for!("hbars");
   ```

2. **动画驱动**：
   ```rust
   // codex-rs/tui/src/ascii_animation.rs
   pub(crate) fn current_frame(&self) -> &'static str {
       let frames = self.frames();
       let elapsed_ms = self.start.elapsed().as_millis();
       let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
       frames[idx]  // 返回当前帧内容（如 frame_1.txt）
   }
   ```

3. **渲染流程**：
   ```rust
   // codex-rs/tui/src/onboarding/welcome.rs
   let frame = self.animation.current_frame();
   lines.extend(frame.lines().map(Into::into));
   ```

### 动画参数

- **帧率**：80ms/帧（`FRAME_TICK_DEFAULT = Duration::from_millis(80)`）
- **总时长**：36 帧 × 80ms = 2.88 秒/循环
- **显示条件**：终端高度 ≥ 37 行，宽度 ≥ 60 列

## 依赖与外部交互

### 上游依赖

| 组件 | 路径 | 关系 |
|------|------|------|
| `frames.rs` | `codex-rs/tui/src/frames.rs` | 编译时通过 `include_str!` 嵌入本文件内容 |
| `ascii_animation.rs` | `codex-rs/tui/src/ascii_animation.rs` | 驱动帧切换逻辑 |
| `welcome.rs` | `codex-rs/tui/src/onboarding/welcome.rs` | 渲染动画到欢迎界面 |

### 下游消费

- **欢迎界面**：`WelcomeWidget` 在 `render_ref` 方法中调用 `current_frame()` 获取当前帧内容
- **帧切换**：用户可按 `Ctrl+.` 随机切换动画变体（从 `ALL_VARIANTS` 中选择）

### 并行实现

`tui_app_server`  crate 包含相同的帧文件和 `frames.rs` 实现，确保服务器端和客户端行为一致。

## 风险、边界与改进建议

### 风险

1. **编码兼容性**：Unicode 块字符在某些终端字体中可能显示为方框或问号，影响视觉效果
2. **终端尺寸限制**：小尺寸终端（< 37×60）会完全跳过动画显示
3. **编译时依赖**：`include_str!` 要求文件在编译时存在，删除或重命名会导致编译失败

### 边界条件

- **空帧处理**：`current_frame()` 在帧为空时返回空字符串（本帧非空）
- **索引越界**：通过 `% frames.len()` 确保索引安全
- **时间溢出**：`elapsed_ms` 使用 `u128`，可支持约 10^29 年的运行时间

### 改进建议

1. **字体检测**：在启动时检测终端是否支持 Unicode 块字符，不支持时回退到 ASCII 变体
2. **响应式尺寸**：提供不同尺寸的帧版本，适应各种终端大小
3. **帧压缩**：36 帧文件内容相似，可考虑运行时生成或差分压缩减少二进制体积
4. **可配置性**：允许用户通过配置文件选择默认动画变体或禁用动画
5. **无障碍支持**：为视觉障碍用户提供动画禁用选项或替代文本描述
