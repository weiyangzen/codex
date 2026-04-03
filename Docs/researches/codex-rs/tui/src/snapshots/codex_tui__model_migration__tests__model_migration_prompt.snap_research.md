# 模型迁移提示界面快照研究文档

## 场景与职责

该快照文件记录了 `codex-rs/tui` 项目中**模型升级提示界面**的渲染结果。当 Codex 检测到用户当前使用的模型有新版本可用时，会显示此交互式提示界面，让用户选择是否升级到新的 AI 模型。这是用户体验的重要组成部分，确保用户能够及时了解并选择最新的模型功能。

**核心职责：**
- 向用户通知可用的模型升级（gpt-5.1-codex-mini → gpt-5.1-codex-max）
- 提供清晰的选择菜单（尝试新模型 / 使用现有模型）
- 处理用户输入（方向键、数字键、回车键）
- 在备用屏幕（alternate screen）中渲染，避免污染主终端滚动历史

## 功能点目的

### 1. 升级通知
- **标题显示**：突出显示新模型名称（"Introducing gpt-5.1-codex-max"）
- **升级说明**：解释升级的好处（"latest and greatest agentic coding model"）
- **回退选项**：明确告知用户可以继续使用当前模型

### 2. 交互式菜单
- **选项展示**：两个明确的选择（1. Try new model / 2. Use existing model）
- **视觉反馈**：当前选中项使用 `›` 符号标记
- **键盘导航**：支持方向键（↑/↓）和数字键（1/2）选择

### 3. 键盘提示
- **操作指引**：底部显示 "Use ↑/↓ to move, press enter to confirm"
- **按键可视化**：使用 `key_hint` 模块渲染按键图标

### 4. 备用屏幕管理
- **AltScreenGuard**：在备用屏幕中渲染提示
- **自动清理**：通过 RAII 模式确保退出时恢复主屏幕

## 具体技术实现

### 核心数据结构

**ModelMigrationOutcome** - 迁移结果枚举：
```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ModelMigrationOutcome {
    Accepted,   // 用户接受升级
    Rejected,   // 用户拒绝升级
    Exit,       // 用户通过 Ctrl+C/D 退出
}
```

**ModelMigrationCopy** - 提示内容结构：
```rust
#[derive(Clone)]
pub(crate) struct ModelMigrationCopy {
    pub heading: Vec<Span<'static>>,    // 标题文本（加粗）
    pub content: Vec<Line<'static>>,    // 内容行
    pub can_opt_out: bool,              // 是否允许拒绝（可选升级）
    pub markdown: Option<String>,       // 可选的 Markdown 内容
}
```

**MigrationMenuOption** - 菜单选项枚举：
```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum MigrationMenuOption {
    TryNewModel,
    UseExistingModel,
}

impl MigrationMenuOption {
    fn all() -> [Self; 2] {
        [Self::TryNewModel, Self::UseExistingModel]
    }

    fn label(self) -> &'static str {
        match self {
            Self::TryNewModel => "Try new model",
            Self::UseExistingModel => "Use existing model",
        }
    }
}
```

### 内容生成逻辑

```rust
pub(crate) fn migration_copy_for_models(
    current_model: &str,
    target_model: &str,
    model_link: Option<String>,
    migration_copy: Option<String>,
    migration_markdown: Option<String>,
    target_display_name: String,
    target_description: Option<String>,
    can_opt_out: bool,
) -> ModelMigrationCopy {
    // 优先使用 Markdown 模板
    if let Some(migration_markdown) = migration_markdown {
        return ModelMigrationCopy {
            heading: Vec::new(),
            content: Vec::new(),
            can_opt_out,
            markdown: Some(fill_migration_markdown(
                &migration_markdown,
                current_model,
                target_model,
            )),
        };
    }

    // 构建标题
    let heading_text = Span::from(format!(
        "Codex just got an upgrade. Introducing {target_display_name}."
    )).bold();

    // 构建内容...
}
```

### 屏幕渲染流程

**ModelMigrationScreen 结构：**
```rust
struct ModelMigrationScreen {
    request_frame: FrameRequester,      // 帧请求器
    copy: ModelMigrationCopy,           // 提示内容
    done: bool,                         // 是否完成
    outcome: ModelMigrationOutcome,     // 结果
    highlighted_option: MigrationMenuOption,  // 当前选中项
}
```

**WidgetRef 实现（渲染）：**
```rust
impl WidgetRef for &ModelMigrationScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);  // 清空区域

        let mut column = ColumnRenderable::new();
        column.push("");
        
        if let Some(markdown) = self.copy.markdown.as_ref() {
            self.render_markdown_content(markdown, area.width, &mut column);
        } else {
            column.push(self.heading_line());
            column.push(Line::from(""));
            self.render_content(&mut column);
        }
        
        if self.copy.can_opt_out {
            self.render_menu(&mut column);
        }

        column.render(area, buf);
    }
}
```

### 键盘事件处理

```rust
fn handle_menu_key(&mut self, code: KeyCode) {
    match code {
        KeyCode::Up | KeyCode::Char('k') => {
            self.highlight_option(MigrationMenuOption::TryNewModel);
        }
        KeyCode::Down | KeyCode::Char('j') => {
            self.highlight_option(MigrationMenuOption::UseExistingModel);
        }
        KeyCode::Char('1') => {
            self.highlight_option(MigrationMenuOption::TryNewModel);
            self.accept();
        }
        KeyCode::Char('2') => {
            self.highlight_option(MigrationMenuOption::UseExistingModel);
            self.reject();
        }
        KeyCode::Enter | KeyCode::Esc => self.confirm_selection(),
        _ => {}
    }
}
```

### 备用屏幕管理

```rust
struct AltScreenGuard<'a> {
    tui: &'a mut Tui,
}

impl<'a> AltScreenGuard<'a> {
    fn enter(tui: &'a mut Tui) -> Self {
        let _ = tui.enter_alt_screen();
        Self { tui }
    }
}

impl Drop for AltScreenGuard<'_> {
    fn drop(&mut self) {
        let _ = self.tui.leave_alt_screen();
    }
}
```

## 关键代码路径与文件引用

### 主要源文件

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/model_migration.rs` | 模型迁移提示的完整实现 |

### 关键函数路径

```
model_migration.rs:422
└── fn prompt_snapshot()  [测试函数]
    └── migration_copy_for_models()  [model_migration.rs:61]
        │   // 构建 ModelMigrationCopy
        └── ModelMigrationScreen::new(request_frame, copy)  [model_migration.rs:180]
            └── frame.render_widget_ref(&screen, frame.area())  [model_migration.rs:449]
                └── WidgetRef::render_ref()  [model_migration.rs:252]
                    ├── render_markdown_content()  [可选]
                    ├── render_content()  [model_migration.rs:301]
                    └── render_menu()  [model_migration.rs:341]
                        └── selection_option_row()  [selection_list.rs]
```

### 测试相关代码

```rust
#[test]
fn prompt_snapshot() {
    let width: u16 = 60;
    let height: u16 = 28;
    let backend = VT100Backend::new(width, height);
    let mut terminal = Terminal::with_options(backend).expect("terminal");
    terminal.set_viewport_area(Rect::new(0, 0, width, height));

    let screen = ModelMigrationScreen::new(
        FrameRequester::test_dummy(),
        migration_copy_for_models(
            "gpt-5.1-codex-mini",           // current_model
            "gpt-5.1-codex-max",            // target_model
            None,                           // model_link
            Some("Upgrade to gpt-5.2-codex for the latest and greatest agentic coding model.".to_string()),  // migration_copy
            None,                           // migration_markdown
            "gpt-5.1-codex-max".to_string(), // target_display_name
            Some("Codex-optimized flagship for deep and fast reasoning.".to_string()),  // target_description
            true,                           // can_opt_out
        ),
    );

    {
        let mut frame = terminal.get_frame();
        frame.render_widget_ref(&screen, frame.area());
    }
    terminal.flush().expect("flush");

    assert_snapshot!("model_migration_prompt", terminal.backend());
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 渲染框架 |
| `crossterm` | 跨平台终端事件处理（键盘输入） |
| `tokio-stream` | 异步事件流处理 |

### 内部模块交互

```
model_migration.rs
├── markdown_render::render_markdown_text_with_width  [Markdown 渲染]
├── render::renderable::{ColumnRenderable, Renderable, RenderableExt}  [渲染抽象]
├── render::Insets  [内边距]
├── selection_list::selection_option_row  [选项行渲染]
├── tui::{FrameRequester, Tui, TuiEvent}  [TUI 核心]
└── key_hint  [按键提示渲染]
```

### 样式应用

| 元素 | 样式 |
|-----|------|
| 标题 | `bold()` |
| 选中标记 `›` | 默认 |
| 未选中项 | 默认 |
| 按键提示 | `dim()`（暗淡） |
| 链接 | `cyan().underlined()` |

## 风险、边界与改进建议

### 已知风险

1. **终端尺寸限制**
   - 在极窄终端（< 40 列）中，菜单可能显示不完整
   - 风险：长模型名称或描述可能被截断
   - 缓解：使用 `Wrap { trim: false }` 进行文本换行

2. **键盘事件冲突**
   - `Esc` 键同时用于接受提示和退出
   - 行为：在非可选升级中，`Esc` 接受提示；在可选升级中，`Esc` 也接受提示
   - 潜在混淆：用户可能期望 `Esc` 取消操作

3. **备用屏幕残留**
   - 如果进程异常终止，备用屏幕可能未正确清理
   - 缓解：`AltScreenGuard` 的 `Drop` 实现确保清理

### 边界情况

1. **强制升级（can_opt_out = false）**
   - 不显示菜单，仅显示 "Press enter to continue"
   - 测试覆盖：`prompt_snapshot_gpt5_family` 等

2. **Markdown 内容**
   - 支持通过 `migration_markdown` 提供完整 Markdown 内容
   - 测试覆盖：`markdown_prompt_keeps_long_url_tail_visible_when_narrow`

3. **空内容处理**
   - 当 `migration_copy` 为 `None` 时，使用默认描述
   - 当 `target_description` 为空时，使用通用描述

### 改进建议

1. **可访问性**
   - 添加对屏幕阅读器的支持（如 ANSI 转义序列）
   - 考虑添加高对比度模式

2. **国际化**
   - 当前所有文本硬编码为英文
   - 建议：添加本地化支持

3. **键盘导航增强**
   - 添加 `h/j/k/l` 导航支持（Vim 风格）
   - 支持 `Ctrl+N` / `Ctrl+P` 切换选项

4. **视觉反馈**
   - 为选中项添加背景色高亮
   - 考虑添加颜色盲友好的指示器

5. **超时机制**
   - 当前提示等待用户无限期输入
   - 建议：添加可选的超时自动接受机制

6. **测试覆盖**
   - 添加对终端尺寸变化的测试
   - 添加对颜色主题变化的测试
