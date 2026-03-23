# frame_13.txt 研究文档

## 场景与职责

`frame_13.txt` 是 Codex TUI 应用服务器启动动画的第 13 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中，此帧标志着动画进入后半周期的前奏阶段。

## 功能点目的

1. **周期过渡**：第 13 帧（约 36% 进度）标志着动画从前段向中段过渡
2. **视觉延续**：保持与前 12 帧的视觉连贯性，为后续帧铺垫
3. **时间标记**：在 80ms 帧间隔下，约在动画开始后 1.04 秒显示

## 具体技术实现

### 帧生命周期

```
动画时间线（假设从 t=0 开始）：
t=0ms      : frame_1.txt  (索引 0)
t=80ms     : frame_2.txt  (索引 1)
...
t=960ms    : frame_12.txt (索引 11)
t=1040ms   : frame_13.txt (索引 12) <-- 本文件
t=1120ms   : frame_14.txt (索引 13)
...
t=2800ms   : frame_36.txt (索引 35)
t=2880ms   : 循环回到 frame_1.txt
```

### 代码中的帧访问

```rust
// frames.rs - 编译时静态嵌入
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // ... 前 12 帧
    include_str!("../frames/default/frame_13.txt"),  // [12]
    // ... 后 23 帧
];

// ascii_animation.rs - 运行时帧选择
impl AsciiAnimation {
    fn frames(&self) -> &'static [&'static str] {
        self.variants[self.variant_idx]  // 返回 FRAMES_DEFAULT 或其他变体
    }
    
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let tick_ms = self.frame_tick.as_millis();  // 80ms
        let elapsed_ms = self.start.elapsed().as_millis();
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        frames[idx]  // 当 idx == 12 时返回 frame_13.txt 内容
    }
}
```

### 变体系统架构

```rust
// 所有可用变体
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,   // default/ 目录 - 包含 frame_13.txt
    &FRAMES_CODEX,     // codex/ 目录
    &FRAMES_OPENAI,    // openai/ 目录
    &FRAMES_BLOCKS,    // blocks/ 目录
    &FRAMES_DOTS,      // dots/ 目录
    &FRAMES_HASH,      // hash/ 目录
    &FRAMES_HBARS,     // hbars/ 目录
    &FRAMES_VBARS,     // vbars/ 目录
    &FRAMES_SHAPES,    // shapes/ 目录
    &FRAMES_SLUG,      // slug/ 目录
];
```

## 关键代码路径与文件引用

| 层级 | 文件 | 功能 |
|-----|------|------|
| 数据层 | `frames/default/frame_13.txt` | 原始 ASCII 艺术数据 |
| 嵌入层 | `src/frames.rs` | `include_str!` 编译时嵌入 |
| 逻辑层 | `src/ascii_animation.rs` | 帧索引计算与时间管理 |
| 表现层 | `src/onboarding/welcome.rs` | 渲染到终端界面 |
| 调度层 | `src/tui/frame_requester.rs` | 帧绘制调度 |

## 依赖与外部交互

### 与随机变体切换的交互

```rust
// 用户按 Ctrl + . 时触发
pub(crate) fn pick_random_variant(&mut self) -> bool {
    if self.variants.len() <= 1 {
        return false;
    }
    let mut rng = rand::rng();
    let mut next = self.variant_idx;
    while next == self.variant_idx {  // 确保切换到不同变体
        next = rng.random_range(0..self.variants.len());
    }
    self.variant_idx = next;  // 可能切换到其他变体的第 13 帧对应位置
    self.request_frame.schedule_frame();
    true
}
```

### 与 TUI 渲染系统的集成
- 使用 ratatui 的 `Paragraph` 组件渲染
- 通过 `FrameRequester` 与 tokio 异步运行时集成
- 受 `FrameRateLimiter` 约束，最高 120 FPS

## 风险、边界与改进建议

### 风险
1. **变体一致性**：所有变体必须有相同帧数（36），否则 `ALL_VARIANTS` 类型不兼容
2. **字符编码**：特殊 Unicode 字符在某些旧终端可能显示为乱码

### 边界情况
- **变体切换时机**：若在显示 frame_13.txt 时切换变体，可能立即跳转到新变体的对应位置帧
- **长时间运行**：动画基于 `Instant::now()`，长时间运行后可能累积浮点误差

### 改进建议
1. **变体独立帧数**：允许不同变体有不同帧数，提高灵活性
2. **帧预览工具**：开发 CLI 工具预览所有变体的动画效果
3. **性能监控**：添加指标监控动画渲染耗时
