# 技术调研：主题 Scope 背景色解析与解析

## 场景与职责

本测试快照验证 Codex TUI 的 **diff 背景色主题化机制**。该功能允许用户通过自定义语法主题（.tmTheme 文件）来覆盖默认的 diff 插入/删除行背景色，实现与编辑器/IDE 一致的视觉体验。

### 应用场景
- 用户使用自定义配色方案（如 Dracula、Nord、Solarized 等）
- 企业/团队统一代码审查界面的视觉风格
- 无障碍需求（高对比度、色盲友好配色）

### 核心职责
1. 从语法主题中提取 diff 专用 scope 的背景色定义
2. 将主题 RGB 值转换为终端支持的颜色格式（TrueColor/ANSI-256）
3. 当主题未定义时，使用内置的兜底配色方案

## 功能点目的

### 解决的问题
传统 diff 工具使用固定的红/绿配色，可能与用户的语法主题不协调。本功能：
- 读取主题中 `markup.inserted` 和 `markup.deleted` scope 的背景色
- 回退支持 `diff.inserted` 和 `diff.deleted` scope
- 自动适配终端颜色能力（TrueColor → ANSI-256 → ANSI-16）

### 测试验证点
- 验证 `resolve_diff_backgrounds_for` 函数正确解析主题定义的背景色
- 验证 RGB 值（如 `(12, 34, 56)`）正确转换为 ratatui 的 `Color::Rgb`
- 验证未定义的颜色回退到默认调色板

## 具体技术实现

### 测试代码路径
**文件**: `codex-rs/tui_app_server/src/diff_render.rs`  
**函数**: `ui_snapshot_theme_scope_background_resolution` (第1896-1911行)

```rust
#[test]
fn ui_snapshot_theme_scope_background_resolution() {
    let backgrounds = resolve_diff_backgrounds_for(
        DiffTheme::Dark,
        DiffColorLevel::TrueColor,
        DiffScopeBackgroundRgbs {
            inserted: Some((12, 34, 56)),
            deleted: None,  // 故意留空，测试回退行为
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

### 核心数据结构

#### `DiffScopeBackgroundRgbs`
**路径**: `codex-rs/tui_app_server/src/render/highlight.rs` (第267-271行)

```rust
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(crate) struct DiffScopeBackgroundRgbs {
    pub inserted: Option<(u8, u8, u8)>,  // RGB 三元组
    pub deleted: Option<(u8, u8, u8)>,
}
```

#### `ResolvedDiffBackgrounds`
**路径**: `codex-rs/tui_app_server/src/diff_render.rs` (第176-180行)

```rust
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct ResolvedDiffBackgrounds {
    add: Option<Color>,  // 已转换的 ratatui Color
    del: Option<Color>,
}
```

### 核心函数实现

#### 1. `resolve_diff_backgrounds_for`
**路径**: `codex-rs/tui_app_server/src/diff_render.rs` (第231-248行)

```rust
fn resolve_diff_backgrounds_for(
    theme: DiffTheme,
    color_level: DiffColorLevel,
    scope_backgrounds: DiffScopeBackgroundRgbs,
) -> ResolvedDiffBackgrounds {
    // 1. 先获取兜底配色
    let mut resolved = fallback_diff_backgrounds(theme, color_level);
    
    // 2. ANSI-16 模式不支持背景色，直接返回
    let Some(level) = RichDiffColorLevel::from_diff_color_level(color_level) else {
        return resolved;
    };

    // 3. 用主题定义覆盖兜底配色
    if let Some(rgb) = scope_backgrounds.inserted {
        resolved.add = Some(color_from_rgb_for_level(rgb, level));
    }
    if let Some(rgb) = scope_backgrounds.deleted {
        resolved.del = Some(color_from_rgb_for_level(rgb, level));
    }
    resolved
}
```

#### 2. `diff_scope_background_rgbs_for_theme`
**路径**: `codex-rs/tui_app_server/src/render/highlight.rs` (第285-292行)

从实际主题中提取背景色：
```rust
fn diff_scope_background_rgbs_for_theme(theme: &Theme) -> DiffScopeBackgroundRgbs {
    let highlighter = Highlighter::new(theme);
    // 优先 markup.inserted/markup.deleted (VS Code 主题规范)
    let inserted = scope_background_rgb(&highlighter, "markup.inserted")
        .or_else(|| scope_background_rgb(&highlighter, "diff.inserted"));
    let deleted = scope_background_rgb(&highlighter, "markup.deleted")
        .or_else(|| scope_background_rgb(&highlighter, "diff.deleted"));
    DiffScopeBackgroundRgbs { inserted, deleted }
}
```

#### 3. `color_from_rgb_for_level`
**路径**: `codex-rs/tui_app_server/src/diff_render.rs` (第267-272行)

根据颜色级别转换 RGB：
```rust
fn color_from_rgb_for_level(rgb: (u8, u8, u8), color_level: RichDiffColorLevel) -> Color {
    match color_level {
        RichDiffColorLevel::TrueColor => rgb_color(rgb),           // 24-bit RGB
        RichDiffColorLevel::Ansi256 => quantize_rgb_to_ansi256(rgb), // 量化到 256 色
    }
}
```

#### 4. `quantize_rgb_to_ansi256`
**路径**: `codex-rs/tui_app_server/src/diff_render.rs` (第280-293行)

使用感知距离算法将 RGB 量化到 ANSI-256 调色板：
```rust
fn quantize_rgb_to_ansi256(target: (u8, u8, u8)) -> Color {
    let best_index = XTERM_COLORS
        .iter()
        .enumerate()
        .skip(16)  // 跳过前16个系统颜色
        .min_by(|(_, a), (_, b)| {
            perceptual_distance(**a, target)
                .total_cmp(&perceptual_distance(**b, target))
        })
        .map(|(index, _)| index as u8);
    // ...
}
```

### 快照输出解析

```
insert=Some(Rgb(12, 34, 56))
delete=Some(Rgb(74, 34, 29))
```

- `insert=Some(Rgb(12, 34, 56))`: 主题定义的插入行背景色被正确解析
- `delete=Some(Rgb(74, 34, 29))`: 删除行使用兜底配色（深红色 `#4A221D`）

## 关键代码路径与文件引用

### 文件依赖图
```
diff_render.rs
├── resolve_diff_backgrounds()
│   └── resolve_diff_backgrounds_for()
│       ├── fallback_diff_backgrounds()  [内置兜底配色]
│       └── color_from_rgb_for_level()
│           ├── rgb_color()              [TrueColor]
│           └── quantize_rgb_to_ansi256() [ANSI-256]
│
└── highlight.rs
    └── diff_scope_background_rgbs()
        └── diff_scope_background_rgbs_for_theme()
            └── scope_background_rgb()   [syntect scope 查询]
```

### 内置兜底配色
**路径**: `codex-rs/tui_app_server/src/diff_render.rs` (第59-75行)

```rust
// TrueColor 调色板
const DARK_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (33, 58, 43);    // #213A2B 深绿
const DARK_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (74, 34, 29);    // #4A221D 深红
const LIGHT_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (218, 251, 225); // #dafbe1 浅绿
const LIGHT_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (255, 235, 233); // #ffebe9 浅红

// ANSI-256 调色板
const DARK_256_ADD_LINE_BG_IDX: u8 = 22;   // 深绿
const DARK_256_DEL_LINE_BG_IDX: u8 = 52;   // 深红
const LIGHT_256_ADD_LINE_BG_IDX: u8 = 194; // 浅绿
const LIGHT_256_DEL_LINE_BG_IDX: u8 = 224; // 浅红
```

### 主题 Scope 优先级
1. `markup.inserted` / `markup.deleted` - TextMate/VS Code 标准
2. `diff.inserted` / `diff.deleted` - 传统 .tmTheme 文件

## 依赖与外部交互

### syntect 集成
| 组件 | 用途 |
|------|------|
| `Highlighter` | 从主题解析 scope 样式 |
| `Scope::new()` | 创建 TextMate scope 查询 |
| `style_mod_for_stack()` | 获取 scope 的样式修饰符 |

### 颜色转换
- **TrueColor**: 直接使用 RGB 值（24位色）
- **ANSI-256**: 使用 `XTERM_COLORS` 常量表（第91行附近定义）
- **ANSI-16**: 禁用背景色，仅使用前景色

### 终端检测
通过 `terminal_palette` 模块检测：
- `stdout_color_level()` - 颜色支持级别
- `default_bg()` - 终端背景色（用于亮/暗主题判断）
- `WT_SESSION` 环境变量 - Windows Terminal 特殊处理

## 风险、边界与改进建议

### 已知风险

1. **主题兼容性**
   - 并非所有主题都定义 diff scope
   - 某些主题的背景色可能与前景色对比度不足
   - 建议：添加对比度检查，必要时自动调整

2. **ANSI-16 降级**
   - 在仅支持16色的终端中，背景色完全禁用
   - 可能导致 diff 视觉区分度降低
   - 建议：考虑使用反向显示（reverse video）或下划线

3. **量化误差**
   - RGB 到 ANSI-256 的转换存在感知误差
   - 某些颜色在量化后可能与原色差异明显

### 边界情况

| 场景 | 行为 |
|------|------|
| 主题只定义 inserted | deleted 使用兜底配色 |
| 主题只定义 deleted | inserted 使用兜底配色 |
| 两者都未定义 | 完全使用兜底配色 |
| ANSI-16 模式 | 返回 `ResolvedDiffBackgrounds::default()`（None） |
| 无效 RGB 值 | 不可能发生（u8 类型保证） |

### 改进建议

1. **对比度验证**
   ```rust
   // 建议添加
   fn ensure_contrast(background: Color, foreground: Color) -> Color {
       // 使用 WCAG 对比度算法
       // 如果对比度不足，调整背景色亮度
   }
   ```

2. **更多 scope 回退**
   - 支持 `markup.changed` 用于修改行
   - 支持 `diff.changed` 作为额外回退

3. **用户自定义覆盖**
   ```toml
   # config.toml 建议添加
   [theme.diff]
   insert_bg = "#123456"
   delete_bg = "#654321"
   ```

4. **实时预览优化**
   - 当前 `set_syntax_theme` 会立即生效
   - 建议添加主题预览模式，不保存到配置

5. **测试扩展**
   - 添加 ANSI-256 量化结果验证测试
   - 添加亮色主题背景解析测试
   - 添加多主题（Dracula、Nord 等）的实际解析测试

### 相关测试
- `theme_scope_backgrounds_override_truecolor_fallback_when_available` - 主题覆盖验证
- `theme_scope_backgrounds_quantize_to_ansi256` - 量化验证
- `ansi16_disables_line_and_gutter_backgrounds` - ANSI-16 降级验证
- `light_truecolor_theme_uses_readable_gutter_and_line_backgrounds` - 亮色主题验证
