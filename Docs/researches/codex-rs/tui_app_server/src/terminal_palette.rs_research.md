# TerminalPalette 研究文档

## 场景与职责

`terminal_palette.rs` 是 Codex TUI 的终端颜色管理模块，负责：

1. **终端颜色能力检测**：检测终端支持的颜色级别（TrueColor/ANSI256/ANSI16）
2. **默认颜色查询**：查询终端的默认前景/背景色
3. **颜色量化**：将 RGB 颜色映射到终端支持的最佳颜色
4. **Xterm 256 色表**：提供标准的 Xterm 256 色定义

该模块位于 `codex-rs/tui_app_server/src/terminal_palette.rs`，是 TUI 渲染系统的颜色基础设施。

## 功能点目的

### 1. 颜色能力检测

检测终端支持的颜色级别：
- `TrueColor` (1600万色) - 现代终端标准
- `Ansi256` (256色) - Xterm 兼容
- `Ansi16` (16色) - 基础终端支持
- `Unknown` - 无法检测

### 2. 默认颜色查询

通过 crossterm 的 OSC 序列查询终端默认前景/背景色：
- 使用 `query_foreground_color()` 和 `query_background_color()`
- 结果缓存避免重复查询
- 支持重新查询（用于主题切换后）

### 3. 颜色量化

将任意 RGB 颜色映射到终端支持的最佳颜色：
- TrueColor 终端：直接使用 RGB
- ANSI256 终端：使用感知距离找到最接近的 Xterm 颜色
- ANSI16/Unknown：返回默认颜色

### 4. 调色板版本控制

跟踪默认颜色查询的版本号，用于缓存失效：
- 每次 `requery_default_colors()` 调用递增版本
- 缓存渲染器可检测版本变化并刷新

## 具体技术实现

### 颜色级别枚举

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StdoutColorLevel {
    TrueColor,
    Ansi256,
    Ansi16,
    Unknown,
}

pub fn stdout_color_level() -> StdoutColorLevel {
    match supports_color::on_cached(supports_color::Stream::Stdout) {
        Some(level) if level.has_16m => StdoutColorLevel::TrueColor,
        Some(level) if level.has_256 => StdoutColorLevel::Ansi256,
        Some(_) => StdoutColorLevel::Ansi16,
        None => StdoutColorLevel::Unknown,
    }
}
```

### 最佳颜色选择

```rust
pub fn best_color(target: (u8, u8, u8)) -> Color {
    let color_level = stdout_color_level();
    if color_level == StdoutColorLevel::TrueColor {
        rgb_color(target)
    } else if color_level == StdoutColorLevel::Ansi256
        && let Some((i, _)) = xterm_fixed_colors().min_by(|(_, a), (_, b)| {
            perceptual_distance(*a, target)
                .partial_cmp(&perceptual_distance(*b, target))
                .unwrap_or(std::cmp::Ordering::Equal)
        })
    {
        indexed_color(i as u8)
    } else {
        Color::default()
    }
}
```

### 平台特定的默认颜色查询

**Unix 实现：**
```rust
#[cfg(all(unix, not(test)))]
mod imp {
    use super::DefaultColors;
    use crossterm::style::query_background_color;
    use crossterm::style::query_foreground_color;
    
    struct Cache<T> {
        attempted: bool,
        value: Option<T>,
    }
    
    fn default_colors_cache() -> &'static Mutex<Cache<DefaultColors>> {
        static CACHE: OnceLock<Mutex<Cache<DefaultColors>>> = OnceLock::new();
        CACHE.get_or_init(|| Mutex::new(Cache::default()))
    }
    
    pub(super) fn default_colors() -> Option<DefaultColors> {
        let cache = default_colors_cache();
        let mut cache = cache.lock().ok()?;
        cache.get_or_init_with(|| query_default_colors().unwrap_or_default())
    }
}
```

**非 Unix/测试回退：**
```rust
#[cfg(not(all(unix, not(test))))]
mod imp {
    pub(super) fn default_colors() -> Option<DefaultColors> {
        None  // 无法查询，返回 None
    }
    
    pub(super) fn requery_default_colors() {}
}
```

### Xterm 256 色表

```rust
pub const XTERM_COLORS: [(u8, u8, u8); 256] = [
    // 0-15: 系统颜色（随终端主题变化）
    (0, 0, 0),       //   0 Black
    (128, 0, 0),     //   1 Maroon
    // ...
    (255, 255, 255), //  15 White
    
    // 16-231: 6x6x6 RGB 立方
    (0, 0, 0),       //  16 Grey0
    (0, 0, 95),      //  17 NavyBlue
    // ...
    
    // 232-255: 灰度渐变
    (8, 8, 8),       // 232 Grey3
    (18, 18, 18),    // 233 Grey7
    // ...
    (238, 238, 238), // 255 Grey93
];
```

### 感知距离计算

```rust
// 来自 color.rs
pub(crate) fn perceptual_distance(a: (u8, u8, u8), b: (u8, u8, u8)) -> f32 {
    // CIE76 公式：Lab 空间中的欧几里得距离
    // 1. sRGB -> Linear RGB
    // 2. Linear RGB -> XYZ
    // 3. XYZ -> Lab
    // 4. 计算欧几里得距离
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/terminal_palette.rs` (439 行)

### 依赖模块
| 模块 | 用途 |
|------|------|
| `color.rs` | 提供 `perceptual_distance` |
| `supports_color` | 检测终端颜色能力 |
| `crossterm::style` | 查询终端默认颜色 |

### 调用方
- `style.rs` - 获取默认背景色计算消息样式
- `diff_render.rs` - 颜色量化和调色板选择
- `shimmer.rs` - 获取默认前景/背景色
- `render/highlight.rs` - 语法高亮颜色适配

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `supports_color` | 检测终端颜色能力 |
| `crossterm` | 查询终端默认颜色（Unix） |
| `ratatui::style::Color` | 颜色类型 |

### 内部依赖
- `color::perceptual_distance` - CIE76 颜色距离计算

## 风险、边界与改进建议

### 潜在风险

1. **OSC 序列兼容性**：`query_foreground_color` 和 `query_background_color` 依赖 OSC 序列，某些终端可能不支持或实现不一致。

2. **缓存失效**：`DEFAULT_PALETTE_VERSION` 使用 `Relaxed` 内存序，在极端并发场景下可能不一致（但实践中可接受）。

3. **系统颜色变化**：Xterm 颜色的 0-15 索引是系统颜色，实际显示取决于终端主题，但代码中用于距离计算。

### 边界情况

1. **查询失败处理**：当颜色查询失败时，缓存 `attempted = true` 和 `value = None`，避免重复失败查询。

2. **重新查询限制**：`requery_default_colors` 不会重试之前已经失败的查询。

3. **非 Unix 平台**：Windows 和其他平台返回 `None`，依赖调用方的回退逻辑。

### 改进建议

1. **Windows 支持**：考虑使用 Windows Console API 查询默认颜色。

2. **配置覆盖**：允许用户通过配置手动指定颜色能力，覆盖自动检测。

3. **更多颜色空间**：当前使用 CIE76，可考虑更精确的 CIEDE2000。

4. **缓存持久化**：考虑在会话间缓存颜色能力检测结果。

5. **终端特定优化**：针对不同终端（iTerm2、Windows Terminal 等）的已知特性进行优化。

6. **动态检测**：在运行时检测颜色变化（如用户切换终端主题）。

### 代码质量

- 良好的平台抽象：使用 `imp` 模块隔离平台特定代码
- 缓存设计合理：避免重复查询终端
- 版本控制：支持缓存失效
- 常量定义完整：完整的 Xterm 256 色表
