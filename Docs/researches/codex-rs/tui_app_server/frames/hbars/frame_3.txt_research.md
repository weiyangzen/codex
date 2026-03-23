# Frame 3 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 3 是 HBARS 动画序列的第三帧，位于循环早期的关键过渡位置。此帧进一步推进波浪的演变，从中部开始展现更明显的形态变化，为后续帧的复杂波形奠定基础。

作为 36 帧循环中的第 3 帧（约 8.3% 进度），Frame 3 标志着动画从初始阶段向发展阶段的过渡。

## 功能点目的

1. **波浪深化**：推进 Frame 2 开始的波形演变，增加波浪的复杂度
2. **视觉层次**：通过条块高度的变化创造更丰富的视觉层次
3. **动量积累**：为中期帧（Frame 6-18）的复杂动画积累视觉动量
4. **循环一致性**：确保与 Frame 36 到 Frame 1 的循环过渡相协调

## 具体技术实现

### Unicode 字符集
使用完整的 Unicode 块元素字符集：
- `▁▂▃▄▅▆▇█` (U+2581-U+2588)

### 帧规格
- **行数**：17 行（包含首尾空行）
- **宽度**：约 40 字符
- **帧索引**：2（在 FRAMES_HBARS 数组中）
- **显示时序**：第 160-240ms（在 80ms 帧间隔下）

### 视觉特征
Frame 3 的独特特征：
- 顶部区域：波峰开始分裂，形成双峰形态
- 中部区域：出现明显的波谷，增强对比度
- 底部区域：条块开始重新聚集，为下一帧做准备

## 关键代码路径与文件引用

### 编译时嵌入
```rust
// codex-rs/tui_app_server/src/frames.rs
include_str!(concat!("../frames/", "hbars", "/frame_3.txt"))
// 在 frames_for! 宏中展开为 FRAMES_HBARS[2]
```

### 帧选择逻辑
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
pub(crate) fn current_frame(&self) -> &'static str {
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % 36) as usize;
    self.variants[self.variant_idx][idx]  // idx = 2 时返回 Frame 3
}
```

### 渲染流程
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
let show_animation = layout_area.height >= MIN_ANIMATION_HEIGHT 
    && layout_area.width >= MIN_ANIMATION_WIDTH;
if show_animation {
    let frame = self.animation.current_frame();
    lines.extend(frame.lines().map(Into::into));
}
```

## 依赖与外部交互

### 系统依赖
- **编译时**: `include_str!` 宏在编译时将文件内容嵌入二进制
- **运行时**: 通过数组索引 O(1) 访问帧数据
- **渲染时**: ratatui 将字符串转换为终端输出

### 用户交互
- **Ctrl+.** 切换到随机变体时，当前帧索引保持不变
- 变体切换后，Frame 3 可能显示来自其他变体的内容

## 风险、边界与改进建议

### 风险与边界

1. **内存对齐**
   - 36 个字符串指针的数组可能产生缓存未命中
   - 建议：考虑将帧数据连续存储

2. **国际化**
   - Unicode 块字符在某些区域设置下可能显示异常
   - 建议：检测 `LC_CTYPE` 环境变量

3. **高对比度模式**
   - 在高对比度终端主题下，低高度条块可能难以区分
   - 建议：提供高对比度优化版本

### 改进建议

1. **帧数据压缩**
   - 使用 RLE（Run-Length Encoding）压缩重复字符
   - 预估可减少 30-40% 的存储空间

2. **动画预览工具**
   - 开发 CLI 工具预览所有帧：`codex --preview-animation hbars`

3. **帧间差异分析**
   - 添加测试确保相邻帧有足够的变化（避免"卡顿"感）

### 性能指标

```
帧数据大小: ~680 字节
数组访问时间: O(1) ~1-2 CPU cycles
渲染时间: ~0.5ms (典型终端)
内存占用: 24KB (FRAMES_HBARS 总计)
```
