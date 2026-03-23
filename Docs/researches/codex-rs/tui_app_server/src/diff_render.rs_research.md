# diff_render.rs 研究文档

## 场景与职责

`diff_render.rs` 是 Codex TUI 应用服务器中负责**统一差异（Unified Diff）渲染**的核心模块。它处理代码变更的可视化展示，包括：

1. **文件变更展示**：将 `FileChange` 协议类型（Add/Delete/Update）渲染为带行号、分隔符和可选语法高亮的差异块
2. **主题感知渲染**：根据终端背景色（深色/浅色）自适应调整差异配色方案
3. **语法高亮集成**：对支持的文件类型使用 syntect 进行代码语法高亮
4. **多终端兼容**：支持 TrueColor、ANSI-256、ANSI-16 三种颜色深度的终端

该模块在以下场景被调用：
- 用户查看代码补丁（ApplyPatch 审批流程）
- 主题选择器预览差异样式
- 历史记录单元格展示文件变更

---

## 功能点目的

### 1. 差异渲染核心功能

| 功能 | 目的 |
|------|------|
| `render_change` | 将单个 `FileChange` 渲染为带样式的行列表 |
| `create_diff_summary` | 生成多文件变更的汇总视图 |
| `DiffSummary` | 封装变更集合，实现 `Renderable` trait 用于 TUI 展示 |

### 2. 主题与配色系统

| 组件 | 用途 |
|------|------|
| `DiffTheme` | 区分深色/浅色终端主题 |
| `DiffColorLevel` | 表示渲染器支持的颜色深度（TrueColor/ANSI256/ANSI16） |
| `RichDiffColorLevel` | 支持背景色的颜色深度子集 |
| `ResolvedDiffBackgrounds` | 预解析的插入/删除行背景色 |

### 3. 语法高亮策略

- **Add/Delete 文件**：整文件内容作为单个块高亮
- **Update 文件**：按 hunk 分块高亮，保持跨行语法状态（如多行字符串、块注释）
- **大文件保护**：超过 10,000 行或字节限制时跳过语法高亮，避免性能问题

### 4. 文本换行处理

- 支持 Unicode 宽字符（CJK）和制表符（TAB_WIDTH=4）
- 长行自动硬换行，保持语法高亮样式跨行继承
- 使用 `wrap_styled_spans` 实现精确的列宽控制

---

## 具体技术实现

### 关键数据结构

```rust
/// 差异行类型分类
pub(crate) enum DiffLineType {
    Insert,  // + 添加行
    Delete,  // - 删除行
    Context, //   上下文行
}

/// 主题类型
enum DiffTheme {
    Dark,   // 深色终端
    Light,  // 浅色终端
}

/// 颜色深度
enum DiffColorLevel {
    TrueColor,
    Ansi256,
    Ansi16,
}

/// 渲染样式上下文（每帧预计算）
pub(crate) struct DiffRenderStyleContext {
    theme: DiffTheme,
    color_level: DiffColorLevel,
    diff_backgrounds: ResolvedDiffBackgrounds,
}
```

### 配色方案常量

```rust
// TrueColor 深色主题
const DARK_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (33, 58, 43);   // #213A2B 绿色
const DARK_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (74, 34, 29);   // #4A221D 红色

// TrueColor 浅色主题（GitHub 风格）
const LIGHT_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (218, 251, 225); // #dafbe1
const LIGHT_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (255, 235, 233); // #ffebe9

// ANSI-256 索引
const DARK_256_ADD_LINE_BG_IDX: u8 = 22;
const DARK_256_DEL_LINE_BG_IDX: u8 = 52;
```

### 核心渲染流程

```
render_change(change, out_lines, width, lang)
├── FileChange::Add { content }
│   ├── highlight_code_to_styled_spans(content, lang)  // 语法高亮
│   └── 逐行调用 push_wrapped_diff_line_inner_with_theme_and_color_level
├── FileChange::Delete { content }
│   └── 同上，使用 DiffLineType::Delete
└── FileChange::Update { unified_diff, .. }
    ├── diffy::Patch::from_str(unified_diff)  // 解析统一差异格式
    ├── 检查大小限制 exceeds_highlight_limits()
    ├── 逐 hunk 处理
    │   ├── hunk 间插入 "⋮" 分隔符
    │   ├── 按 hunk 高亮（保持解析器状态）
    │   └── 逐行渲染 Insert/Delete/Context
    └── 行号追踪（old_ln / new_ln）
```

### Windows Terminal 特殊处理

```rust
fn diff_color_level_for_terminal(
    stdout_level: StdoutColorLevel,
    terminal_name: TerminalName,
    has_wt_session: bool,           // WT_SESSION 环境变量
    has_force_color_override: bool, // FORCE_COLOR 环境变量
) -> DiffColorLevel
```

- Windows Terminal 支持 TrueColor 但 `supports-color` 可能报告 ANSI-16
- 检测到 `WT_SESSION` 时自动提升到 TrueColor
- `FORCE_COLOR` 可覆盖此行为

### 样式应用策略

| 元素 | 深色主题 | 浅色主题 |
|------|----------|----------|
| 插入行背景 | #213A2B 绿色 | #dafbe1 淡绿 |
| 删除行背景 | #4A221D 红色 | #ffebe9 淡红 |
| 行号列 | DIM 修饰符 | 独立背景色（#aceebb/#ffcecb）|
| 符号 (+/-) | 继承行样式 | 仅前景色（绿/红）|
| 删除行内容 | DIM 修饰符 | 正常 |

---

## 关键代码路径与文件引用

### 本文件内关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `current_diff_render_style_context` | 214-223 | 每帧预计算样式上下文 |
| `resolve_diff_backgrounds` | 198-203 | 解析主题背景色 |
| `render_change` | 474-736 | 核心差异渲染逻辑 |
| `create_diff_summary` | 345-352 | 生成差异汇总 |
| `wrap_styled_spans` | 951-1020 | 样式化文本换行 |
| `push_wrapped_diff_line_inner_with_theme_and_color_level` | 838-938 | 单行差异渲染 |
| `display_path_for` | 741-762 | 路径显示优化（相对路径/~展开） |
| `calculate_add_remove_from_diff` | 764-779 | 统计添加/删除行数 |

### 样式辅助函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `style_line_bg_for` | 1140-1150 | 行背景样式 |
| `style_gutter_for` | 1199-1219 | 行号列样式 |
| `style_sign_add/style_sign_del` | 1224-1245 | 符号样式 |
| `style_add/style_del` | 1258-1300 | 内容样式 |

### 测试覆盖

- **单元测试**：1306-2426 行，包含 40+ 个测试用例
- **快照测试**：使用 `insta` 验证 UI 输出
- **主题测试**：验证深色/浅色/ANSI16 模式渲染
- **换行测试**：验证 Unicode 宽字符和制表符处理
- **性能测试**：大文件（10k+ 行）跳过高亮逻辑

---

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `diffy` | 统一差异格式解析（`Patch`, `Hunk`, `Line`） |
| `ratatui` | TUI 渲染（`Buffer`, `Rect`, `Style`, `Line`, `Span`） |
| `unicode-width` | Unicode 字符显示宽度计算 |
| `syntect` (间接) | 语法高亮通过 `crate::render::highlight` 模块 |

### 内部模块依赖

| 模块 | 用途 |
|------|------|
| `crate::color` | `is_light`, `perceptual_distance` 颜色工具 |
| `crate::exec_command::relativize_to_home` | 路径简化 |
| `crate::render::highlight` | 语法高亮接口 |
| `crate::render::Insets`, `crate::render::renderable` | 渲染布局 |
| `crate::render::line_utils::prefix_lines` | 行前缀工具 |
| `crate::terminal_palette` | 终端颜色能力检测 |
| `codex_core::git_info::get_git_repo_root` | Git 仓库检测 |
| `codex_core::terminal::terminal_info` | 终端信息 |
| `codex_protocol::protocol::FileChange` | 协议类型 |

### 调用方

| 文件 | 用途 |
|------|------|
| `app.rs` | `DiffSummary` 渲染、路径显示 |
| `approval_overlay.rs` | 补丁审批展示 |
| `chatwidget.rs` | 历史记录差异展示 |
| `theme_picker.rs` | 主题预览 |
| `history_cell.rs` | 历史单元格差异 |

---

## 风险、边界与改进建议

### 已知风险

1. **性能风险**
   - 超大差异文件（>10k 行）已做保护，但极端情况仍可能影响帧率
   - 语法高亮在 hunk 级别进行，跨 hunk 状态不保持（设计取舍）

2. **兼容性风险**
   - ANSI-16 终端不支持背景色，依赖前景色区分
   - 某些终端对 TrueColor 支持检测不准确（已针对 Windows Terminal 优化）

3. **路径处理**
   - `display_path_for` 依赖 Git 仓库检测，非 Git 项目使用 ~ 展开
   - Windows 路径分隔符处理依赖标准库

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 空文件添加/删除 | 正常渲染，行号为 0 |
| 无法解析的 diff | 返回 (0, 0) 统计，静默跳过 |
| 重命名文件 | 使用目标扩展名进行语法高亮 |
| 无扩展名文件 | 跳过语法高亮 |
| CJK 宽字符 | 使用 `UnicodeWidthChar` 正确计算列宽 |
| 制表符 | 固定 4 列宽度处理 |

### 改进建议

1. **性能优化**
   - 考虑对超大文件使用虚拟滚动，避免一次性渲染所有行
   - 缓存语法高亮结果，避免重复计算

2. **功能增强**
   - 支持更多差异格式（如 side-by-side）
   - 添加差异折叠/展开交互
   - 支持自定义配色方案配置

3. **可维护性**
   - 文件超过 2400 行，可考虑将测试模块拆分到单独文件
   - 样式常量可提取到主题配置模块

4. **测试覆盖**
   - 添加更多边界情况测试（如空 hunk、二进制文件标记）
   - 增加终端模拟测试，验证实际颜色输出

---

## 代码统计

- **总行数**：约 2426 行
- **代码行**：约 1300 行（不含测试和注释）
- **测试行**：约 1126 行（1306-2426）
- **主要结构体**：8 个
- **主要函数**：30+ 个
- **单元测试**：40+ 个
