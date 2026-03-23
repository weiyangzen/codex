# shapes/frame_6.txt 研究文档

## 场景与职责

`shapes/frame_6.txt` 是 Codex TUI 应用程序服务器的 ASCII 艺术动画帧文件，属于 `shapes`（形状）动画变体的第 6 帧。在 36 帧动画循环中，它在 400-479ms 时间窗口显示。

**使用场景：**
- TUI 欢迎界面的持续动画播放
- shapes 变体 36 帧序列的第 6 帧

## 功能点目的

1. **动画过渡**：从 frame_5 的高密度中心状态向更分散的状态过渡
2. **视觉节奏**：创造"扩张-收缩"的呼吸节奏感
3. **持续反馈**：保持用户在等待期间有视觉内容可观看

## 具体技术实现

### 帧内容特征
```
帧 6 特征分析：
- 图案演变：中心密度开始降低，形状向外扩散
- 过渡特征：从"峰值"向"释放"状态转变
- 形状分布：边缘区域开始出现更多形状
```

### 动画时序计算
```rust
// 本帧显示时间窗口计算
let frame_idx = 5; // 0-based index for frame_6
let start_ms = frame_idx * 80;  // 400ms
let end_ms = (frame_idx + 1) * 80;  // 480ms
// 显示窗口：400-479ms
```

## 关键代码路径与文件引用

### 核心数据结构
```rust
// frames.rs
pub(crate) const FRAMES_SHAPES: [&str; 36] = [
    include_str!("../frames/shapes/frame_1.txt"),  // [0]
    // ...
    include_str!("../frames/shapes/frame_6.txt"),  // [5] - 本文件
    // ...
    include_str!("../frames/shapes/frame_36.txt"), // [35]
];
```

### 渲染流程
```rust
// ascii_animation.rs
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let elapsed_ms = self.start.elapsed().as_millis();
    let tick_ms = self.frame_tick.as_millis();  // 80ms
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    // 当 idx == 5 时返回 frame_6.txt 内容
    frames[idx]
}
```

## 依赖与外部交互

### 序列位置
```
frame_4 (峰值) → frame_5 (峰值保持) → frame_6 (开始扩散) → frame_7 (继续扩散)
```

### 变体生态系统
本文件是 10 个动画变体之一，每个变体包含 36 帧：
- 总帧数：10 变体 × 36 帧 = 360 帧文件
- 总大小：约 360 × 1100 字节 ≈ 396KB 静态数据

## 风险、边界与改进建议

### 文件一致性风险
- **风险**：如果本文件的行数或列数与其他帧不一致，可能导致渲染错位
- **检查**：所有 shapes 帧应为 17 行，每行约 40 个字符
- **验证**：建议添加 CI 测试检查帧尺寸一致性

### 改进建议
1. **帧生成工具**：提供工具从视频/GIF 自动生成 ASCII 帧序列
2. **实时预览**：开发 Web 工具预览所有变体的动画效果
3. **用户贡献**：建立社区贡献新变体的流程
