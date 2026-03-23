# 研究报告：codex-rs/tui/frames/default/frame_1.txt

## 场景与职责

`frame_1.txt` 是 Codex TUI（终端用户界面）默认 ASCII 艺术动画序列的第 1 帧。该文件是 36 帧动画序列的起始帧，用于在应用启动时展示欢迎界面的动态视觉效果。

**核心职责**：
- 作为动画序列的第一帧，展示 Codex 品牌标识的初始状态
- 提供视觉吸引力，增强用户首次使用时的品牌印象
- 配合 `ascii_animation.rs` 驱动器实现流畅的旋转动画效果

## 功能点目的

### 动画序列中的定位
- **帧序号**: 1/36（动画序列的起始点）
- **动画主题**: 抽象几何符号风格的旋转图案
- **视觉风格**: 使用 `=+,_`、`*|/` 等符号构成的对称几何图形

### 艺术风格特征
本帧展示了一个由特殊字符构成的抽象旋转图案：
- 使用字符：`=`, `+`, `,`, `_`, `*`, `|`, `/`, `\`, `^`, `~`, `;`, `:`, `"`, `'`, `!`, `\``, `.`, `-`, `|`, `\`, `/`
- 图案呈现对称的放射状结构，暗示旋转运动的开始
- 中心区域密集，边缘逐渐稀疏，形成视觉焦点

## 具体技术实现

### 文件规格
```
尺寸: 17 行 × 39 列（固定尺寸，所有帧保持一致）
编码: UTF-8
格式: 纯文本，使用空格进行精确对齐
```

### 编译时嵌入
该文件通过 `frames.rs` 中的宏在编译时被嵌入到二进制中：

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

pub(crate) const FRAMES_DEFAULT: [&str; 36] = frames_for!("default");
```

### 动画渲染流程
1. **编译阶段**: `include_str!` 宏将文件内容作为字符串字面量嵌入
2. **运行时**: `AsciiAnimation` 结构体管理帧的切换逻辑
3. **渲染时**: `current_frame()` 方法根据时间计算当前应显示的帧
4. **显示**: `WelcomeWidget` 将帧内容渲染到终端界面

### 帧切换机制
```rust
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let tick_ms = self.frame_tick.as_millis();  // 默认 80ms
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]  // 返回当前帧（如 frame_1.txt 内容）
}
```

## 关键代码路径与文件引用

### 直接依赖
| 文件 | 用途 |
|------|------|
| `codex-rs/tui/src/frames.rs` | 定义 `frames_for!` 宏，编译时嵌入本帧 |
| `codex-rs/tui/src/ascii_animation.rs` | 动画驱动器，控制帧切换逻辑 |
| `codex-rs/tui/src/onboarding/welcome.rs` | 欢迎界面组件，渲染动画帧 |

### 调用链
```
frame_1.txt (编译时嵌入)
    ↓
frames.rs → FRAMES_DEFAULT[0]
    ↓
AsciiAnimation::current_frame() → 返回帧内容
    ↓
WelcomeWidget::render_ref() → 渲染到终端
```

### BUILD.bazel 配置
```bazel
codex_rust_crate(
    name = "tui",
    compile_data = glob(
        include = ["**"],  # 包含 frames/default/*.txt
        ...
    ),
)
```

## 依赖与外部交互

### 内部依赖
- **`codex-rs/tui/src/tui/frame_requester.rs`**: 提供 `FrameRequester` 用于调度下一帧渲染
- **`codex-rs/tui/src/frames.rs`**: 定义 `FRAMES_DEFAULT` 常量数组
- **`codex-rs/tui/src/onboarding/welcome.rs`**: 消费帧内容并渲染

### 外部依赖（运行时）
- **ratatui**: 用于终端 UI 渲染
- **crossterm**: 处理终端尺寸和输入事件

### 动画变体
本帧属于 `default` 变体，同目录下还有其他变体：
- `codex`: 品牌标识风格
- `openai`: OpenAI 标志风格
- `blocks`, `dots`, `hash`, `hbars`, `vbars`, `shapes`, `slug`: 其他视觉风格

## 风险、边界与改进建议

### 潜在风险
1. **编译时依赖**: 文件必须在编译时存在，缺失会导致编译失败
2. **尺寸固定**: 17×39 的尺寸是硬编码约定，修改需同步调整所有帧
3. **字符编码**: 使用 Unicode 字符，需确保终端支持

### 边界条件
- **最小显示尺寸**: `MIN_ANIMATION_HEIGHT = 37`, `MIN_ANIMATION_WIDTH = 60`
- **帧率**: 默认 80ms 切换一次（约 12.5 FPS）
- **完整动画周期**: 36 帧 × 80ms = 2.88 秒

### 改进建议
1. **动态加载**: 考虑从配置文件加载帧，避免重新编译
2. **响应式尺寸**: 支持根据终端尺寸自动缩放
3. **主题扩展**: 允许用户自定义动画主题
4. **性能优化**: 对于低性能终端，可降低帧率或禁用动画

### 测试覆盖
- `welcome_renders_animation_on_first_draw`: 验证首帧渲染
- `welcome_skips_animation_below_height_breakpoint`: 验证尺寸不足时跳过动画
- `ctrl_dot_changes_animation_variant`: 验证 Ctrl+. 切换变体

---
*研究范围：frame_1.txt 及其在 Codex TUI 动画系统中的角色*
