# styles.md 研究文档

## 场景与职责

`styles.md` 是 Codex TUI 的视觉样式规范文档，定义了终端用户界面的颜色使用准则。它作为开发者的参考指南，确保 TUI 在不同终端主题下保持一致的视觉体验和可读性。

## 功能点目的

1. **标准化颜色使用**：定义明确的语义化颜色映射（成功、错误、提示等）
2. **确保可访问性**：避免在未知终端主题下使用可能导致对比度问题的颜色
3. **提供实现指导**：与 `clippy.toml` 联动，通过 lint 规则强制执行
4. **维护视觉一致性**：确保所有 UI 组件遵循相同的颜色规范

## 具体技术实现

### 颜色语义映射

#### 前景色规范

| 语义 | ANSI 颜色 | 使用场景 |
|------|----------|---------|
| 默认 | `reset` | 主要文本 |
| 提示/选择/状态 | `cyan` | 用户输入提示、选中项、状态指示器 |
| 成功/添加 | `green` | 成功消息、代码添加 |
| 错误/失败/删除 | `red` | 错误消息、代码删除 |
| Codex 品牌 | `magenta` | AI 生成的内容标识 |
| 次要文本 | `dim` | 辅助信息、元数据 |

#### 标题样式

```markdown
- **Headers:** Use `bold`. For markdown with various header levels, leave in the `#` signs.
- **Primary text:** Default.
- **Secondary text:** Use `dim`.
```

### 禁止使用的颜色

| 颜色 | 原因 | 例外 |
|------|------|------|
| 自定义颜色 | 无法保证在各种终端主题下的对比度 | `shimmer.rs` 使用默认颜色调整亮度 |
| `black` & `white` | 默认终端主题颜色效果更好 | 手动着色背景需要对比时 |
| `blue` | 当前样式指南未使用 | - |
| `yellow` | 当前样式指南未使用 | - |

### 代码实现

样式规范在代码中的实现位置：

```rust
// src/style.rs
pub fn user_message_style() -> Style {
    user_message_style_for(default_bg())
}

pub fn user_message_style_for(terminal_bg: Option<(u8, u8, u8)>) -> Style {
    match terminal_bg {
        Some(bg) => Style::default().bg(user_message_bg(bg)),
        None => Style::default(),
    }
}
```

```rust
// src/color.rs
pub fn blend(top: (u8, u8, u8), bottom: (u8, u8, u8), alpha: f32) -> (u8, u8, u8) {
    // 颜色混合实现，用于 shimmer 效果
}
```

### Lint 规则关联

```toml
# clippy.toml (项目根目录)
# 规则捕获违规颜色使用
```

AGENTS.md 中提到的规则：
> (There are some rules to try to catch this in `clippy.toml`.)

## 关键代码路径与文件引用

### 样式实现文件

| 文件 | 职责 |
|------|------|
| `src/style.rs` | 用户消息、计划提案的样式函数 |
| `src/color.rs` | 颜色混合、亮度检测 |
| `src/terminal_palette.rs` | 终端调色板检测和最佳颜色选择 |
| `src/shimmer.rs` | 动态颜色效果（文档中提到的例外） |

### 使用场景

```
styles.md (规范文档)
    ↓ 指导实现
src/style.rs
    ↓ 提供样式函数
src/chatwidget.rs (用户消息渲染)
src/bottom_pane/*.rs (底部面板组件)
src/status.rs (状态指示器)
```

### Ratatui Stylize Trait 使用

根据 AGENTS.md 的 TUI 代码规范：

```rust
// 推荐方式
"text".into()           // 基本 span
"text".red()            // 红色文本
"text".green()          // 绿色文本
"text".magenta()        // 品红文本 (Codex 品牌色)
"text".dim()            // 暗淡文本 (次要信息)
url.cyan().underlined() // 链接样式

// Line 构建
vec!["  └ ".into(), "M".red(), " ".dim(), "tui/src/app.rs".dim()]
```

## 依赖与外部交互

### 终端能力检测

```rust
// src/terminal_palette.rs
pub fn default_bg() -> Option<(u8, u8, u8)> {
    // 检测终端背景色
}

pub fn best_color(rgb: (u8, u8, u8)) -> Color {
    // 选择终端支持的最佳颜色
}
```

### 颜色系统交互

```
styles.md (规范)
    ↓
codex-core (终端信息检测)
    ↓
ratatui (渲染)
    ↓
crossterm (终端控制)
    ↓
终端模拟器
```

### 跨平台考虑

| 平台 | 颜色支持 |
|------|---------|
| macOS Terminal | 256色 + 真彩色 |
| iTerm2 | 真彩色 |
| Windows Terminal | 真彩色 |
| Linux (各种) | 取决于终端模拟器 |
| VS Code 集成终端 | 真彩色 |

## 风险、边界与改进建议

### 潜在风险

1. **终端兼容性**：旧版终端可能不支持某些 ANSI 序列
2. **主题冲突**：用户自定义终端主题可能与规范颜色冲突
3. **色盲友好性**：仅依赖颜色区分信息可能对色盲用户不友好

### 边界条件

1. **背景色检测失败**：
   ```rust
   // src/style.rs 处理 None 情况
   None => Style::default(),  // 回退到默认
   ```

2. **亮色/暗色主题适配**：
   ```rust
   // src/color.rs
   let (top, alpha) = if is_light(terminal_bg) {
       ((0, 0, 0), 0.04)      // 亮色主题：黑色叠加
   } else {
       ((255, 255, 255), 0.12) // 暗色主题：白色叠加
   };
   ```

### 改进建议

1. **主题感知样式**：
   ```rust
   // 建议：根据检测到的主题类型调整颜色
   pub enum TerminalTheme {
       Light,
       Dark,
       HighContrast,
   }
   ```

2. **图标+颜色双重编码**：
   ```markdown
   - 成功: ✓ + green
   - 错误: ✗ + red
   - 警告: ▲ + yellow (如果未来添加)
   ```

3. **用户自定义主题**：
   ```toml
   # config.toml
   [ui.colors]
   success = "#28a745"
   error = "#dc3545"
   accent = "magenta"
   ```

4. **增强 clippy 规则**：
   ```toml
   # clippy.toml
   # 建议：添加更多颜色使用检查
   disallowed-methods = [
       "ratatui::style::Color::Blue",
       "ratatui::style::Color::Yellow",
   ]
   ```

5. **文档化 shimmer 例外**：
   ```markdown
   <!-- 在 styles.md 中添加 -->
   ## 例外情况
   
   `shimmer.rs` 使用动态颜色调整，通过 `blend()` 函数基于默认颜色
   计算亮度变化，因此不受 "避免自定义颜色" 规则限制。
   ```

6. **对比度检查工具**：
   - 添加开发工具验证颜色组合的可读性
   - 参考 WCAG 对比度标准
