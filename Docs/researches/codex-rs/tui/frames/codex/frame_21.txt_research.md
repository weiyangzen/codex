# frame_21.txt 研究文档

## 场景与职责

`frame_21.txt` 是 Codex TUI 欢迎界面 ASCII 动画序列的第 21 帧。该帧展示 Codex 标志在展开过程中的一个过渡形态，继续从最小状态向初始展开状态恢复。

## 功能点目的

1. **展开推进**：作为第 21 帧，标志继续向外展开
2. **循环后段**：位于 36 帧循环的后 40%
3. **接近完成**：距离完成一个完整循环还有 15 帧

## 具体技术实现

### 文件规格
- **帧序号**：21 / 36
- **循环进度**：58.3%（21/36）
- **显示时间**：动画开始后约 1600ms
- **文件大小**：662 字节

### 动画时间线
```
时间(ms)   1440    1520    1600    1680    1760
           |_______|_______|_______|_______|
帧         19      20      21      22      23
状态       开始展开  展开中   展开中   展开中   继续展开
```

### 代码集成
```rust
// AsciiAnimation 结构
pub(crate) struct AsciiAnimation {
    request_frame: FrameRequester,
    variants: &'static [&'static [&'static str]],
    variant_idx: usize,  // 当前使用 FRAMES_CODEX
    frame_tick: Duration,  // 80ms
    start: Instant,
}
```

## 关键代码路径与文件引用

### 核心路径
- **数据文件**：`codex-rs/tui/frames/codex/frame_21.txt`
- **数组位置**：`FRAMES_CODEX[20]`
- **宏定义**：`frames.rs:28`

### 渲染调用
```
App::run()
  → Tui::draw()
    → WelcomeWidget::render_ref()
      → animation.current_frame() → FRAMES_CODEX[20]
        → 渲染 frame_21.txt 内容
```

## 依赖与外部交互

### 编译时
- 通过 `include_str!` 嵌入
- 路径：`../frames/codex/frame_21.txt`

### 运行时
- 依赖 `FrameScheduler` 准确调度
- 依赖终端正确渲染

## 风险、边界与改进建议

### 风险点
1. **累积误差**：多帧累积的时序误差可能影响动画流畅性
2. **内存占用**：36 个静态字符串持续占用内存

### 改进建议
1. **懒加载**：首次显示时才加载帧数据
2. **共享存储**：与其他变体共享相同字符模式的帧
3. **性能分析**：分析动画对启动时间的影响
