# frame_25.txt 研究文档

## 场景与职责

`frame_25.txt` 是 Codex TUI 欢迎界面 ASCII 动画序列的第 25 帧。该帧展示 Codex 标志在展开过程中的一个过渡形态，位于 36 帧动画循环的后 1/3 段。

## 功能点目的

1. **后段展开**：作为第 25 帧，标志接近完全展开
2. **循环尾声**：距离完成循环还有 11 帧
3. **接近初始**：形态接近 frame_1 的初始状态

## 具体技术实现

### 文件规格
- **帧序号**：25 / 36
- **循环位置**：69.4%（25/36）
- **显示时间**：动画开始后约 1920ms
- **文件大小**：662 字节

### 接近循环结束
```
帧 25:  69.4% (1920ms) ← 本帧
帧 30:  83.3% (2320ms)
帧 35:  97.2% (2720ms)
帧 36: 100.0% (2800ms)
帧 1:   0.0%  (2880ms) ← 新一轮开始
```

### 技术实现
```rust
// 帧率限制器（frame_rate_limiter.rs）
const MAX_FPS: u32 = 120;
pub(crate) const MIN_FRAME_INTERVAL: Duration = 
    Duration::from_micros(1_000_000 / MAX_FPS as u64);  // ~8.33ms

// FrameScheduler 使用此限制器确保不超过 120 FPS
```

## 关键代码路径与文件引用

### 核心路径
- **文件**：`codex-rs/tui/frames/codex/frame_25.txt`
- **数组**：`FRAMES_CODEX[24]`
- **宏**：`frames.rs:30`

### 渲染流程
```
FrameScheduler::run() [每 80ms]
  → draw_tx.send(())
    → TuiEvent::Draw
      → App 处理事件
        → 如果显示欢迎界面:
          → WelcomeWidget::render_ref()
            → AsciiAnimation::current_frame() → frame_25.txt
```

## 依赖与外部交互

### 内部依赖
- 依赖前半段帧完成收缩动画
- 为最后 11 帧的完成动画提供基础

### 外部配置
- 可通过环境变量或配置文件禁用动画
- 可通过快捷键切换变体

## 风险、边界与改进建议

### 风险点
1. **循环衔接**：frame_36 到 frame_1 的过渡必须平滑
2. **内存碎片**：频繁的小字符串分配可能导致碎片

### 改进建议
1. **无缝循环**：验证 frame_36 与 frame_1 的视觉连续性
2. **内存池**：使用字符串池管理帧数据
3. **用户反馈**：收集用户对动画效果的反馈
