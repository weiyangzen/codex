# frame_36.txt 研究文档

## 场景与职责

`frame_36.txt` 是 Codex TUI 中 `dots` 动画系列的第36帧（索引35），也是最后一帧，在36帧动画循环中代表约100%的时间点（即将重置）。该帧是循环的终点，直接衔接到frame_1开始新循环。

## 功能点目的

- **循环最后一帧**：36帧循环的终点
- **循环衔接**：直接衔接到frame_1
- **视觉重置**：完成一个完整的"呼吸"周期

## 具体技术实现

### 帧特征
- 图案状态非常接近frame_1
- 确保与frame_1的平滑过渡
- 完成一个完整的动画循环

### 技术时序
```
循环位置：100%（即将重置）
显示时间：2800ms - 2880ms
下一帧：frame_1.txt（循环重置）
```

### 代码集成

**循环重置**：
```rust
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let tick_ms = self.frame_tick.as_millis();
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    // 当 idx == 35 时返回 frame_36.txt
    // 下一帧 idx 变为 0，返回 frame_1.txt（循环重置）
    frames[idx]
}
```

## 关键代码路径与文件引用

### 渲染调用链
```
App::render() → StatusIndicatorWidget::render() → 
AsciiAnimation::current_frame() → FRAMES_DOTS[35] (frame_36.txt)
→ 下一帧：FRAMES_DOTS[0] (frame_1.txt)
```

### 相关文件
- `frame_35.txt` - 前一帧
- `frame_1.txt` - 下一循环的第一帧
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

### 技术风险
1. **循环接缝**：frame_36到frame_1的过渡是最关键的接缝
2. **视觉跳跃**：如果两帧差异太大，会产生明显的跳跃感

### 改进建议
1. **接缝优化**：确保frame_36和frame_1的视觉一致性
2. **循环检测**：检测循环次数，在多次循环后加入变化
3. **性能监控**：监控长时间动画的性能影响
4. **用户控制**：允许用户禁用动画或选择静态指示器
