# Theme Scope Background Resolution 快照研究文档

## 场景与职责

此快照测试验证了**语法主题作用域背景色解析**功能。该功能允许用户通过自定义语法主题来覆盖默认的 diff 背景色，实现个性化的差异展示效果。

### 测试场景
- **主题**: Dark
- **颜色级别**: TrueColor
- **自定义插入背景**: RGB(12, 34, 56)
- **自定义删除背景**: 未设置（使用默认值）

### 核心功能
验证 `resolve_diff_backgrounds_for` 函数正确：
1. 解析主题定义的作用域背景色
2. 与默认调色板正确合并
3. 根据颜色级别（TrueColor/ANSI256）正确转换

## 功能点目的

### 1. 主题自定义支持
- 允许语法主题定义 `markup.inserted` / `markup.deleted` 作用域
- 或使用 fallback `diff.inserted` / `diff.deleted`
- 自定义颜色覆盖默认调色板

### 2. 颜色级别适配
- TrueColor: 直接使用 RGB 值
- ANSI256: 通过 `quantize_rgb_to_ansi256` 量化到最接近的调色板颜色

### 3. 部分覆盖支持
- 可以只设置插入或删除其中一个的背景色
- 未设置的使用默认调色板

## 具体技术实现

### 背景色解析流程

```rust
/// 解析 diff 背景色（生产环境入口）
fn resolve_diff_backgrounds(
    theme: DiffTheme,
    color_level: DiffColorLevel,
) -> ResolvedDiffBackgrounds {
    resolve_diff_backgrounds_for(theme, color_level, diff_scope_background_rgbs())
}

/// 可测试的核心解析逻辑
fn resolve_diff_backgrounds_for(
    theme: DiffTheme,
    color_level: DiffColorLevel,
    scope_backgrounds: DiffScopeBackgroundRgbs,
) -> ResolvedDiffBackgrounds {
    // 1. 从默认调色板开始
    let mut resolved = fallback_diff_backgrounds(theme, color_level);
    
    // 2. ANSI-16 模式不支持背景色，直接返回
    let Some(level) = RichDiffColorLevel::from_diff_color_level(color_level) else {
        return resolved;
    };

    // 3. 使用主题定义的颜色覆盖默认值
    if let Some(rgb) = scope_backgrounds.inserted {
        resolved.add = Some(color_from_rgb_for_level(rgb, level));
    }
    if let Some(rgb) = scope_backgrounds.deleted {
        resolved.del = Some(color_from_rgb_for_level(rgb, level));
    }
    resolved
}
```

### 主题作用域查询

```rust
// render/highlight.rs
pub struct DiffScopeBackgroundRgbs {
    pub inserted: Option<(u8, u8, u8)>,
    pub deleted: Option<(u8, u8, u8)>,
}

pub fn diff_scope_background_rgbs() -> DiffScopeBackgroundRgbs {
    // 查询当前语法主题的 scope 设置
    // 优先查找 "markup.inserted" / "markup.deleted"
    // fallback 到 "diff.inserted" / "diff.deleted"
}
```

### 颜色级别转换

```rust
fn color_from_rgb_for_level(rgb: (u8, u8, u8), color_level: RichDiffColorLevel) -> Color {
    match color_level {
        RichDiffColorLevel::TrueColor => rgb_color(rgb),  // 直接使用 RGB
        RichDiffColorLevel::Ansi256 => quantize_rgb_to_ansi256(rgb),  // 量化到 256 色
    }
}

/// 使用感知距离量化到 ANSI-256
fn quantize_rgb_to_ansi256(target: (u8, u8, u8)) -> Color {
    let best_index = XTERM_COLORS
        .iter()
        .enumerate()
        .skip(16)  // 跳过前 16 个系统颜色
        .min_by(|(_, a), (_, b)| {
            perceptual_distance(**a, target)
                .total_cmp(&perceptual_distance(**b, target))
        })
        .map(|(index, _)| index as u8);
    // ...
}
```

### 测试代码

```rust
#[test]
fn ui_snapshot_theme_scope_background_resolution() {
    let backgrounds = resolve_diff_backgrounds_for(
        DiffTheme::Dark,
        DiffColorLevel::TrueColor,
        DiffScopeBackgroundRgbs {
            inserted: Some((12, 34, 56)),  // 自定义插入背景
            deleted: None,                  // 删除背景使用默认
        },
    );
    let snapshot = format!(
        "insert={:?}\ndelete={:?}",
        style_line_bg_for(DiffLineType::Insert, backgrounds).bg,
        style_line_bg_for(DiffLineType::Delete, backgrounds).bg,
    );
    assert_snapshot!("theme_scope_background_resolution", snapshot);
}
```

## 关键代码路径与文件引用

### 核心类型和函数

| 名称 | 位置 | 职责 |
|------|------|------|
| `DiffScopeBackgroundRgbs` | render/highlight.rs | 主题作用域背景色 RGB 值 |
| `diff_scope_background_rgbs` | render/highlight.rs | 查询当前主题的作用域颜色 |
| `resolve_diff_backgrounds` | diff_render.rs:198 | 生产环境背景色解析入口 |
| `resolve_diff_backgrounds_for` | diff_render.rs:231 | 可测试的核心解析逻辑 |
| `color_from_rgb_for_level` | diff_render.rs:267 | 根据颜色级别转换 RGB |
| `quantize_rgb_to_ansi256` | diff_render.rs:280 | RGB 量化到 ANSI-256 |
| `perceptual_distance` | color.rs | 计算感知颜色距离 |

### 默认调色板常量

```rust
// 深色主题
const DARK_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (33, 58, 43);   // #213A2B
const DARK_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (74, 34, 29);   // #4A221D

// 浅色主题（GitHub 风格）
const LIGHT_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (218, 251, 225); // #dafbe1
const LIGHT_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (255, 235, 233); // #ffebe9
```

### ANSI-256 调色板索引

```rust
const DARK_256_ADD_LINE_BG_IDX: u8 = 22;   // 深绿色
const DARK_256_DEL_LINE_BG_IDX: u8 = 52;   // 深红色
const LIGHT_256_ADD_LINE_BG_IDX: u8 = 194; // 浅绿色
const LIGHT_256_DEL_LINE_BG_IDX: u8 = 224; // 浅红色
```

## 依赖与外部交互

### syntect 主题集成

```rust
// 通过 syntect 查询主题设置
use syntect::highlighting::Theme;
use syntect::highlighting::ThemeSettings;

// 从主题设置中提取背景色
fn extract_scope_background(theme: &Theme, scope: &str) -> Option<(u8, u8, u8)> {
    // ...
}
```

### 感知颜色距离

```rust
// color.rs - 使用 CIE76 或类似算法
pub fn perceptual_distance(a: (u8, u8, u8), b: (u8, u8, u8)) -> f32 {
    // 将 RGB 转换到 Lab 颜色空间
    // 计算欧几里得距离
}
```

### XTerm 颜色表

```rust
// terminal_palette.rs
pub const XTERM_COLORS: [(u8, u8, u8); 256] = [
    // 0-15: 系统颜色
    // 16-231: 6x6x6 颜色立方
    // 232-255: 灰度渐变
];
```

## 风险、边界与改进建议

### 边界情况

1. **ANSI-16 模式**
   - `RichDiffColorLevel::from_diff_color_level` 返回 `None`
   - 背景色被禁用，无论主题如何设置
   - 这是有意设计，避免 ANSI-16 的饱和背景色

2. **无效 RGB 值**
   - 主题可能定义超出范围的 RGB 值
   - 需要验证和截断处理

3. **颜色量化误差**
   - TrueColor 到 ANSI256 的转换会丢失精度
   - 某些颜色可能被量化到相近但不相同的颜色

### 潜在风险

1. **主题兼容性**
   - 不同主题可能使用不同的作用域命名
   - 当前使用 `markup.inserted` 和 `diff.inserted` 作为 fallback

2. **性能问题**
   - `quantize_rgb_to_ansi256` 每次遍历 240 个颜色
   - 虽然单次开销小，但频繁调用可能影响性能

3. **缓存失效**
   - 主题可以在运行时切换
   - `current_diff_render_style_context` 每帧重新查询

### 改进建议

1. **量化缓存**
   - 缓存 RGB 到 ANSI256 的映射结果
   - 使用 LRU 缓存避免重复计算

2. **更多作用域支持**
   - 支持 `markup.changed` 用于修改行
   - 支持 `diff.context` 用于上下文行背景

3. **渐变背景**
   - 支持行号 gutter 和内容的渐变背景
   - 增强视觉层次感

4. **主题验证工具**
   - 提供工具验证主题定义的作用域
   - 列出可用的 diff 相关作用域

5. **文档完善**
   - 明确文档化支持的作用域名称
   - 提供主题制作指南
