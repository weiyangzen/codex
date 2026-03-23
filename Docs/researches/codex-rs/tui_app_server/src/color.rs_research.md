# color.rs 研究文档

## 场景与职责

`color.rs` 是 Codex TUI 应用服务器的颜色处理工具模块，提供颜色空间转换、颜色混合和感知距离计算等功能。该模块是 TUI 主题系统和终端颜色适配的基础组件，支持根据终端背景自动调整 UI 元素的颜色。

该模块在以下场景中使用：
- 终端背景色检测和亮度判断
- 用户消息和计划提案的背景色混合
- 终端调色板的颜色量化（找到最接近的可显示颜色）
- Diff 渲染的颜色主题适配

## 功能点目的

### 1. 亮度检测 `is_light`
- 根据 RGB 值计算颜色的感知亮度（YIQ 亮度公式）
- 阈值设为 128.0，用于区分浅色和深色背景
- 公式：`Y = 0.299*R + 0.587*G + 0.114*B`

### 2. 颜色混合 `blend`
- 将前景色和背景色按 Alpha 通道混合
- 用于创建半透明的 UI 背景效果
- 公式：`result = fg * alpha + bg * (1 - alpha)`

### 3. 感知距离计算 `perceptual_distance`
- 计算两种颜色在人眼感知上的差异
- 使用 CIE76 公式（Lab 颜色空间的欧几里得距离）
- 转换路径：sRGB → Linear RGB → XYZ → Lab

## 具体技术实现

### 亮度检测

```rust
pub(crate) fn is_light(bg: (u8, u8, u8)) -> bool {
    let (r, g, b) = bg;
    let y = 0.299 * r as f32 + 0.587 * g as f32 + 0.114 * b as f32;
    y > 128.0
}
```

- 使用 YIQ 颜色空间的 Y 分量（亮度）
- 系数基于人眼对不同波长的敏感度（绿色最敏感，蓝色最不敏感）

### 颜色混合

```rust
pub(crate) fn blend(fg: (u8, u8, u8), bg: (u8, u8, u8), alpha: f32) -> (u8, u8, u8) {
    let r = (fg.0 as f32 * alpha + bg.0 as f32 * (1.0 - alpha)) as u8;
    let g = (fg.1 as f32 * alpha + bg.1 as f32 * (1.0 - alpha)) as u8;
    let b = (fg.2 as f32 * alpha + bg.2 as f32 * (1.0 - alpha)) as u8;
    (r, g, b)
}
```

- 简单的线性插值
- Alpha 值范围：0.0（完全背景色）到 1.0（完全前景色）

### 感知距离计算

```rust
pub(crate) fn perceptual_distance(a: (u8, u8, u8), b: (u8, u8, u8)) -> f32 {
    // 1. sRGB 转 Linear RGB
    // 2. Linear RGB 转 XYZ
    // 3. XYZ 转 Lab
    // 4. 计算欧几里得距离
}
```

#### sRGB 转 Linear RGB
```rust
fn srgb_to_linear(c: u8) -> f32 {
    let c = c as f32 / 255.0;
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}
```

#### RGB 转 XYZ（D65 白点）
```rust
fn rgb_to_xyz(r: u8, g: u8, b: u8) -> (f32, f32, f32) {
    let r = srgb_to_linear(r);
    let g = srgb_to_linear(g);
    let b = srgb_to_linear(b);

    let x = r * 0.4124 + g * 0.3576 + b * 0.1805;
    let y = r * 0.2126 + g * 0.7152 + b * 0.0722;
    let z = r * 0.0193 + g * 0.1192 + b * 0.9505;
    (x, y, z)
}
```

#### XYZ 转 Lab
```rust
fn xyz_to_lab(x: f32, y: f32, z: f32) -> (f32, f32, f32) {
    // D65 参考白点
    let xr = x / 0.95047;
    let yr = y / 1.00000;
    let zr = z / 1.08883;

    let fx = f(xr);
    let fy = f(yr);
    let fz = f(zr);

    let l = 116.0 * fy - 16.0;
    let a = 500.0 * (fx - fy);
    let b = 200.0 * (fy - fz);
    (l, a, b)
}

fn f(t: f32) -> f32 {
    if t > 0.008856 {
        t.powf(1.0 / 3.0)
    } else {
        7.787 * t + 16.0 / 116.0
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/color.rs`

### 调用方

| 文件 | 使用函数 | 用途 |
|------|----------|------|
| `style.rs` | `blend`, `is_light` | 用户消息和计划提案的背景色计算 |
| `tui.rs` | `is_light` | 终端背景检测 |
| `shimmer.rs` | `is_light` | 闪烁效果的颜色适配 |
| `diff_render.rs` | `is_light`, `perceptual_distance` | Diff 主题的颜色选择和量化 |
| `exec_cell/render.rs` | `is_light` | 执行单元格渲染的颜色适配 |
| `terminal_palette.rs` | `perceptual_distance` | 在 256 色终端中找到最接近的颜色 |
| `render/highlight.rs` | `is_light` | 语法高亮的颜色适配 |

### 模块声明
- 在 `lib.rs` 中声明为 `mod color;`

## 依赖与外部交互

### 外部依赖
- 无外部 crate 依赖，仅使用标准库

### 内部模块交互
- 被多个样式和渲染模块使用
- 是终端调色板系统的核心依赖

## 风险、边界与改进建议

### 风险点

1. **CIE76 的局限性**
   - CIE76 公式在蓝色区域存在感知不均匀性
   - 对于某些颜色组合，感知距离可能不准确
   - **评估**：当前用于终端颜色量化，精度足够
   - **可选改进**：考虑升级到 CIE94 或 CIEDE2000

2. **浮点精度**
   - 颜色转换涉及多次浮点运算
   - 在极端情况下可能有精度损失
   - **评估**：对当前用途影响可忽略

### 边界情况

1. **颜色值溢出**
   - `blend` 函数使用 `as u8` 转换，可能溢出
   - 当前实现假设输入 Alpha 值在有效范围内
   - **建议**：添加调试断言或饱和转换

2. **黑色和白色**
   - `is_light((0, 0, 0))` 返回 false（正确）
   - `is_light((255, 255, 255))` 返回 true（正确）
   - 阈值 128 是经验值，可能不适合所有场景

### 改进建议

1. **常量定义**
   - 当前魔法数字（如 0.299, 128.0）应定义为命名常量
   - 建议添加文档说明这些值的来源

2. **单元测试**
   - 当前无单元测试
   - 建议添加：
     - 已知颜色对的感知距离测试
     - 边界颜色（黑、白、灰）的亮度检测
     - 颜色混合的精度测试

3. **性能优化**
   - 考虑为常用操作添加查找表（LUT）
   - 例如：sRGB 到 Linear RGB 的转换表

4. **功能扩展**
   - 添加对比度计算函数（WCAG 标准）
   - 添加颜色插值函数（HSL/Lab 空间）
   - 支持更多颜色空间（HSL、HSV、LCH）

5. **文档完善**
   - 添加模块级文档说明颜色空间转换流程
   - 说明 CIE76 的适用场景和局限性
