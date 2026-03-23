# frame_1.txt 研究文档

## 场景与职责

`frame_1.txt` 是 Codex TUI 应用服务器中 ASCII 动画系统的一部分，具体属于 `codex` 变体动画序列的第 1 帧。该文件存储在 `codex-rs/tui_app_server/frames/codex/` 目录下，是 36 帧旋转 Codex 图标动画的起始帧。

**使用场景：**
- 在 TUI（终端用户界面）的欢迎界面（WelcomeWidget）中显示动态 ASCII 艺术
- 作为启动/加载状态的视觉反馈
- 通过 `Ctrl+.` 快捷键可在 10 种动画变体间切换

## 功能点目的

1. **视觉品牌展示**：展示 Codex 品牌标识的旋转动画效果
2. **终端美学**：在纯文本终端环境中提供视觉吸引力的动态内容
3. **用户参与**：通过动画效果提升用户等待时的体验

## 具体技术实现

### 文件格式
- **格式**：纯文本 ASCII 艺术
- **尺寸**：17 行 x 40 列（固定尺寸）
- **字符集**：使用字母 `e`, `o`, `c`, `d`, `x` 等构成 Codex 图标图案
- **文件大小**：662 字节

### 动画系统集成

**编译时嵌入**（`frames.rs`）：
```rust
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            // ... frame_2 到 frame_36
        ]
    };
}

pub(crate) const FRAMES_CODEX: [&str; 36] = frames_for!("codex");
```

**动画驱动**（`ascii_animation.rs`）：
- 使用 `AsciiAnimation` 结构体管理动画状态
- 默认帧率：`FRAME_TICK_DEFAULT = Duration::from_millis(80)`（12.5 FPS）
- 帧索引计算：`(elapsed_ms / tick_ms) % frames.len()`

**渲染流程**（`welcome.rs`）：
```rust
let frame = self.animation.current_frame();
lines.extend(frame.lines().map(Into::into));
```

### 关键数据结构

```rust
// 动画变体集合
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,   // 默认变体
    &FRAMES_CODEX,     // Codex 图标（本文件所属）
    &FRAMES_OPENAI,    // OpenAI 标志
    &FRAMES_BLOCKS,    // 方块动画
    &FRAMES_DOTS,      // 点动画
    &FRAMES_HASH,      // 哈希图案
    &FRAMES_HBARS,     // 水平条
    &FRAMES_VBARS,     // 垂直条
    &FRAMES_SHAPES,    // 几何形状
    &FRAMES_SLUG,      //  slug 图案
];
```

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/frames.rs` | 定义 `frames_for!` 宏，编译时嵌入所有帧文件 |
| `codex-rs/tui_app_server/src/ascii_animation.rs` | `AsciiAnimation` 结构体，管理动画时序和帧切换 |
| `codex-rs/tui_app_server/src/onboarding/welcome.rs` | 欢迎组件，实际渲染动画帧 |
| `codex-rs/tui_app_server/src/tui/frame_requester.rs` | 帧调度器，控制动画刷新率（最高 120 FPS） |

### 调用链
```
WelcomeWidget::render_ref()
  └─> AsciiAnimation::current_frame()
      └─> FRAMES_CODEX[frame_index]  // 返回本文件内容
```

### 帧调度
```
FrameRequester::schedule_frame_in()
  └─> FrameScheduler::run()  // 合并多个请求，限制最高 120 FPS
      └─> 触发 TUI 重绘
```

## 依赖与外部交互

### 编译依赖
- **Bazel**：`BUILD.bazel` 使用 `glob(include = ["**"])` 包含所有帧文件作为编译数据
- **Cargo**：通过 `include_str!` 宏在编译时将文件内容嵌入二进制

### 运行时依赖
- **ratatui**：用于终端渲染
- **tokio**：异步运行时，用于帧调度
- **crossterm**：终端事件处理（`Ctrl+.` 切换变体）

### 交互方式
| 交互 | 说明 |
|-----|------|
| `Ctrl+.` | 随机切换到其他动画变体 |
| 终端大小变化 | 当终端小于 60x37 时自动隐藏动画 |
| 动画开关 | 可通过配置禁用动画 |

## 风险、边界与改进建议

### 风险
1. **二进制体积**：36 帧 x 10 变体 = 360 个文件全部嵌入二进制，增加约 240KB
2. **固定帧率**：80ms 的默认帧率在某些终端上可能显得卡顿
3. **尺寸限制**：固定 40x17 尺寸，无法自适应不同终端大小

### 边界情况
1. **终端过小**：当终端宽度 < 60 或高度 < 37 时，动画被跳过（`MIN_ANIMATION_WIDTH/HEIGHT`）
2. **空帧处理**：`current_frame()` 返回空字符串时，渲染逻辑已处理
3. **变体索引越界**：通过 `variant_idx.min(variants.len() - 1)` 保护

### 改进建议
1. **动态帧率**：根据终端性能自适应调整帧率
2. **延迟加载**：将帧文件改为运行时从文件系统加载，减少二进制体积
3. **响应式尺寸**：支持根据终端大小缩放动画
4. **压缩存储**：使用 RLE 或其他压缩算法减少帧数据大小
5. **主题集成**：支持根据终端主题调整 ASCII 字符密度（暗色主题使用更密字符）
