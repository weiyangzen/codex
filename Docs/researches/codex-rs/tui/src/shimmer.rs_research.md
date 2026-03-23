# shimmer.rs 研究文档

## 场景与职责

`shimmer.rs` 是 Codex TUI 的文本动画效果模块，实现了一种"闪烁"（shimmer）视觉效果。该效果通过随时间变化的颜色渐变，在文本上产生一种流动的光带动画，用于吸引用户注意力或表示正在进行的状态。

该模块主要用于：
- 登录流程中的提示文本动画
- 执行单元格的加载状态指示
- 状态指示器的工作状态显示

## 功能点目的

### 1. 流动光带动画
- 在文本上产生从左到右流动的光带效果
- 光带内字符颜色渐变，从基色到高亮色再回到基色
- 使用余弦函数实现平滑的亮度过渡

### 2. 终端颜色自适应
- 检测终端是否支持真彩色（24-bit RGB）
- 支持真彩色时使用 RGB 颜色插值
- 不支持时使用 ANSI 样式（Dim/Normal/Bold）降级

### 3. 时间同步动画
- 使用进程启动时间作为同步基准
- 确保跨组件动画一致性
- 2 秒一个完整周期

## 具体技术实现

### 核心算法

```rust
pub(crate) fn shimmer_spans(text: &str) -> Vec<Span<'static>> {
    let chars: Vec<char> = text.chars().collect();
    if chars.is_empty() {
        return Vec::new();
    }

    // 动画参数
    let padding = 10usize;                    // 光带前后填充
    let period = chars.len() + padding * 2;   // 总周期长度
    let sweep_seconds = 2.0f32;               // 动画周期（秒）
    
    // 计算当前光带位置（基于进程启动时间）
    let pos_f = (elapsed_since_start().as_secs_f32() % sweep_seconds) 
                / sweep_seconds * (period as f32);
    let pos = pos_f as usize;
    
    let band_half_width = 5.0;                // 光带半宽
    let has_true_color = supports_color::on_cached(supports_color::Stream::Stdout)
        .map(|level| level.has_16m)
        .unwrap_or(false);

    // 颜色定义
    let base_color = default_fg().unwrap_or((128, 128, 128));
    let highlight_color = default_bg().unwrap_or((255, 255, 255));

    // 为每个字符计算样式
    chars.iter().enumerate().map(|(i, ch)| {
        let i_pos = i as isize + padding as isize;
        let dist = (i_pos - pos as isize).abs() as f32;

        // 余弦衰减计算强度
        let t = if dist <= band_half_width {
            let x = std::f32::consts::PI * (dist / band_half_width);
            0.5 * (1.0 + x.cos())  // 余弦缓动，范围 [0, 1]
        } else {
            0.0
        };

        // 根据终端能力选择颜色模式
        let style = if has_true_color {
            let highlight = t.clamp(0.0, 1.0);
            let (r, g, b) = blend(highlight_color, base_color, highlight * 0.9);
            Style::default()
                .fg(Color::Rgb(r, g, b))
                .add_modifier(Modifier::BOLD)
        } else {
            color_for_level(t)  // ANSI 降级
        };

        Span::styled(ch.to_string(), style)
    }).collect()
}
```

### 颜色混合

```rust
// 线性颜色混合
pub(crate) fn blend(fg: (u8, u8, u8), bg: (u8, u8, u8), alpha: f32) -> (u8, u8, u8) {
    let r = (fg.0 as f32 * alpha + bg.0 as f32 * (1.0 - alpha)) as u8;
    let g = (fg.1 as f32 * alpha + bg.1 as f32 * (1.0 - alpha)) as u8;
    let b = (fg.2 as f32 * alpha + bg.2 as f32 * (1.0 - alpha)) as u8;
    (r, g, b)
}
```

### ANSI 降级

```rust
fn color_for_level(intensity: f32) -> Style {
    if intensity < 0.2 {
        Style::default().add_modifier(Modifier::DIM)      // 暗淡
    } else if intensity < 0.6 {
        Style::default()                                   // 正常
    } else {
        Style::default().add_modifier(Modifier::BOLD)      // 粗体
    }
}
```

### 时间同步

```rust
static PROCESS_START: OnceLock<Instant> = OnceLock::new();

fn elapsed_since_start() -> Duration {
    let start = PROCESS_START.get_or_init(Instant::now);
    start.elapsed()
}
```

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `shimmer_spans` | 21 | 核心函数：生成带闪烁效果的 Span 列表 |
| `blend` | 7 | RGB 颜色混合（来自 `color.rs`） |
| `color_for_level` | 71 | ANSI 降级样式选择 |
| `elapsed_since_start` | 16 | 获取进程启动后的经过时间 |

### 依赖模块

| 模块 | 路径 | 用途 |
|------|------|------|
| `blend` | `crate::color` | RGB 颜色混合算法 |
| `default_bg`/`default_fg` | `crate::terminal_palette` | 获取终端默认颜色 |
| `supports_color` | 外部 crate | 检测终端颜色支持 |
| `ratatui::style` | 外部 crate | 样式定义 |

### 调用方

| 文件 | 代码位置 | 用途 |
|------|----------|------|
| `status_indicator_widget.rs` | 255 | 状态指示器头部动画 |
| `onboarding/auth.rs` | 401 | 登录提示动画 |
| `onboarding/auth/headless_chatgpt_login.rs` | 150 | 无头登录横幅动画 |
| `exec_cell/render.rs` | 191 | 执行单元加载点动画 |

## 依赖与外部交互

### 颜色系统

```
shimmer_spans
    ↓ 调用
default_fg() / default_bg() (terminal_palette.rs)
    ↓ 调用
best_color() (terminal_palette.rs)
    ↓ 调用
supports_color::on_cached() (外部 crate)
```

### 渲染流程

```rust
// 使用示例（来自 status_indicator_widget.rs）
let mut spans = vec![/* 其他 spans */];
spans.extend(shimmer_spans(&self.header));  // 添加闪烁效果
let line = Line::from(spans);
frame.render_widget(line, area);
```

### 视觉效果

```
时间 →

T0:   Hello World  (全部基色)
T0.5: He██lo World  (光带在 "ll" 位置)
T1:   Hell██ World  (光带在 "o " 位置)
T1.5: Hello W██rld  (光带在 "Wo" 位置)
T2:   Hello World  (回到初始状态，循环)

██ = 高亮字符（颜色渐变）
```

## 风险、边界与改进建议

### 风险分析

1. **CPU 开销**
   - 每帧都重新计算所有字符的颜色
   - 长文本时计算量较大
   - 当前实现对于短文本（<100 字符）性能可接受

2. **可访问性问题**
   - 动画可能分散注意力
   - 颜色变化可能影响色盲用户
   - 应提供禁用动画的选项

3. **终端兼容性**
   - 依赖 `supports_color` 检测，可能不完全准确
   - 某些终端可能对 RGB 颜色支持不佳

### 边界情况处理

| 场景 | 处理方式 |
|------|----------|
| 空字符串 | 返回空 Vec |
| 终端无颜色支持 | 使用 ANSI 降级 |
| 无法获取默认颜色 | 使用灰色 (128, 128, 128) 和白色 (255, 255, 255) 作为后备 |

### 改进建议

1. **性能优化**
   - 缓存颜色计算结果（如果文本和终端大小不变）
   - 使用查找表加速余弦计算
   - 限制最大文本长度，避免超长文本导致卡顿

2. **可访问性**
   - 添加 `NO_ANIMATION` 环境变量支持
   - 遵循 `prefers-reduced-motion` 媒体查询（终端模拟器支持时）
   - 提供静态高亮替代方案

3. **视觉效果**
   - 支持自定义动画速度
   - 支持自定义光带宽度
   - 支持双向流动（左到右和右到左）

4. **代码改进**
   - 考虑将 `blend` 函数内联或预计算
   - 添加单元测试验证颜色计算
   - 考虑使用 `ratatui::style::Color::from_u32` 优化 RGB 创建

5. **功能扩展**
   - 支持多光带效果
   - 支持彩虹色渐变
   - 支持脉冲效果（整体亮度变化）

### 与其他模块的关系

该模块是纯粹的视觉效果模块，与业务逻辑完全解耦。它仅依赖于：
- `color.rs`: 颜色混合算法
- `terminal_palette.rs`: 终端颜色查询

这种设计使得该模块易于测试和替换，也便于在其他项目中复用。
