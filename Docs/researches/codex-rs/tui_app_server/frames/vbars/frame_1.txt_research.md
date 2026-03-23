# frame_1.txt 研究文档

## 场景与职责

`frame_1.txt` 是 Codex TUI 应用服务器欢迎界面动画的 ASCII 艺术帧文件，属于 **vbars**（垂直条形图）动画变体的第 1 帧。该文件在编译时通过 Rust 的 `include_str!` 宏嵌入到二进制中，用于在用户首次启动 Codex CLI 时展示动态视觉效果。

vbars 变体展示了一组垂直条形图案的动态变化，模拟音频波形或数据可视化效果，为用户提供视觉反馈，表明应用正在加载或处于活动状态。

## 功能点目的

1. **视觉反馈**：在 TUI 初始化期间提供动态视觉指示器
2. **品牌展示**：通过独特的 ASCII 艺术风格展示 OpenAI Codex 的品牌个性
3. **用户参与**：通过 `Ctrl+.` 快捷键支持用户在 10 种动画变体之间切换
4. **响应式设计**：在终端尺寸不足（小于 60x37）时自动隐藏动画

## 具体技术实现

### 文件规格
- **尺寸**：17 行 x 40 列（含边框空白）
- **字符集**：Unicode 方块元素字符（U+2588-U+259F 范围）
- **文件大小**：1208 字节
- **帧率**：80ms 每帧（12.5 FPS）

### 使用的 Unicode 字符
| 字符 | Unicode | 描述 |
|------|---------|------|
| █ | U+2588 | 全块 |
| ▉ | U+2589 | 左七分之一块 |
| ▊ | U+258A | 左八分之七块 |
| ▋ | U+258B | 左五分之三块 |
| ▌ | U+258C | 左二分之一块 |
| ▍ | U+258D | 左五分之二块 |
| ▎ | U+258E | 左四分之一块 |
| ▏ | U+258F | 左八分之一块 |

### 动画系统集成

```rust
// 在 frames.rs 中的编译时嵌入
pub(crate) const FRAMES_VBARS: [&str; 36] = frames_for!("vbars");

// 在 ascii_animation.rs 中的运行时调度
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]  // 返回如 frame_1.txt 的内容
}
```

### 渲染流程
1. `WelcomeWidget` 通过 `AsciiAnimation` 请求当前帧
2. `current_frame()` 基于 elapsed time 计算帧索引
3. 帧内容通过 `ratatui::Paragraph` 渲染到缓冲区
4. `FrameRequester` 调度下一帧（80ms 后）

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/frames/vbars/frame_1.txt` | 本文件，ASCII 艺术帧数据 |
| `codex-rs/tui_app_server/src/frames.rs` | 编译时帧数据嵌入，定义 `FRAMES_VBARS` |
| `codex-rs/tui_app_server/src/ascii_animation.rs` | 动画调度逻辑，帧率控制 |
| `codex-rs/tui_app_server/src/onboarding/welcome.rs` | 欢迎界面组件，消费动画帧 |
| `codex-rs/tui_app_server/src/tui/frame_requester.rs` | 帧渲染调度器 |

### 调用链
```
WelcomeWidget::render_ref
  └─> AsciiAnimation::current_frame()
      └─> FRAMES_VBARS[0] (frame_1.txt 内容)
  └─> AsciiAnimation::schedule_next_frame()
      └─> FrameRequester::schedule_frame_in(Duration::from_millis(80))
```

### Bazel 构建集成
```python
# BUILD.bazel
codex_rust_crate(
    name = "tui_app_server",
    compile_data = glob(include = ["**"], ...),
    # 包含 frames/vbars/*.txt 文件
)
```

## 依赖与外部交互

### 编译时依赖
- **Rust `include_str!` 宏**：将文本文件内容嵌入为静态字符串
- **`concat!` 宏**：构建帧文件路径

### 运行时依赖
- **ratatui**：终端 UI 渲染库
- **crossterm**：跨平台终端控制
- **tokio**：异步运行时（帧调度器）

### 变体切换
用户可通过 `Ctrl+.` 在以下变体间切换：
1. `default` - 默认 OpenAI 标志动画
2. `codex` - Codex 品牌动画
3. `openai` - OpenAI 螺旋动画
4. `blocks` - 方块图案
5. `dots` - 点阵图案
6. `hash` - 散列图案
7. `hbars` - 水平条形
8. `vbars` - 垂直条形（本文件所属）
9. `shapes` - 几何形状
10. `slug` - 鼻涕虫动画

## 风险、边界与改进建议

### 风险
1. **编码问题**：Unicode 方块字符在某些终端字体中可能显示为 tofu 或错位
2. **性能**：36 帧 x 10 变体 = 360 个静态字符串增加二进制大小约 400KB
3. **可访问性**：动画可能对光敏感用户造成不适

### 边界条件
- **最小显示尺寸**：60 列 x 37 行（`MIN_ANIMATION_WIDTH/HEIGHT`）
- **帧率上限**：120 FPS（`FrameRateLimiter` 限制）
- **空帧处理**：`current_frame()` 在空帧时返回空字符串

### 改进建议
1. **减少二进制大小**：考虑使用运行时从资源文件加载而非编译时嵌入
2. **无障碍支持**：添加配置选项禁用动画或减少运动
3. **主题适配**：支持根据终端主题调整动画颜色
4. **压缩优化**：使用 RLE 或类似算法压缩帧数据
5. **动态生成**：考虑使用程序生成波形而非预渲染帧

### 测试覆盖
- `ascii_animation.rs` 包含 `frame_tick_must_be_nonzero` 测试
- `welcome.rs` 包含动画渲染、尺寸断点、变体切换测试
