# frame_31.txt 研究文档

## 场景与职责

`frame_31.txt` 是 Codex TUI 中 `dots` 动画系列的第31帧（索引30），在36帧动画循环中代表约86.1%的时间点。该帧展示新一轮收缩接近完成的状态。

## 功能点目的

- **收缩末期**：图案高度集中在中心，接近最小状态
- **循环接近结束**：距离36帧循环结束还有5帧
- **准备循环**：为回到frame_1开始新循环做准备

## 具体技术实现

### 帧特征
- 中心区域点密度最高
- 边缘几乎完全清空
- 呈现收缩即将完成的视觉状态

### 技术时序
```
循环位置：86.1%
显示时间：2400ms - 2480ms
剩余帧数：5帧（约400ms）
```

### 代码路径

**在 ascii_animation.rs 中**：
```rust
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let tick_ms = self.frame_tick.as_millis();
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]  // idx = 30 返回 frame_31.txt
}
```

## 关键代码路径与文件引用

### 渲染调用链
```
App::render() → StatusIndicatorWidget::render() → 
AsciiAnimation::current_frame() → FRAMES_DOTS[30] (frame_31.txt)
```

### 相关文件
- `frame_30.txt` - 前一帧
- `frame_32.txt` - 后一帧
- `frames.rs` - 帧定义

## 依赖与外部交互

### 系统集成
- 与TUI事件循环集成
- 通过 `FrameRequester` 调度渲染
- 使用 `ratatui` 渲染

### 配置和环境
- 受 `animations_enabled` 控制
- 依赖终端能力

## 风险、边界与改进建议

### 潜在问题
1. **循环接缝**：frame_36到frame_1的过渡需要平滑
2. **视觉重复**：固定循环可能产生单调感

### 改进建议
1. **过渡优化**：确保循环接缝的视觉平滑
2. **随机变化**：在多次循环后加入变化
3. **节能模式**：在电池供电时降低动画复杂度
