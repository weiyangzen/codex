# frame_30.txt 研究文档

## 场景与职责

`frame_30.txt` 是 Codex TUI 欢迎界面 ASCII 动画序列的第 30 帧。该帧展示 Codex 标志在展开过程中的一个过渡形态，位于 36 帧动画循环的后段。

## 功能点目的

1. **接近初始**：作为第 30 帧，标志非常接近初始展开状态
2. **循环尾声**：距离完成循环还有 6 帧
3. **准备衔接**：为无缝循环回到 frame_1 做准备

## 具体技术实现

### 文件规格
- **帧序号**：30 / 36
- **循环位置**：83.3%（30/36 = 5/6）
- **显示时间**：动画开始后约 2320ms
- **文件大小**：662 字节

### 5/6 里程碑
```
30/36 = 5/6 ≈ 83.3%
已用时间: 30 × 80ms = 2400ms
剩余时间: 6 × 80ms = 480ms
```

### 与 frame_6 的关系
```
frame_6:  16.7% (6/36)   - 收缩早期
frame_30: 83.3% (30/36)  - 展开晚期（本帧）

理论上应形成对称
```

### 代码集成
```rust
// AsciiAnimation::current_frame
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let tick_ms = self.frame_tick.as_millis();
    let elapsed_ms = self.start.elapsed().as_millis();
    
    if tick_ms == 0 {
        return frames[0];
    }
    
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    // idx = (2320 / 80) % 36 = 29 % 36 = 29
    frames[idx]  // FRAMES_CODEX[29] = frame_30.txt
}
```

## 关键代码路径与文件引用

### 文件链
```
frame_30.txt
  → include_str! → FRAMES_CODEX[29]
    → AsciiAnimation::current_frame()
      → WelcomeWidget::render_ref()
        → 终端显示
```

### 相关常量
- `FRAME_TICK_DEFAULT = Duration::from_millis(80)`
- `MIN_ANIMATION_HEIGHT = 37`
- `MIN_ANIMATION_WIDTH = 60`

## 依赖与外部交互

### 编译时
- 通过 `include_str!` 嵌入
- 编译时检查文件存在

### 运行时
- 通过 `&'static str` 访问
- 由 `FrameScheduler` 控制显示

## 风险、边界与改进建议

### 边界条件
- **时间边界**：在 83.3% 位置显示
- **对称边界**：应与 frame_6 形成视觉对称

### 改进建议
1. **对称验证**：验证 frame_6 与 frame_30 的对称性
2. **循环平滑**：确保 frame_36 到 frame_1 无缝衔接
3. **用户控制**：允许用户单步浏览帧
