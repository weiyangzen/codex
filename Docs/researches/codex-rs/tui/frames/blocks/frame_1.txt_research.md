# frame_1.txt 研究文档

## 场景与职责

`frame_1.txt` 是 Codex TUI (Terminal User Interface) 的 ASCII 艺术动画帧文件，属于 `blocks` 动画变体的第 1 帧。该文件是 36 帧循环动画序列的起始帧，用于在 Codex CLI 的欢迎界面（WelcomeWidget）中展示动态的 ASCII 艺术动画效果。

## 功能点目的

1. **视觉动画效果**：作为循环动画的第一帧，展示一个由 Unicode 块字符组成的抽象图案
2. **品牌展示**：通过动态的 ASCII 艺术增强 Codex CLI 的终端用户体验
3. **加载状态指示**：在用户等待或初始化期间提供视觉反馈

## 具体技术实现

### 文件格式与内容

- **文件路径**: `codex-rs/tui/frames/blocks/frame_1.txt`
- **文件大小**: 约 1174 bytes
- **行数**: 17 行
- **字符编码**: UTF-8

### 使用的 Unicode 字符

文件使用以下 Unicode 块字符来创建灰度效果：

| 字符 | Unicode | 描述 | 视觉密度 |
|------|---------|------|----------|
| `█` | U+2588 | 全块 (Full Block) | 100% |
| `▓` | U+2593 | 深阴影 (Dark Shade) | 75% |
| `▒` | U+2592 | 中等阴影 (Medium Shade) | 50% |
| `░` | U+2591 | 浅阴影 (Light Shade) | 25% |
| ` ` | U+0020 | 空格 | 0% |

### 帧尺寸

- **宽度**: 约 40 字符
- **高度**: 17 行
- **宽高比**: 约 2.35:1（符合终端字符的矩形比例）

### 编译时嵌入

该文件通过 Rust 的 `include_str!` 宏在编译时嵌入到二进制中：

```rust
// codex-rs/tui/src/frames.rs
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            // ... 其他帧
        ]
    };
}

pub(crate) const FRAMES_BLOCKS: [&str; 36] = frames_for!("blocks");
```

### 动画渲染流程

1. **初始化**: `AsciiAnimation::new()` 创建动画驱动器
2. **帧选择**: 基于时间计算当前帧索引：`idx = (elapsed_ms / tick_ms) % frames.len()`
3. **渲染**: `WelcomeWidget` 通过 `current_frame()` 获取当前帧内容
4. **定时**: 默认帧间隔为 80ms (`FRAME_TICK_DEFAULT`)

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/frames.rs` | 定义 `frames_for!` 宏，编译时嵌入所有帧文件 |
| `codex-rs/tui/src/ascii_animation.rs` | `AsciiAnimation` 结构体，驱动动画时序和帧切换 |
| `codex-rs/tui/src/onboarding/welcome.rs` | `WelcomeWidget`，实际渲染欢迎界面和动画 |

### 代码引用链

```
frame_1.txt
    ↓ (include_str!)
codex-rs/tui/src/frames.rs: FRAMES_BLOCKS[0]
    ↓ (引用)
codex-rs/tui/src/ascii_animation.rs: AsciiAnimation::current_frame()
    ↓ (调用)
codex-rs/tui/src/onboarding/welcome.rs: WelcomeWidget::render_ref()
```

### 动画变体常量

```rust
// codex-rs/tui/src/frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = frames_for!("default");
pub(crate) const FRAMES_CODEX: [&str; 36] = frames_for!("codex");
pub(crate) const FRAMES_OPENAI: [&str; 36] = frames_for!("openai");
pub(crate) const FRAMES_BLOCKS: [&str; 36] = frames_for!("blocks");  // <-- 本文件所属
pub(crate) const FRAMES_DOTS: [&str; 36] = frames_for!("dots");
// ... 其他变体
```

## 依赖与外部交互

### 编译依赖

- **Rust 编译器**: 支持 `include_str!` 宏
- **文件系统**: 编译时需要访问 `../frames/blocks/frame_1.txt`

### 运行时依赖

- **ratatui**: 终端 UI 渲染库，用于在缓冲区绘制帧内容
- **crossterm**: 终端控制，处理清屏和光标定位
- **终端模拟器**: 需要支持 Unicode 块字符的终端

### 用户交互

- **Ctrl + .**: 用户可以按 Ctrl + 句号键切换不同的动画变体（如从 blocks 切换到 codex）
- **动画开关**: 可通过配置禁用动画效果

## 风险、边界与改进建议

### 潜在风险

1. **文件缺失**: 如果文件被删除或重命名，编译将失败
   ```
   error: couldn't read ../frames/blocks/frame_1.txt: No such file or directory
   ```

2. **编码问题**: 文件必须使用 UTF-8 编码，否则编译时可能出现字符解析错误

3. **尺寸变化**: 如果帧尺寸不一致，可能导致动画闪烁或布局错乱

### 边界条件

1. **终端尺寸**: `WelcomeWidget` 会在终端高度 < 37 或宽度 < 60 时跳过动画显示
   ```rust
   const MIN_ANIMATION_HEIGHT: u16 = 37;
   const MIN_ANIMATION_WIDTH: u16 = 60;
   ```

2. **帧率限制**: 默认 80ms 的帧间隔意味着动画以约 12.5 FPS 运行

3. **内存占用**: 所有帧在编译时嵌入，增加二进制大小约 36 × 平均帧大小

### 改进建议

1. **压缩优化**: 考虑使用更紧凑的格式存储帧数据，减少二进制体积

2. **动态加载**: 对于大量动画帧，可考虑运行时从文件系统加载而非编译时嵌入

3. **尺寸标准化**: 添加 CI 检查确保所有帧具有相同的尺寸

4. **可访问性**: 为视力障碍用户提供纯文本替代方案

5. **性能监控**: 在低端设备上监测动画对 CPU 的影响

### 测试覆盖

相关测试位于 `codex-rs/tui/src/onboarding/welcome.rs`：

- `welcome_renders_animation_on_first_draw`: 验证首帧渲染
- `welcome_skips_animation_below_height_breakpoint`: 验证小终端跳过动画
- `ctrl_dot_changes_animation_variant`: 验证变体切换功能
