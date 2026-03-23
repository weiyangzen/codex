# frame_21.txt 研究文档

## 场景与职责

`frame_21.txt` 是 Codex TUI 中 `dots` 动画系列的第21帧（索引20），在36帧动画循环中代表约58.3%的时间点。该帧展示点状图案接近收缩完成的状态。

## 功能点目的

- **收缩末期**：图案高度集中在中心，接近最小状态
- **循环后期**：进入36帧循环的最后三分之一
- **过渡准备**：为下一轮的扩张做准备

## 具体技术实现

### 帧特征
- 中心区域点密度最高
- 边缘区域基本清空
- 呈现收缩即将完成的视觉状态

### 技术细节

**时间位置**：
```
开始时间：1600ms
结束时间：1680ms
在36帧循环中的位置：58.3%
```

**帧访问代码**：
```rust
impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        if frames.is_empty() { return ""; }
        
        let tick_ms = self.frame_tick.as_millis();
        let elapsed_ms = self.start.elapsed().as_millis();
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        
        frames[idx]  // idx = 20 时返回 frame_21.txt
    }
}
```

## 关键代码路径与文件引用

### 核心文件
1. `codex-rs/tui/src/frames.rs` - 帧定义（第51行）
2. `codex-rs/tui/src/ascii_animation.rs` - 动画逻辑
3. `codex-rs/tui/src/status_indicator_widget.rs` - 状态指示器

### 相邻帧
- `frame_20.txt` - 前一帧（收缩后期）
- `frame_22.txt` - 后一帧（收缩完成/开始扩张）

## 依赖与外部交互

### 运行时依赖
- `std::time::Duration` 和 `std::time::Instant`
- `ratatui` 终端渲染库
- `unicode-width` 字符宽度计算

### 配置选项
- 动画可以通过配置禁用
- 支持10种不同的动画变体

## 风险、边界与改进建议

### 技术考虑
1. **帧率稳定性**：确保80ms间隔的一致性
2. **内存使用**：36帧全部加载在内存中

### 改进方向
1. **延迟加载**：考虑按需加载帧数据
2. **压缩存储**：使用更紧凑的存储格式
3. **程序化生成**：使用算法生成收缩效果
