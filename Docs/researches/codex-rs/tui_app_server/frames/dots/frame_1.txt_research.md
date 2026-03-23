# frame_1.txt 研究文档

## 场景与职责

`frame_1.txt` 是 Codex TUI 应用服务器的 ASCII 艺术动画帧文件，属于 `dots` 动画变体系列中的第一帧。该文件包含一个 17 行的 ASCII 艺术图案，使用 Unicode 字符（○, ●, ◉, ·）构成一个抽象的动态点阵图案，用于在 TUI 欢迎界面和状态指示器中提供视觉反馈。

## 功能点目的

1. **视觉动画效果**：作为 36 帧循环动画的第一帧，提供流畅的视觉过渡效果
2. **品牌识别**：dots 变体使用点状图案，营造科技感和动态感
3. **用户体验**：在长时间操作（如认证、加载）期间提供视觉反馈，减少用户焦虑
4. **终端兼容性**：使用标准 Unicode 字符，确保在大多数终端中正确显示

## 具体技术实现

### 文件格式
- **尺寸**：17 行 × 40 列（固定尺寸）
- **字符集**：
  - `○` (U+25CB)：白色圆圈，用于背景/空白区域
  - `●` (U+25CF)：黑色圆圈，用于主要图案
  - `◉` (U+25C9)：靶心圆圈，用于高亮/焦点区域
  - `·` (U+00B7)：中间点，用于过渡/渐变效果

### 图案结构
```
第 1 行：空白边距
第 2 行：顶部装饰图案 "○◉○◉○●●○○●●○"
第 3-16 行：主体动态点阵图案，呈现不规则分布
第 17 行：空白边距
```

### 动画系统集成

该文件通过 `frames.rs` 模块集成到应用中：

```rust
// frames.rs
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            // ... frame_2 到 frame_36
        ]
    };
}

pub(crate) const FRAMES_DOTS: [&str; 36] = frames_for!("dots");
```

### 动画播放机制

1. **帧率控制**：默认 80ms 每帧 (`FRAME_TICK_DEFAULT`)
2. **循环播放**：36 帧循环，通过时间计算当前帧索引
3. **随机变体切换**：用户可通过 `Ctrl+.` 切换不同动画变体

```rust
// ascii_animation.rs
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let tick_ms = self.frame_tick.as_millis();
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]
}
```

## 关键代码路径与文件引用

### 核心文件依赖

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/tui_app_server/src/frames.rs` | 定义 `FRAMES_DOTS` 常量，编译时嵌入帧数据 |
| `codex-rs/tui_app_server/src/ascii_animation.rs` | 动画控制器，管理帧切换和定时 |
| `codex-rs/tui_app_server/src/onboarding/welcome.rs` | 欢迎界面，使用动画作为背景 |
| `codex-rs/tui_app_server/src/status_indicator_widget.rs` | 状态指示器，显示工作进度 |

### 使用场景

1. **欢迎界面** (`welcome.rs`):
   ```rust
   let frame = self.animation.current_frame();
   lines.extend(frame.lines().map(Into::into));
   ```

2. **状态指示器** (`status_indicator_widget.rs`):
   ```rust
   spans.push(spinner(Some(self.last_resume_at), self.animations_enabled));
   spans.extend(shimmer_spans(&self.header));
   ```

## 依赖与外部交互

### 编译时依赖
- `include_str!` 宏在编译时将文件内容嵌入二进制
- 文件必须存在于 `frames/dots/` 目录中

### 运行时依赖
- `FrameRequester`：调度帧刷新（约 32ms 间隔）
- `ratatui`：终端渲染库
- `crossterm`：终端控制

### 相关变体
`dots` 是 10 个动画变体之一：
- `default`, `codex`, `openai`, `blocks`, `dots`, `hash`, `hbars`, `vbars`, `shapes`, `slug`

## 风险、边界与改进建议

### 潜在风险

1. **终端兼容性**：
   - 某些老旧终端可能不支持 Unicode 字符
   - 字符宽度计算可能因终端字体而异
   - **缓解**：代码中已检查 `animations_enabled` 标志，可禁用动画

2. **文件缺失**：
   - 如果文件被删除，编译将失败（`include_str!` 错误）
   - **缓解**：文件是版本控制的一部分，CI 会验证完整性

3. **性能影响**：
   - 频繁帧刷新（32ms）可能增加 CPU 使用
   - **缓解**：使用 `FrameRateLimiter` 限制最大帧率（120 FPS）

### 边界条件

| 条件 | 行为 |
|------|------|
| 终端高度 < 37 | 跳过动画显示（`MIN_ANIMATION_HEIGHT`） |
| 终端宽度 < 60 | 跳过动画显示（`MIN_ANIMATION_WIDTH`） |
| `animations_enabled = false` | 显示静态点 "•" 代替动画 |
| 不支持真彩色 | 使用 `color_for_level` 降级显示 |

### 改进建议

1. **动态尺寸**：
   - 当前固定 40×17 尺寸，可考虑响应式缩放
   - 实现终端尺寸自适应的动画版本

2. **性能优化**：
   - 考虑使用更高效的帧差异检测
   - 在后台时降低刷新率

3. **可访问性**：
   - 添加 `NO_ANIMATION` 环境变量支持
   - 为高对比度终端提供替代图案

4. **内容扩展**：
   - 当前 36 帧约 2.88 秒循环，可考虑更长的无缝循环
   - 添加主题感知颜色（当前为灰度）

### 维护注意事项

- 修改帧文件后需重新编译（编译时嵌入）
- 保持所有 36 帧尺寸一致，避免渲染错位
- 新增变体需在 `frames.rs` 和 `ALL_VARIANTS` 中注册
