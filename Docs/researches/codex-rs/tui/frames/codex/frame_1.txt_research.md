# frame_1.txt 研究文档

## 场景与职责

`frame_1.txt` 是 Codex TUI（终端用户界面）欢迎界面 ASCII 动画序列的第一帧。该文件属于 `codex` 动画变体，在 TUI 启动时展示 OpenAI Codex 品牌的动态 ASCII 艺术效果，为用户提供视觉吸引力的初始体验。

## 功能点目的

1. **品牌展示**：展示 Codex 标志的 ASCII 艺术表现形式
2. **动画序列起点**：作为 36 帧循环动画的第一帧，启动整个欢迎动画
3. **终端美学**：在纯文本终端环境中提供视觉吸引力的图形元素
4. **用户引导**：配合欢迎文字 "Welcome to Codex, OpenAI's command-line coding agent" 使用

## 具体技术实现

### 文件格式与结构
- **格式**：纯文本 ASCII 艺术
- **尺寸**：17 行 × 40 列（标准终端字符尺寸）
- **字符集**：使用空格、`o`、`e`、`c`、`x`、`d` 等字符构建渐变效果
- **文件大小**：662 字节

### 动画系统集成

#### 编译时嵌入
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

pub(crate) const FRAMES_CODEX: [&str; 36] = frames_for!("codex");
```

#### 动画驱动机制
- **帧率控制**：`FRAME_TICK_DEFAULT = Duration::from_millis(80)`（80ms/帧，约 12.5 FPS）
- **动画控制器**：`AsciiAnimation` 结构体（`ascii_animation.rs`）
- **帧调度**：`FrameRequester` 通过 Tokio 异步任务调度帧绘制

#### 关键数据结构
```rust
// AsciiAnimation 结构定义
pub(crate) struct AsciiAnimation {
    request_frame: FrameRequester,
    variants: &'static [&'static [&'static str]],
    variant_idx: usize,
    frame_tick: Duration,
    start: Instant,
}
```

### 渲染流程

1. **WelcomeWidget 渲染**（`onboarding/welcome.rs`）
   ```rust
   impl WidgetRef for &WelcomeWidget {
       fn render_ref(&self, area: Rect, buf: &mut Buffer) {
           if self.animations_enabled {
               self.animation.schedule_next_frame();
           }
           let frame = self.animation.current_frame();
           lines.extend(frame.lines().map(Into::into));
       }
   }
   ```

2. **帧索引计算**
   ```rust
   pub(crate) fn current_frame(&self) -> &'static str {
       let elapsed_ms = self.start.elapsed().as_millis();
       let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
       frames[idx]
   }
   ```

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/frames/codex/frame_1.txt` | 本文件：动画第一帧数据 |
| `codex-rs/tui/src/frames.rs` | 帧数据编译时嵌入宏定义 |
| `codex-rs/tui/src/ascii_animation.rs` | ASCII 动画控制器实现 |
| `codex-rs/tui/src/onboarding/welcome.rs` | 欢迎界面组件，使用动画 |
| `codex-rs/tui/src/tui/frame_requester.rs` | 帧调度与速率限制 |

### 调用链
```
main() → run_onboarding_app() → WelcomeWidget::new() 
  → AsciiAnimation::new() → AsciiAnimation::current_frame()
    → FRAMES_CODEX[frame_index] → frame_1.txt (循环)
```

### 显示条件
- **最小高度**：`MIN_ANIMATION_HEIGHT = 37` 行
- **最小宽度**：`MIN_ANIMATION_WIDTH = 60` 列
- **动画开关**：`animations_enabled` 配置项

## 依赖与外部交互

### 编译依赖
- **Rust 宏系统**：`include_str!` 编译时文件嵌入
- **Cargo 构建**：文件变更触发重新编译

### 运行时依赖
- **ratatui**：终端 UI 渲染库
- **tokio**：异步运行时，用于帧调度
- **crossterm**：跨平台终端控制

### 变体切换
用户可通过 `Ctrl+.` 快捷键在以下变体间随机切换：
- `FRAMES_DEFAULT` - 默认动画
- `FRAMES_CODEX` - Codex 标志（本文件所属）
- `FRAMES_OPENAI` - OpenAI 标志
- `FRAMES_BLOCKS`, `FRAMES_DOTS`, `FRAMES_HASH`, `FRAMES_HBARS`, `FRAMES_VBARS`, `FRAMES_SHAPES`, `FRAMES_SLUG` - 其他动画效果

## 风险、边界与改进建议

### 潜在风险
1. **编译时依赖**：文件缺失或格式错误会导致编译失败
2. **二进制体积**：36 帧 × 662 字节 ≈ 23KB 静态数据嵌入二进制
3. **终端兼容性**：依赖等宽字体显示，某些终端可能渲染异常

### 边界条件
- **尺寸限制**：终端小于 60×37 时动画自动隐藏
- **性能边界**：120 FPS 最大帧率限制（`MIN_FRAME_INTERVAL`）
- **循环边界**：36 帧循环，第 36 帧后回到第 1 帧

### 改进建议
1. **动态加载**：考虑运行时从文件系统加载，减少二进制体积
2. **压缩优化**：ASCII 艺术可使用 RLE 等简单压缩
3. **主题适配**：支持根据终端主题自动调整字符密度
4. **无障碍支持**：提供 `--no-animation` 选项完全禁用动画
5. **帧率可调**：允许用户自定义动画速度

### 测试覆盖
- `welcome_renders_animation_on_first_draw`：验证首帧渲染
- `welcome_skips_animation_below_height_breakpoint`：验证尺寸边界
- `ctrl_dot_changes_animation_variant`：验证变体切换
