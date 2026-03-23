# frame_6.txt 研究文档

## 场景与职责

`frame_6.txt` 是 Codex TUI App Server 中 `blocks` 动画变体的第六帧，展示3D方块旋转动画的第六个时间切片。在36帧循环中，该帧于动画开始后的 400ms-480ms 时间段显示，代表约 16.7% 的动画周期完成。

该文件作为静态 ASCII 艺术资源，在编译时嵌入到应用程序二进制中。

## 功能点目的

1. **旋转动画推进**：展示方块从 frame_5 继续旋转的状态
2. **视觉连贯性维护**：确保 frame_5 → frame_6 → frame_7 的过渡平滑
3. **循环动画构建**：作为36帧序列的 1/6 部分，贡献于完整的 2.88 秒周期

## 具体技术实现

### 时序与索引

```rust
// 帧参数
const FRAME_INDEX: usize = 5;           // 数组索引（从0开始）
const FRAME_NUMBER: usize = 6;          // 帧号（从1开始）
const DISPLAY_START_MS: u64 = 400;      // 开始显示时间
const DISPLAY_END_MS: u64 = 480;        // 结束显示时间
const CYCLE_PERCENTAGE: f64 = 16.67;    // 周期完成百分比
```

### 数据结构

```rust
// 在 FRAMES_BLOCKS 数组中的位置
pub(crate) const FRAMES_BLOCKS: [&str; 36] = [
    // frame_1 到 frame_5 ...
    include_str!("../frames/blocks/frame_6.txt"),  // [5]
    // frame_7 到 frame_36 ...
];

// 变体数组引用
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,   // [0]
    &FRAMES_CODEX,     // [1]
    &FRAMES_OPENAI,    // [2]
    &FRAMES_BLOCKS,    // [3] <- 包含当前文件
    // ... 其他变体
];
```

### 动画控制流程

```rust
impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();  // 返回 &FRAMES_BLOCKS
        if frames.is_empty() { return ""; }
        
        let tick_ms = self.frame_tick.as_millis();  // 80ms
        let elapsed_ms = self.start.elapsed().as_millis();
        
        // 当 elapsed_ms 在 400-480 之间时，idx = 5
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        frames[idx]  // 返回 frame_6.txt 内容
    }
}
```

## 关键代码路径与文件引用

### 编译时路径
| 阶段 | 文件 | 行 | 代码 |
|------|------|-----|------|
| 宏定义 | `frames.rs` | 4-44 | `macro_rules! frames_for` |
| 宏调用 | `frames.rs` | 50 | `frames_for!("blocks")` |
| 具体嵌入 | `frames.rs` | 12 | `include_str!(..."/frame_6.txt")` |

### 运行时路径
```
App::run()
  → render_loop()
    → WelcomeWidget::render_ref()
      → AsciiAnimation::current_frame()
        → frames[5]  // frame_6
      → Paragraph::new(frame)
    → Terminal::flush()
```

## 依赖与外部交互

### 依赖图
```
frame_6.txt
  ↑ (编译时嵌入)
frames.rs → FRAMES_BLOCKS[5]
  ↑
ascii_animation.rs → AsciiAnimation
  ↑
welcome.rs → WelcomeWidget
  ↑
app.rs → App (主应用)
```

### 外部系统
- **终端**: 通过 crossterm 输出 Unicode 块字符
- **渲染引擎**: ratatui 处理布局和样式
- **事件系统**: FrameRequester 驱动动画更新

## 风险、边界与改进建议

### 风险

1. **编译依赖**：
   - 文件必须在编译时存在
   - 删除或重命名会导致编译失败

2. **字符渲染**：
   - 块字符宽度计算可能因终端而异
   - 双宽字符在某些终端可能导致布局错乱

### 边界

1. **最小终端尺寸**：
   ```rust
   const MIN_ANIMATION_HEIGHT: u16 = 37;
   const MIN_ANIMATION_WIDTH: u16 = 60;
   ```
   - 低于此尺寸时动画被完全跳过

2. **动画开关**：
   - `animations_enabled` 标志可禁用所有动画
   - 禁用时 frame_6 永不显示

### 改进建议

1. **程序化动画**：
   ```rust
   // 使用 3D 投影替代预渲染帧
   fn render_rotating_cube(angle: f32) -> Vec<String> {
       // 实时计算投影...
   }
   ```

2. **帧缓存优化**：
   ```rust
   struct AsciiAnimation {
       cached_lines: Vec<Vec<Line<'static>>>,  // 预解析的帧
   }
   ```

3. **可配置帧率**：
   ```toml
   # config.toml
   [animation]
   frame_rate = 15  # fps，默认 12.5
   ```

---

**文件元数据**：
- 路径：`codex-rs/tui_app_server/frames/blocks/frame_6.txt`
- 大小：1172 bytes
- 行数：17行
- 帧序号：6/36
- 变体：blocks
- 显示时间：400ms-480ms
- 周期位置：~16.7%
