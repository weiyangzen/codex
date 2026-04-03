# Diff Render ANSI16 Mode 研究文档

## 场景与职责

该组件负责在 Codex TUI 的 ANSI-16 颜色模式终端中渲染差异内容。当用户使用仅支持 16 色的终端（如某些基础终端模拟器或特定环境配置）时，系统需要降级到前景色-only 的渲染模式，确保差异内容仍然可读且区分度高。

## 功能点目的

ANSI-16 差异渲染的核心目的：

1. **兼容性保障**：支持仅支持 16 色的老旧终端
2. **可读性维护**：即使没有背景色，仍通过前景色区分添加/删除
3. **性能优化**：ANSI-16 模式渲染更快，适合资源受限环境
4. **降级策略**：自动检测终端能力并选择合适的渲染模式
5. **一致性**：保持与真彩色/256色模式相同的布局结构

## 具体技术实现

### 颜色级别检测

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum DiffColorLevel {
    TrueColor,  // 24位真彩色
    Ansi256,    // 256色
    Ansi16,     // 16色（此场景）
}

/// 检测当前终端的颜色级别
fn diff_color_level() -> DiffColorLevel {
    diff_color_level_for_terminal(
        stdout_color_level(),
        terminal_info().name,
        std::env::var_os("WT_SESSION").is_some(),
        has_force_color_override(),
    )
}
```

### ANSI-16 模式判断

```rust
fn diff_color_level_for_terminal(
    stdout_level: StdoutColorLevel,
    terminal_name: TerminalName,
    has_wt_session: bool,
    has_force_color_override: bool,
) -> DiffColorLevel {
    // Windows Terminal 特殊处理：即使报告 ANSI-16 也提升到真彩色
    if has_wt_session && !has_force_color_override {
        return DiffColorLevel::TrueColor;
    }

    match stdout_level {
        StdoutColorLevel::TrueColor => DiffColorLevel::TrueColor,
        StdoutColorLevel::Ansi256 => DiffColorLevel::Ansi256,
        StdoutColorLevel::Ansi16 | StdoutColorLevel::Unknown => DiffColorLevel::Ansi16,
    }
}
```

### ANSI-16 样式定义

```rust
// 添加行样式 - 仅使用绿色前景色
fn style_add(
    theme: DiffTheme,
    color_level: DiffColorLevel,
    diff_backgrounds: ResolvedDiffBackgrounds,
) -> Style {
    match (theme, color_level, diff_backgrounds.add) {
        // ANSI-16 模式：仅前景色，无背景色
        (_, DiffColorLevel::Ansi16, _) => Style::default().fg(Color::Green),
        // 其他模式可能使用背景色...
        _ => /* ... */
    }
}

// 删除行样式 - 仅使用红色前景色
fn style_del(
    theme: DiffTheme,
    color_level: DiffColorLevel,
    diff_backgrounds: ResolvedDiffBackgrounds,
) -> Style {
    match (theme, color_level, diff_backgrounds.del) {
        // ANSI-16 模式：仅前景色，无背景色
        (_, DiffColorLevel::Ansi16, _) => Style::default().fg(Color::Red),
        // 其他模式可能使用背景色...
        _ => /* ... */
    }
}
```

### 渲染输出示例

```
"1 +added in ansi16 mode                 "
"2 -deleted in ansi16 mode               "
```

**特点**：
- 行号（1, 2）使用默认颜色
- `+` 符号使用绿色前景色
- `-` 符号使用红色前景色
- 内容文本使用对应颜色
- **无背景色**（与真彩色/256色模式的主要区别）

### 富色级别转换

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RichDiffColorLevel {
    TrueColor,
    Ansi256,
}

impl RichDiffColorLevel {
    /// 从 DiffColorLevel 提取富色级别，ANSI-16 返回 None
    fn from_diff_color_level(level: DiffColorLevel) -> Option<Self> {
        match level {
            DiffColorLevel::TrueColor => Some(Self::TrueColor),
            DiffColorLevel::Ansi256 => Some(Self::Ansi256),
            DiffColorLevel::Ansi16 => None,  // ANSI-16 不支持背景色
        }
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/diff_render.rs` | 差异渲染核心实现 |
| `/home/sansha/Github/codex/codex-rs/tui/src/diff_render.rs` | `DiffColorLevel` 枚举（第 133-138 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/diff_render.rs` | `RichDiffColorLevel` 枚举（第 151-155 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/diff_render.rs` | `diff_color_level` 函数（第 1053-1060 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/diff_render.rs` | `diff_color_level_for_terminal` 函数（第 1089-1115 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/diff_render.rs` | `style_add` 函数（第 1258-1276 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/diff_render.rs` | `style_del` 函数（第 1282-1299 行） |

### 测试代码
```rust
#[test]
fn ansi16_add_style_uses_foreground_only() {
    let style = style_add(
        DiffTheme::Dark,
        DiffColorLevel::Ansi16,
        fallback_diff_backgrounds(DiffTheme::Dark, DiffColorLevel::Ansi16),
    );
    assert_eq!(style.fg, Some(Color::Green));
    assert_eq!(style.bg, None);  // 确认无背景色
}

#[test]
fn ansi16_insert_delete_no_background() {
    let mut lines = push_wrapped_diff_line_inner_with_theme_and_color_level(
        1,
        DiffLineType::Insert,
        "added in ansi16 mode",
        80,
        line_number_width(2),
        None,
        DiffTheme::Dark,
        DiffColorLevel::Ansi16,
        fallback_diff_backgrounds(DiffTheme::Dark, DiffColorLevel::Ansi16),
    );
    lines.extend(push_wrapped_diff_line_inner_with_theme_and_color_level(
        2,
        DiffLineType::Delete,
        "deleted in ansi16 mode",
        80,
        line_number_width(2),
        None,
        DiffTheme::Dark,
        DiffColorLevel::Ansi16,
        fallback_diff_backgrounds(DiffTheme::Dark, DiffColorLevel::Ansi16),
    ));
    snapshot_lines("ansi16_insert_delete_no_background", lines, 40, 4);
}
```

## 依赖与外部交互

### 依赖模块
- `crate::terminal_palette::StdoutColorLevel` - 终端颜色级别检测
- `crate::terminal_palette::stdout_color_level` - 获取 stdout 颜色支持
- `codex_core::terminal::terminal_info` - 终端信息检测

### 环境变量检测
```rust
/// 检测 FORCE_COLOR 是否设置
fn has_force_color_override() -> bool {
    std::env::var_os("FORCE_COLOR").is_some()
}

/// Windows Terminal 检测
std::env::var_os("WT_SESSION").is_some()
```

### 终端名称检测
```rust
// codex_core::terminal::TerminalName
pub enum TerminalName {
    WindowsTerminal,
    AppleTerminal,
    VSCode,
    JetBrains,
    // ...
    Unknown,
}
```

## 风险、边界与改进建议

### 边界情况

1. **终端谎报能力**：某些终端报告支持 256 色但实际只支持 16 色
2. **tmux/screen**：终端复用器可能改变颜色能力检测
3. **SSH 会话**：通过 SSH 连接时颜色能力可能不同
4. **CI 环境**：CI 环境通常强制使用无颜色或 16 色模式

### 潜在风险

1. **可读性降低**：无背景色时，添加/删除行可能不够醒目
2. **色盲用户**：红绿色盲用户可能难以区分添加/删除
3. **对比度问题**：某些终端配色下前景色对比度不足
4. **性能误优化**：错误地降级到 ANSI-16 可能降低用户体验

### 改进建议

1. **用户覆盖选项**：
   ```rust
   // 建议添加配置选项允许用户强制颜色模式
   struct DiffRenderConfig {
       color_mode: ColorMode,  // Auto, TrueColor, Ansi256, Ansi16, None
   }
   ```

2. **符号增强**：
   ```rust
   // 建议在 ANSI-16 模式下使用更明显的符号
   fn get_ansi16_diff_symbols() -> DiffSymbols {
       DiffSymbols {
           add_prefix: ">>+",      // 更明显的添加标记
           delete_prefix: "<<-",   // 更明显的删除标记
           context_prefix: "  ",
       }
   }
   ```

3. **下划线/粗体增强**：
   ```rust
   // 建议使用样式修饰符增强可读性
   fn style_add_ansi16() -> Style {
       Style::default()
           .fg(Color::Green)
           .add_modifier(Modifier::BOLD)
           .add_modifier(Modifier::UNDERLINED)
   }
   ```

4. **运行时检测验证**：
   ```rust
   // 建议在启动时验证颜色能力
   fn verify_color_capability() -> VerifiedColorLevel {
       // 发送测试颜色序列并检测实际显示效果
       // 返回验证后的颜色级别
   }
   ```

5. **渐进增强**：
   ```rust
   // 建议根据内容重要性选择颜色级别
   fn select_color_level_for_content(content: &DiffContent) -> DiffColorLevel {
       if content.is_critical() {
           DiffColorLevel::TrueColor  // 关键内容使用最佳效果
       } else {
           diff_color_level()  // 其他内容使用自动检测
       }
   }
   ```

### 相关测试
- `ansi16_insert_delete_no_background` - ANSI-16 模式差异渲染测试
- `ansi16_add_style_uses_foreground_only` - 添加样式测试
- `ansi16_del_style_uses_foreground_only` - 删除样式测试
- `ansi16_sign_styles_use_foreground_only` - 符号样式测试
- `ansi16_disables_line_and_gutter_backgrounds` - 背景禁用测试
