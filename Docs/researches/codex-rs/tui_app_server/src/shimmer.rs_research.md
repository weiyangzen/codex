# shimmer.rs 研究文档

## 场景与职责

`shimmer.rs` 是 Codex TUI 应用服务器中的**微光动画效果模块**，负责生成文本的"微光"（shimmer）动画效果。这是一种视觉反馈效果，通过在文本上产生流动的光带动画来吸引用户注意力，常用于：

1. **加载状态指示** - 表示系统正在处理中
2. **品牌展示** - Codex CLI 启动时的品牌动画
3. **视觉反馈** - 重要信息的高亮展示

该模块实现了一个基于时间的正弦波动画效果，在支持真彩色的终端上显示渐变色彩，在不支持的终端上回退到亮度变化。

## 功能点目的

### 1. 时间同步动画
- 使用进程启动时间作为同步基准
- 所有微光效果在进程内保持同步
- 2秒一个完整周期

### 2. 真彩色支持
- 检测终端是否支持 24-bit 真彩色 (16M colors)
- 支持时：使用 RGB 渐变色彩
- 不支持时：回退到 ANSI 样式（dim/normal/bold）

### 3. 平滑光带效果
- 使用余弦函数创建平滑的光强分布
- 光带半宽为 5 个字符
- 边缘平滑过渡

## 具体技术实现

### 核心函数

```rust
/// 为给定文本生成微光动画的 Span 列表
pub(crate) fn shimmer_spans(text: &str) -> Vec<Span<'static>>
```

### 动画算法

#### 1. 时间计算
```rust
static PROCESS_START: OnceLock<Instant> = OnceLock::new();

fn elapsed_since_start() -> Duration {
    let start = PROCESS_START.get_or_init(Instant::now);
    start.elapsed()
}
```

#### 2. 位置计算
```rust
let padding = 10usize;                    // 前后填充，确保光带完全进出
let period = chars.len() + padding * 2;   // 总周期长度
let sweep_seconds = 2.0f32;               // 2秒一个周期

// 计算当前光带中心位置（0 到 period）
let pos_f = (elapsed_since_start().as_secs_f32() % sweep_seconds) 
            / sweep_seconds 
            * (period as f32);
let pos = pos_f as usize;
```

#### 3. 光强计算
```rust
let band_half_width = 5.0;

for (i, ch) in chars.iter().enumerate() {
    let i_pos = i as isize + padding as isize;
    let pos = pos as isize;
    let dist = (i_pos - pos).abs() as f32;

    // 使用余弦函数创建平滑过渡
    let t = if dist <= band_half_width {
        let x = std::f32::consts::PI * (dist / band_half_width);
        0.5 * (1.0 + x.cos())  // 余弦缓动，范围 0.0 ~ 1.0
    } else {
        0.0
    };
    
    // 应用样式...
}
```

#### 4. 颜色混合（真彩色）
```rust
let base_color = default_fg().unwrap_or((128, 128, 128));
let highlight_color = default_bg().unwrap_or((255, 255, 255));

let highlight = t.clamp(0.0, 1.0);
let (r, g, b) = blend(highlight_color, base_color, highlight * 0.9);

Style::default()
    .fg(Color::Rgb(r, g, b))
    .add_modifier(Modifier::BOLD)
```

#### 5. 回退样式（非真彩色）
```rust
fn color_for_level(intensity: f32) -> Style {
    if intensity < 0.2 {
        Style::default().add_modifier(Modifier::DIM)
    } else if intensity < 0.6 {
        Style::default()
    } else {
        Style::default().add_modifier(Modifier::BOLD)
    }
}
```

### 颜色混合函数

```rust
pub(crate) fn blend(fg: (u8, u8, u8), bg: (u8, u8, u8), alpha: f32) -> (u8, u8, u8) {
    let r = (fg.0 as f32 * alpha + bg.0 as f32 * (1.0 - alpha)) as u8;
    let g = (fg.1 as f32 * alpha + bg.1 as f32 * (1.0 - alpha)) as u8;
    let b = (fg.2 as f32 * alpha + bg.2 as f32 * (1.0 - alpha)) as u8;
    (r, g, b)
}
```

## 关键代码路径与文件引用

### 核心实现
- `shimmer_spans()` - 第 21-69 行
- `color_for_level()` - 第 71-80 行
- `elapsed_since_start()` - 第 16-19 行

### 依赖模块
- `crate::color::blend` - 颜色混合函数
- `crate::terminal_palette::default_bg` - 默认背景色
- `crate::terminal_palette::default_fg` - 默认前景色

### 调用方
通过 Grep 搜索发现以下文件使用了 `shimmer_spans`：
- `ascii_animation.rs` - ASCII 动画中的微光效果
- `status_indicator_widget.rs` - 状态指示器的微光动画

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `crate::color::blend` | RGB 颜色混合 |
| `crate::terminal_palette::default_bg` | 获取终端默认背景色 |
| `crate::terminal_palette::default_fg` | 获取终端默认前景色 |

### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `ratatui` | 终端 UI 渲染 |
| `ratatui::style::Color` | 颜色类型 |
| `ratatui::style::Style` | 样式类型 |
| `ratatui::style::Modifier` | 样式修饰符 |
| `ratatui::text::Span` | 文本片段类型 |
| `supports_color` | 检测终端颜色支持 |
| `std::sync::OnceLock` | 进程启动时间一次性初始化 |
| `std::time::Instant` | 时间测量 |

### 颜色支持检测
```rust
let has_true_color = supports_color::on_cached(supports_color::Stream::Stdout)
    .map(|level| level.has_16m)
    .unwrap_or(false);
```

## 风险、边界与改进建议

### 已知限制

1. **固定动画参数**
   - 周期固定为 2 秒
   - 光带半宽固定为 5 个字符
   - 填充固定为 10 个字符
   - 无法自定义动画参数

2. **颜色依赖**
   - 依赖终端报告的默认前景/背景色
   - 某些终端可能报告不准确的颜色

3. **性能考虑**
   - 每次渲染都重新计算所有字符的颜色
   - 长文本可能产生性能开销

### 边界情况

1. **空文本**
   ```rust
   if chars.is_empty() {
       return Vec::new();
   }
   ```

2. **单字符文本**
   - 光带效果可能不明显
   - 仍然会产生颜色变化

3. **终端颜色支持变化**
   - 使用 `supports_color::on_cached` 缓存结果
   - 运行时切换终端颜色支持不会被检测

4. **CI/无头环境**
   - 可能无法正确检测颜色支持
   - 回退到 ANSI 样式

### 改进建议

1. **可配置参数**
   ```rust
   pub struct ShimmerConfig {
       pub sweep_seconds: f32,
       pub band_half_width: f32,
       pub padding: usize,
       pub highlight_intensity: f32,
   }
   
   pub(crate) fn shimmer_spans_with_config(
       text: &str,
       config: &ShimmerConfig,
   ) -> Vec<Span<'static>>
   ```

2. **方向支持**
   - 当前仅支持从左到右的光带
   - 可添加从右到左、双向等效果

3. **多光带效果**
   - 支持多个光带同时存在
   - 创建更复杂的动画模式

4. **缓动函数选项**
   - 当前使用余弦缓动
   - 可添加线性、指数等其他缓动

5. **性能优化**
   ```rust
   // 缓存计算结果
   static CACHE: Mutex<HashMap<String, Vec<Span<'static>>>> = ...;
   
   // 或使用预计算的调色板
   const PALETTE_SIZE: usize = 256;
   static PALETTE: [(u8, u8, u8); PALETTE_SIZE] = ...;
   ```

6. **主题集成**
   - 从主题配置读取微光颜色
   - 支持自定义高亮/基础色

7. **无障碍支持**
   - 添加选项禁用动画（减少运动偏好）
   - 确保颜色对比度符合 WCAG 标准

### 代码质量

该模块代码简洁高效：
- 使用 `OnceLock` 实现线程安全的惰性初始化
- 数学计算清晰（余弦缓动）
- 正确处理空输入

建议改进：
- 添加单元测试验证颜色计算
- 添加文档说明动画参数的影响
- 考虑添加 `#[allow(clippy::disallowed_methods)]` 的说明注释

### 数学可视化

光强分布函数：
```
intensity
    1.0 |    ████
        |  ██    ██
    0.5 | █        █
        |█          █
    0.0 +------------→ distance
        -5    0    +5
        
    公式: 0.5 * (1 + cos(π * dist / half_width))
```

这个余弦函数确保：
- 距离为 0 时强度最大（1.0）
- 距离为 ±half_width 时强度为 0
- 过渡平滑自然
