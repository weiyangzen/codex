# shapes/frame_1.txt 研究文档

## 场景与职责

`shapes/frame_1.txt` 是 Codex TUI（终端用户界面）应用程序服务器的 ASCII 艺术动画帧文件，属于 `shapes`（形状）动画变体的第 1 帧。该文件在 TUI 的欢迎界面（WelcomeWidget）中作为背景动画的一部分使用，为用户提供视觉上的加载/等待反馈。

**使用场景：**
- TUI 启动时的欢迎屏幕背景动画
- 通过 `Ctrl+.` 快捷键可切换不同的动画变体（包括 shapes）
- 当终端尺寸足够（最小高度 37 行，最小宽度 60 列）时显示动画

## 功能点目的

1. **视觉装饰**：为命令行界面提供美观的视觉效果，增强用户体验
2. **品牌识别**：使用几何形状（◆、△、●、□、▲、◇、○、■ 等 Unicode 字符）构成独特的视觉风格
3. **加载反馈**：动画帧的循环播放向用户表明应用程序正在运行
4. **变体多样性**：shapes 变体使用多种几何形状符号，与其他变体（如 codex、openai、blocks 等）形成差异化视觉风格

## 具体技术实现

### 文件格式
- **编码**：UTF-8（包含 Unicode 几何形状字符）
- **尺寸**：17 行 × 40 列（标准帧尺寸）
- **字符集**：使用 Unicode 几何图形块字符（U+25A0-U+25FF 范围）

### 帧内容分析
```
帧 1 展示了一个由多种几何形状组成的复杂图案：
- 使用符号：◆（菱形）、△（三角）、●（圆点）、□（方块）、▲（实心三角）、◇（空心菱形）、○（空心圆）、■（实心方块）
- 图案特征：中心向外扩散的形状排列，形成类似"爆炸"或"绽放"的视觉效果
- 视觉风格：高密度、多形状混合的抽象艺术图案
```

### 动画系统集成

**编译时嵌入**：
```rust
// frames.rs
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            // ... frame_2.txt 到 frame_36.txt
        ]
    };
}

pub(crate) const FRAMES_SHAPES: [&str; 36] = frames_for!("shapes");
```

**运行时渲染**：
```rust
// welcome.rs
let frame = self.animation.current_frame();
lines.extend(frame.lines().map(Into::into));
```

**帧切换逻辑**：
- 默认帧间隔：80 毫秒（`FRAME_TICK_DEFAULT`）
- 帧索引计算：`(elapsed_ms / tick_ms) % frames.len()`
- 循环播放：36 帧完成后回到第 1 帧

## 关键代码路径与文件引用

### 定义与注册
| 文件 | 作用 |
|------|------|
| `codex-rs/tui_app_server/src/frames.rs` | 定义 `FRAMES_SHAPES` 常量，使用 `include_str!` 宏在编译时嵌入本文件内容 |
| `codex-rs/tui_app_server/src/ascii_animation.rs` | 实现 `AsciiAnimation` 结构体，管理帧的时序和切换逻辑 |

### 使用位置
| 文件 | 作用 |
|------|------|
| `codex-rs/tui_app_server/src/onboarding/welcome.rs` | 在欢迎界面中渲染动画帧 |
| `codex-rs/tui_app_server/src/tui/frame_requester.rs` | 调度帧绘制请求，控制动画刷新率（最高 120 FPS） |

### 构建配置
| 文件 | 作用 |
|------|------|
| `codex-rs/tui_app_server/BUILD.bazel` | 通过 `compile_data` 将帧文件包含在构建产物中 |
| `codex-rs/tui_app_server/Cargo.toml` | 项目依赖配置 |

## 依赖与外部交互

### 编译时依赖
- **Rust 编译器**：使用 `include_str!` 宏将文件内容嵌入二进制
- **Bazel/Cargo**：构建系统确保文件在编译时可用

### 运行时依赖
- **ratatui**：用于在终端中渲染文本帧
- **crossterm**：处理终端尺寸变化和键盘事件（Ctrl+. 切换变体）
- **tokio**：异步运行时，用于帧调度任务

### 与其他变体的关系
本文件属于 `shapes` 变体，与其他 9 个变体共同构成完整的动画集合：
- `default`：默认 ASCII 艺术（使用标点符号）
- `codex`：Codex 品牌风格（使用字母字符）
- `openai`：OpenAI 品牌风格
- `blocks`：方块字符（▒、▓、█、░ 等）
- `dots`：点状图案
- `hash`：哈希/井号图案
- `hbars`：水平条形图案
- `vbars`：垂直条形图案
- `shapes`：**本文件所属变体**，几何形状混合
- `slug`： slug 风格图案

## 风险、边界与改进建议

### 潜在风险
1. **终端兼容性**：
   - 使用的 Unicode 几何形状字符在某些终端字体中可能显示为方框或空白
   - 建议：测试在常见终端（iTerm2、Windows Terminal、GNOME Terminal）中的显示效果

2. **文件完整性**：
   - 文件在编译时被嵌入，运行时修改不会影响已编译的二进制文件
   - 删除或损坏文件会导致编译失败

3. **尺寸约束**：
   - 固定 17×40 的尺寸可能不适合极小终端窗口
   - 建议：考虑添加响应式尺寸调整

### 边界条件
- **最小显示尺寸**：终端必须至少 37 行高、60 列宽才能显示动画
- **帧率限制**：动画刷新率被限制在最高 120 FPS，避免过度消耗 CPU
- **内存占用**：36 帧 × 约 1200 字节 ≈ 43KB 静态内存占用

### 改进建议
1. **动态主题**：
   - 当前帧内容是静态的，可考虑支持用户自定义帧文件路径
   - 允许从配置文件加载自定义动画

2. **可访问性**：
   - 添加 `--no-animation` 启动参数，完全禁用动画以减少视觉干扰
   - 支持高对比度模式

3. **性能优化**：
   - 对于远程 SSH 会话，可自动检测并降级为更简单的动画变体
   - 考虑使用更高效的差分渲染（仅更新变化的字符）

4. **文档完善**：
   - 添加帧设计规范文档，说明如何创建新的动画变体
   - 提供帧预览工具，方便设计师验证动画效果
