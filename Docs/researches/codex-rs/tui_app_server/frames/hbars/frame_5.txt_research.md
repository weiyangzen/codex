# Frame 5 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 5 是 HBARS 动画序列的第五帧，标志着动画进入早期阶段的后半部分。此帧展现出更加成熟的波浪形态，条块分布达到一个局部平衡点，为中期阶段的高复杂度波形做准备。

在 36 帧循环中，Frame 5 代表了约 13.9% 的进度（5/36），是早期阶段的关键过渡帧。

## 功能点目的

1. **形态成熟**：展示更成熟的波浪形态
2. **局部平衡**：在分散与聚集之间达到视觉平衡
3. **中期铺垫**：为 Frame 6-12 的高复杂度波形做铺垫
4. **循环协调**：确保与 Frame 36 的循环衔接平滑

## 具体技术实现

### Unicode 字符集
使用完整的 Unicode 块元素字符集：
- `▁▂▃▄▅▆▇█` (U+2581-U+2588)

### 帧规格
- **行数**：17 行（包含首尾空行）
- **宽度**：约 40 字符
- **帧索引**：4（在 FRAMES_HBARS 数组中）
- **显示时序**：第 320-400ms

### 视觉特征
Frame 5 的特征：
- 顶部：波峰达到局部最高点
- 中部：波浪形态更加对称
- 底部：开始出现向下一帧过渡的迹象

## 关键代码路径与文件引用

### 宏展开
```rust
// codex-rs/tui_app_server/src/frames.rs
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_5.txt")),
            // ... 其他帧
        ]
    };
}
```

### 帧访问
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
fn frames(&self) -> &'static [&'static str] {
    self.variants[self.variant_idx]
}
// 访问 Frame 5: frames[4]
```

### 渲染检查
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
let show_animation = self.animations_enabled
    && layout_area.height >= MIN_ANIMATION_HEIGHT
    && layout_area.width >= MIN_ANIMATION_WIDTH;
```

## 依赖与外部交互

### 编译依赖
- `include_str!` 宏在编译时读取文件
- 文件路径相对于 `CARGO_MANIFEST_DIR`

### 运行时依赖
- `FrameRequester` 调度渲染
- `ratatui::Paragraph` 处理文本渲染

## 风险、边界与改进建议

### 风险与边界

1. **文件系统依赖**
   - 编译时依赖文件系统存在性
   - 文件缺失会导致编译失败

2. **编码问题**
   - 必须使用 UTF-8 编码
   - BOM 头可能导致渲染问题

3. **行尾一致性**
   - 必须使用 LF (\n) 行尾
   - CRLF 可能导致空行计算错误

### 改进建议

1. **编译时验证**
   - 添加 build.rs 验证帧文件格式

2. **备用帧**
   - 提供简化版帧用于低性能终端

3. **帧分析工具**
   - 开发工具分析帧间的视觉差异度

### 相关测试

```bash
# 运行欢迎屏幕测试
cargo test -p codex-tui-app-server welcome

# 验证帧文件格式
wc -l codex-rs/tui_app_server/frames/hbars/frame_5.txt
# 应输出 17
```
