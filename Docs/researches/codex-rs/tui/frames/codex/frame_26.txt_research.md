# frame_26.txt 研究文档

## 场景与职责

`frame_26.txt` 是 Codex TUI 欢迎界面 ASCII 动画序列的第 26 帧。该帧展示 Codex 标志在展开过程中的一个过渡形态，位于 36 帧动画循环的后段。

## 功能点目的

1. **后段推进**：作为第 26 帧，标志继续向初始状态展开
2. **接近完成**：距离完成循环还有 10 帧
3. **视觉恢复**：标志形态接近初始展开状态

## 具体技术实现

### 文件规格
- **帧序号**：26 / 36
- **循环位置**：72.2%（26/36）
- **显示时间**：动画开始后约 2000ms（2 秒）
- **文件大小**：662 字节

### 时间里程碑
```
2000ms = 2秒
本帧在 2 秒时刻显示
剩余时间: 880ms 完成循环
```

### 帧选择算法
```rust
impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let tick_ms = self.frame_tick.as_millis();  // 80
        let elapsed_ms = self.start.elapsed().as_millis();
        
        if tick_ms == 0 {
            return frames[0];
        }
        
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        // idx = (2000 / 80) % 36 = 25 % 36 = 25
        // 返回 frames[25] = frame_26.txt
        frames[idx]
    }
}
```

## 关键代码路径与文件引用

### 文件引用
```
frame_26.txt
  → include_str! → FRAMES_CODEX[25]
    → AsciiAnimation::frames() → &FRAMES_CODEX
      → current_frame() → 返回 &str
```

### 相关常量
- `FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80)`
- `MIN_ANIMATION_HEIGHT: u16 = 37`
- `MIN_ANIMATION_WIDTH: u16 = 60`

## 依赖与外部交互

### 编译时
- 文件通过 `include_str!` 嵌入 `.rodata` 段
- 编译时检查文件存在性

### 运行时
- 通过 `&'static str` 引用访问，零拷贝
- 由 `FrameScheduler` 控制显示时机

## 风险、边界与改进建议

### 边界条件
- **时间边界**：在 2 秒时刻显示
- **循环边界**：距离循环结束还有约 0.88 秒

### 改进建议
1. **时间标记**：在特定时间（如 2 秒）显示特殊效果
2. **循环计数**：显示已完成的循环次数
3. **交互提示**：在动画上叠加操作提示
