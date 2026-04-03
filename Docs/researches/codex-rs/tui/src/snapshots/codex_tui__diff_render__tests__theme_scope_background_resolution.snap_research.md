# Theme Scope Background Resolution Snapshot 研究文档

## 场景与职责

此快照测试验证了**语法主题作用域背景色解析**功能。该功能允许用户通过自定义语法主题来覆盖默认的 diff 背景色，实现个性化的 diff 显示效果。

测试场景：
- 使用自定义主题作用域颜色
- 验证插入行（insert）和删除行（delete）的背景色正确解析

## 功能点目的

### 主题作用域背景色系统

Codex TUI 支持从语法主题中读取特定的作用域来设置 diff 背景色：

1. **插入行背景色**：
   - 优先：`markup.inserted`
   - 回退：`diff.inserted`

2. **删除行背景色**：
   - 优先：`markup.deleted`
   - 回退：`diff.deleted`

### 颜色解析流程

```rust
fn resolve_diff_backgrounds(
    theme: DiffTheme,
    color_level: DiffColorLevel,
) -> ResolvedDiffBackgrounds {
    resolve_diff_backgrounds_for(theme, color_level, diff_scope_background_rgbs())
}
```

### 回退机制

如果主题未定义上述作用域，使用硬编码的默认调色板：

```rust
fn fallback_diff_backgrounds(
    theme: DiffTheme,
    color_level: DiffColorLevel,
) -> ResolvedDiffBackgrounds {
    match RichDiffColorLevel::from_diff_color_level(color_level) {
        Some(level) => ResolvedDiffBackgrounds {
            add: Some(add_line_bg(theme, level)),  // 默认绿色背景
            del: Some(del_line_bg(theme, level)),  // 默认红色背景
        },
        None => ResolvedDiffBackgrounds::default(),  // ANSI-16：无背景
    }
}
```

## 具体技术实现

### 数据结构

```rust
// 解析后的背景色
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct ResolvedDiffBackgrounds {
    add: Option<Color>,  // 插入行背景色
    del: Option<Color>,  // 删除行背景色
}

// 主题作用域 RGB 值（来自 syntect 主题）
pub struct DiffScopeBackgroundRgbs {
    pub inserted: Option<(u8, u8, u8)>,
    pub deleted: Option<(u8, u8, u8)>,
}
```

### 解析逻辑

```rust
fn resolve_diff_backgrounds_for(
    theme: DiffTheme,
    color_level: DiffColorLevel,
    scope_backgrounds: DiffScopeBackgroundRgbs,
) -> ResolvedDiffBackgrounds {
    // 从默认调色板开始
    let mut resolved = fallback_diff_backgrounds(theme, color_level);
    
    let Some(level) = RichDiffColorLevel::from_diff_color_level(color_level) else {
        return resolved;  // ANSI-16：返回无背景
    };

    // 用主题定义的颜色覆盖默认值
    if let Some(rgb) = scope_backgrounds.inserted {
        resolved.add = Some(color_from_rgb_for_level(rgb, level));
    }
    if let Some(rgb) = scope_backgrounds.deleted {
        resolved.del = Some(color_from_rgb_for_level(rgb, level));
    }
    resolved
}
```

### 颜色级别转换

```rust
fn color_from_rgb_for_level(rgb: (u8, u8, u8), color_level: RichDiffColorLevel) -> Color {
    match color_level {
        RichDiffColorLevel::TrueColor => rgb_color(rgb),  // 直接使用 RGB
        RichDiffColorLevel::Ansi256 => quantize_rgb_to_ansi256(rgb),  // 量化为 ANSI-256
    }
}
```

### ANSI-256 量化

```rust
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

## 关键代码路径与文件引用

### 核心函数

| 函数 | 文件 | 行号 | 职责 |
|------|------|------|------|
| `resolve_diff_backgrounds` | `diff_render.rs` | 198-203 | 解析主题背景色主入口 |
| `resolve_diff_backgrounds_for` | `diff_render.rs` | 231-248 | 核心解析逻辑 |
| `fallback_diff_backgrounds` | `diff_render.rs` | 252-263 | 默认调色板 |
| `color_from_rgb_for_level` | `diff_render.rs` | 267-272 | RGB 转终端颜色 |
| `quantize_rgb_to_ansi256` | `diff_render.rs` | 280-293 | ANSI-256 量化 |

### 测试代码

```rust
#[test]
fn ui_snapshot_theme_scope_background_resolution() {
    let backgrounds = resolve_diff_backgrounds_for(
        DiffTheme::Dark,
        DiffColorLevel::TrueColor,
        DiffScopeBackgroundRgbs {
            inserted: Some((12, 34, 56)),  // 自定义插入行颜色
            deleted: None,                  // 使用默认删除行颜色
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

### 输出解析

```
insert=Some(Rgb(12, 34, 56))
delete=Some(Rgb(74, 34, 29))
```

说明：
- `insert`：使用了自定义的 `(12, 34, 56)` RGB 值
- `delete`：使用了默认的暗色主题删除行颜色 `(74, 34, 29)`（#4A221D）

## 依赖与外部交互

### 主题系统集成

```rust
// 从当前激活的语法主题获取作用域背景色
pub fn diff_scope_background_rgbs() -> DiffScopeBackgroundRgbs {
    // 查询 syntect 主题中的特定作用域
    // - markup.inserted / diff.inserted
    // - markup.deleted / diff.deleted
}
```

### 调色板常量

```rust
// 暗色主题默认背景
const DARK_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (33, 58, 43);   // #213A2B
const DARK_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (74, 34, 29);   // #4A221D

// 亮色主题默认背景（GitHub 风格）
const LIGHT_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (218, 251, 225); // #dafbe1
const LIGHT_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (255, 235, 233); // #ffebe9
```

### XTerm 256 色表

```rust
const XTERM_COLORS: [(u8, u8, u8); 256] = [
    // 索引 0-15: 系统颜色
    // 索引 16-255: 216 色立方 + 24 灰度
    // ...
];
```

## 风险、边界与改进建议

### 边界情况

1. **ANSI-16 终端**：
   ```rust
   let Some(level) = RichDiffColorLevel::from_diff_color_level(color_level) else {
       return resolved;  // 返回默认（无背景）
   };
   ```
   ANSI-16 终端完全不显示背景色，无论主题如何定义

2. **主题未定义作用域**：
   - 如果主题没有 `markup.inserted` 或 `diff.inserted`
   - 回退到硬编码调色板

3. **颜色量化误差**：
   - TrueColor → ANSI-256 转换可能产生视觉差异
   - 使用感知距离最小化误差

### 潜在风险

1. **主题兼容性**：
   - 不同主题对作用域的命名可能不一致
   - 某些主题可能使用非标准命名

2. **性能问题**：
   ```rust
   XTERM_COLORS
       .iter()
       .enumerate()
       .skip(16)
       .min_by(|(_, a), (_, b)| { ... })
   ```
   每次解析都需要遍历 240 个颜色，虽然单次开销小，但频繁调用可能影响性能

3. **颜色对比度**：
   - 用户自定义主题可能选择对比度不足的颜色
   - 可能导致文字难以阅读

### 改进建议

1. **性能优化**：
   - 缓存主题解析结果
   - 使用查找表加速 ANSI-256 量化
   - 仅在主题切换时重新解析

2. **可访问性**：
   - 添加对比度检查，警告低对比度组合
   - 提供高对比度预设主题

3. **功能扩展**：
   - 支持更多自定义作用域（如 `diff.context` 上下文行背景）
   - 允许用户通过配置文件覆盖颜色
   - 支持透明度/混合模式

4. **文档改进**：
   - 提供主题制作指南
   - 列出推荐的作用域名称
   - 提供示例主题配置

5. **测试覆盖**：
   - 添加 ANSI-256 量化精度测试
   - 测试各种主题的边缘情况
   - 验证颜色对比度符合 WCAG 标准
