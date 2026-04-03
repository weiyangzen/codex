# styles.md 研究文档

## 场景与职责

`codex-rs/tui/styles.md` 是 Codex TUI 的视觉样式规范文档，定义了终端用户界面的颜色使用准则。该文档确保 TUI 在不同终端主题下保持一致、可访问且美观的视觉体验。

该规范是 TUI 开发的核心设计指南，直接影响所有 UI 组件的颜色选择和文本样式。

## 功能点目的

### 1. 颜色使用规范

#### 标题和文本层级
| 元素 | 样式 | 说明 |
|------|------|------|
| Headers | **bold** | 标题使用粗体，保留 Markdown `#` 符号 |
| Primary text | 默认 | 主要文本使用默认前景色 |
| Secondary text | `dim` | 次要文本使用暗淡样式 |

#### 前景色规范
| 用途 | ANSI 颜色 | 示例场景 |
|------|-----------|----------|
| 默认 | 默认前景色 | 大部分文本 |
| 用户输入提示、选择、状态指示 | `cyan` | 输入框边框、选中项 |
| 成功、添加 | `green` | 成功消息、新增内容 |
| 错误、失败、删除 | `red` | 错误提示、删除内容 |
| Codex 品牌 | `magenta` | Codex 相关标识 |

### 2. 禁止使用的颜色

#### 避免自定义颜色
- 无保证在不同终端主题下对比度良好
- 例外：`shimmer.rs` 使用默认颜色调整亮度

#### 避免黑白前景色
- 默认终端主题颜色效果更好
- 使用 `reset` 恢复默认
- 例外：需要与手动着色背景形成对比时

#### 避免蓝黄配色
- 当前样式指南不使用 `blue` 和 `yellow`
- 优先使用规范中定义的前景颜色

### 3. 代码检查
规范通过 `clippy.toml` 强制执行：
```toml
# 禁止在特定文件中使用 disallowed-methods
disallowed-methods = [
    # 颜色相关限制...
]
```

## 具体技术实现

### 样式应用代码路径

#### 1. 颜色工具模块
**文件**: `src/color.rs`
```rust
/// 判断背景色是否为浅色
pub(crate) fn is_light(bg: (u8, u8, u8)) -> bool {
    let (r, g, b) = bg;
    let y = 0.299 * r as f32 + 0.587 * g as f32 + 0.114 * b as f32;
    y > 128.0
}

/// 混合前景色和背景色
pub(crate) fn blend(fg: (u8, u8, u8), bg: (u8, u8, u8), alpha: f32) -> (u8, u8, u8) {
    let r = (fg.0 as f32 * alpha + bg.0 as f32 * (1.0 - alpha)) as u8;
    let g = (fg.1 as f32 * alpha + bg.1 as f32 * (1.0 - alpha)) as u8;
    let b = (fg.2 as f32 * alpha + bg.2 as f32 * (1.0 - alpha)) as u8;
    (r, g, b)
}

/// CIE76 感知颜色距离计算
pub(crate) fn perceptual_distance(a: (u8, u8, u8), b: (u8, u8, u8)) -> f32 {
    // sRGB -> Linear RGB -> XYZ -> Lab -> Euclidean distance
}
```

#### 2. 终端调色板
**文件**: `src/terminal_palette.rs`
```rust
/// 获取最佳匹配颜色
pub(crate) fn best_color(rgb: (u8, u8, u8)) -> Color {
    // 根据终端能力返回 RGB 或 ANSI 16 色
}

/// 默认前景色
pub(crate) fn default_fg() -> Option<(u8, u8, u8)> {
    // 查询终端默认前景色
}

/// 默认背景色
pub(crate) fn default_bg() -> Option<(u8, u8, u8)> {
    // 查询终端默认背景色
}
```

#### 3. 用户消息样式
**文件**: `src/style.rs`
```rust
pub fn user_message_style() -> Style {
    user_message_style_for(default_bg())
}

pub fn user_message_style_for(terminal_bg: Option<(u8, u8, u8)>) -> Style {
    match terminal_bg {
        Some(bg) => Style::default().bg(user_message_bg(bg)),
        None => Style::default(),
    }
}

pub fn user_message_bg(terminal_bg: (u8, u8, u8)) -> Color {
    let (top, alpha) = if is_light(terminal_bg) {
        ((0, 0, 0), 0.04)      // 浅色背景：轻微暗化
    } else {
        ((255, 255, 255), 0.12) // 深色背景：轻微亮化
    };
    best_color(blend(top, terminal_bg, alpha))
}
```

#### 4. 闪烁效果（例外情况）
**文件**: `src/shimmer.rs`
```rust
pub(crate) fn shimmer_spans(text: &str) -> Vec<Span<'static>> {
    // 基于时间的扫描动画
    // 使用 blend() 调整默认颜色亮度
    // 这是 styles.md 中提到的例外情况
}
```

### 样式应用示例

#### AGENTS.md 中的规范示例
```rust
// 使用 Stylize trait 的简洁样式
vec!["  └ ".into(), "M".red(), " ".dim(), "tui/src/app.rs".dim()]

// 链接样式
url.cyan().underlined()

// 简单转换
"text".into()           // Span
text.dim()              // 暗淡样式
text.bold()             // 粗体
```

#### 渲染模块
**文件**: `src/render/` 目录
- `highlight.rs`: 语法高亮（使用 `syntect`）
- `line_utils.rs`: 行处理工具
- `renderable.rs`: 可渲染 trait 定义

## 关键代码路径与文件引用

### 核心样式文件
| 文件 | 行数 | 职责 |
|------|------|------|
| `styles.md` | ~21 | 样式规范文档（本文件） |
| `src/color.rs` | ~75 | 颜色计算工具 |
| `src/style.rs` | ~44 | 用户消息样式 |
| `src/terminal_palette.rs` | ~100+ | 终端调色板查询 |
| `src/shimmer.rs` | ~80 | 闪烁动画效果 |

### 样式使用分布
| 模块 | 样式应用 |
|------|----------|
| `src/chatwidget.rs` | 消息渲染、状态指示 |
| `src/bottom_pane/*.rs` | 输入框、弹出框、页脚 |
| `src/history_cell.rs` | 历史消息单元格 |
| `src/diff_render.rs` | 差异渲染 |
| `src/status/*.rs` | 状态显示 |

### Ratatui 集成
```rust
// 使用 ratatui 的 Stylize trait
use ratatui::style::Stylize;

// 示例
Span::styled("text", Style::default().fg(Color::Cyan))
// 简化为：
"text".cyan()

Line::from(vec!["prefix".into(), "content".green()])
```

## 依赖与外部交互

### 外部依赖
| Crate | 用途 |
|-------|------|
| `ratatui` | UI 框架，提供 `Style`, `Color`, `Stylize` |
| `syntect` | 语法高亮主题 |
| `supports-color` | 检测终端颜色支持能力 |

### 内部依赖
| 模块 | 交互 |
|------|------|
| `color.rs` | 提供颜色计算工具 |
| `terminal_palette.rs` | 查询终端默认颜色 |

### 终端能力检测
```rust
// shimmer.rs
let has_true_color = supports_color::on_cached(supports_color::Stream::Stdout)
    .map(|level| level.has_16m)
    .unwrap_or(false);
```

## 风险、边界与改进建议

### 风险点

#### 1. 终端兼容性
- 不同终端对 ANSI 颜色的解释可能不同
- 部分终端可能不支持 `dim` 修饰符
- True Color (24-bit) 支持不一致

#### 2. 主题对比度
```rust
// 当前实现依赖终端默认颜色
// 如果用户主题设置不当，可能导致对比度问题
```

#### 3. 样式一致性
- 多个开发者可能引入不一致的样式
- `clippy.toml` 只能检查部分违规

### 边界条件

#### 1. 背景色自适应
```rust
// style.rs
let (top, alpha) = if is_light(terminal_bg) {
    ((0, 0, 0), 0.04)
} else {
    ((255, 255, 255), 0.12)
};
```
- 阈值固定为 128（Y > 128 为浅色）
- 某些中间色调可能判断不准确

#### 2. 语法高亮主题
```rust
// highlight.rs
pub(crate) fn set_theme_override(
    theme_name: Option<String>,
    codex_home: Option<PathBuf>,
) -> Option<String> {
    // 主题覆盖逻辑
}
```
- 用户自定义主题可能与样式规范冲突

### 改进建议

#### 1. 自动化样式检查
```rust
// 建议添加测试
#[test]
fn verify_style_compliance() {
    // 扫描所有样式使用，确保符合 styles.md
    // 检查：不使用 .white(), .black(), .blue(), .yellow()
}
```

#### 2. 对比度验证
```rust
// 建议添加 WCAG 对比度检查
pub fn verify_contrast(fg: Color, bg: Color) -> bool {
    let ratio = contrast_ratio(fg, bg);
    ratio >= 4.5  // AA 标准
}
```

#### 3. 主题预览工具
```rust
// 建议添加调试命令
SlashCommand::ThemePreview => {
    // 显示所有样式在终端上的实际效果
}
```

#### 4. 文档完善
- 添加样式使用示例图
- 提供常见终端的主题配置建议
- 记录已知问题终端的 workaround

#### 5. 配置化样式
```rust
// 允许用户自定义部分样式
pub struct UserTheme {
    pub success_color: Color,
    pub error_color: Color,
    pub accent_color: Color,
}
```

#### 6. 响应式样式
```rust
// 根据终端宽度调整样式
pub fn adaptive_style(width: u16, style: Style) -> Style {
    if width < 80 {
        // 窄终端使用更明显的对比
        style.add_modifier(Modifier::BOLD)
    } else {
        style
    }
}
```
