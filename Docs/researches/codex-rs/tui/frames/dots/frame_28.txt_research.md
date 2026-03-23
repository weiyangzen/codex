# frame_28.txt 研究文档

## 场景与职责

`frame_28.txt` 是 Codex TUI 中 `dots` 动画系列的第28帧（索引27），在36帧动画循环中代表约77.8%的时间点。该帧展示新一轮收缩的进行状态。

## 功能点目的

- **收缩进行**：图案持续向中心收缩
- **循环后期**：进入36帧循环的最后阶段
- **接近重置**：距离循环结束还有8帧

## 具体技术实现

### 帧特征
- 点继续向中心聚集
- 边缘区域逐渐清空
- 收缩过程进行中

### 技术时序
```
循环进度：77.8%
显示时间：2160ms - 2240ms
剩余到循环结束：约640ms
```

### 代码路径

**在 ascii_animation.rs 中**：
```rust
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    if frames.is_empty() { return ""; }
    
    let tick_ms = self.frame_tick.as_millis();
    let elapsed_ms = self.start.elapsed().as_millis();
    
    if tick_ms == 0 {
        return frames[0];
    }
    
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]  // idx = 27 返回 frame_28.txt
}
```

## 关键代码路径与文件引用

### 渲染流程
```
Terminal::draw() → Widget::render() → 
AsciiAnimation::current_frame() → FRAMES_DOTS[27]
```

### 相关文件
- `frame_27.txt` - 前一帧
- `frame_29.txt` - 后一帧
- `frames.rs` - 帧定义

## 依赖与外部交互

### 运行时依赖
- `std::time::Duration` 和 `Instant`
- `ratatui` 渲染库
- Unicode宽度计算

### 配置选项
- 可通过设置禁用
- 支持10种动画变体

## 风险、边界与改进建议

### 技术风险
1. **帧跳过**：高负载下可能跳过某些帧
2. **定时精度**：系统定时器精度影响动画流畅度

### 改进方向
1. **时间补偿**：检测并补偿渲染延迟
2. **性能监控**：监控动画对系统性能的影响
3. **用户偏好**：允许用户调整动画参数
