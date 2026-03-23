# model_migration.rs 深入研究

## 场景与职责

`model_migration.rs` 是 Codex TUI 中负责**模型升级提示**的模块。当检测到用户使用的模型有新版本可用时，显示交互式提示引导用户升级。这是产品引导用户采用最新模型能力的关键入口。

### 核心场景

1. **模型版本检测**：系统检测到当前模型有新版本（如 gpt-5 → gpt-5.1）
2. **升级引导提示**：显示美观的交互式提示，介绍新模型优势
3. **用户选择处理**：支持用户选择升级或继续使用现有模型
4. **强制升级场景**：某些情况下不允许用户选择（如重大安全更新）

### 升级类型

| 类型 | 说明 | 示例 |
|------|------|------|
| 可选升级 | 用户可以选择升级或保持现状 | gpt-5-codex-mini → gpt-5.1-codex-mini |
| 强制升级 | 用户必须确认才能继续 | gpt-5 → gpt-5.1 |

## 功能点目的

### 1. ModelMigrationOutcome - 结果枚举

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ModelMigrationOutcome {
    Accepted,   // 用户接受升级
    Rejected,   // 用户拒绝升级（仅可选场景）
    Exit,       // 用户通过 Ctrl+C/D 退出
}
```

### 2. ModelMigrationCopy - 提示内容

```rust
#[derive(Clone)]
pub(crate) struct ModelMigrationCopy {
    pub heading: Vec<Span<'static>>,      // 标题（粗体）
    pub content: Vec<Line<'static>>,      // 内容行
    pub can_opt_out: bool,                // 是否允许拒绝
    pub markdown: Option<String>,         // 可选的 Markdown 内容
}
```

### 3. MigrationMenuOption - 菜单选项

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum MigrationMenuOption {
    TryNewModel,       // "Try new model"
    UseExistingModel,  // "Use existing model"
}
```

### 4. 核心函数

#### `migration_copy_for_models(...)` - 生成提示内容

根据参数生成结构化的提示内容：
- 支持自定义 Markdown 模板
- 支持自定义文案
- 支持模型链接
- 自动处理可选/强制升级的差异文案

#### `run_model_migration_prompt(...)` - 运行提示

异步函数，显示提示并等待用户输入：
- 进入备用屏幕（AltScreen）
- 处理键盘事件
- 返回用户选择结果

## 具体技术实现

### 提示内容生成流程

```rust
pub(crate) fn migration_copy_for_models(
    current_model: &str,           // 当前模型
    target_model: &str,            // 目标模型
    model_link: Option<String>,    // 模型详情链接
    migration_copy: Option<String>, // 自定义文案
    migration_markdown: Option<String>, // Markdown 模板
    target_display_name: String,   // 显示名称
    target_description: Option<String>, // 模型描述
    can_opt_out: bool,             // 是否可拒绝
) -> ModelMigrationCopy
```

**文案优先级**：
1. 如果提供 `migration_markdown`，使用模板渲染
2. 如果提供 `migration_copy`，使用自定义文案
3. 否则使用默认文案

**默认文案结构**：
```
Codex just got an upgrade. Introducing {target_display_name}.

We recommend switching from {current_model} to {target_model}.

{description} Learn more about {target_display_name} at {link}.

[You can continue using {current_model} if you prefer.]  // 仅可选时
[Press enter to continue]  // 仅强制时
```

### UI 渲染结构

```
┌─────────────────────────────────────┐
│                                     │
│  > Codex just got an upgrade...     │  // 标题（引用样式）
│                                     │
│    We recommend switching...        │  // 内容（2空格缩进）
│                                     │
│    Description...                   │
│    Learn more at https://...        │  // 链接（青色下划线）
│                                     │
│    You can continue using...        │  // 可选升级提示
│                                     │
│  [ LM Studio ]  [ Ollama ]          │  // 选择按钮（仅可选）
│                                     │
│    Use ↑/↓ to move...               │  // 操作提示
│                                     │
└─────────────────────────────────────┘
```

### 键盘事件处理

```rust
fn handle_menu_key(&mut self, code: KeyCode) {
    match code {
        KeyCode::Up | KeyCode::Char('k') => 选择上一个
        KeyCode::Down | KeyCode::Char('j') => 选择下一个
        KeyCode::Char('1') => 选择并确认升级
        KeyCode::Char('2') => 选择并拒绝升级
        KeyCode::Enter | KeyCode::Esc => 确认当前选择
    }
}
```

### 备用屏幕管理

```rust
struct AltScreenGuard<'a> {
    tui: &'a mut Tui,
}

impl<'a> AltScreenGuard<'_> {
    fn enter(tui: &'a mut Tui) -> Self {
        let _ = tui.enter_alt_screen();
        Self { tui }
    }
}

impl Drop for AltScreenGuard<'_> {
    fn drop(&mut self) {
        let _ = self.tui.leave_alt_screen();  // 确保退出时恢复
    }
}
```

## 关键代码路径

### 1. 内容生成路径（行 60-135）

```rust
pub(crate) fn migration_copy_for_models(...) -> ModelMigrationCopy {
    // Markdown 模板优先
    if let Some(migration_markdown) = migration_markdown {
        return ModelMigrationCopy {
            markdown: Some(fill_migration_markdown(...)),
            ...
        };
    }
    
    // 构建标题
    let heading_text = Span::from(format!("...{target_display_name}...")).bold();
    
    // 构建内容
    let mut content = vec![];
    // ... 添加各段落
    
    ModelMigrationCopy { heading, content, can_opt_out, markdown: None }
}
```

### 2. 提示运行路径（行 137-169）

```rust
pub(crate) async fn run_model_migration_prompt(
    tui: &mut Tui,
    copy: ModelMigrationCopy,
) -> ModelMigrationOutcome {
    let alt = AltScreenGuard::enter(tui);  // 进入备用屏幕
    let mut screen = ModelMigrationScreen::new(alt.tui.frame_requester(), copy);
    
    // 初始渲染
    let _ = alt.tui.draw(u16::MAX, |frame| {
        frame.render_widget_ref(&screen, frame.area());
    });
    
    // 事件循环
    while !screen.is_done() {
        if let Some(event) = events.next().await {
            match event {
                TuiEvent::Key(key_event) => screen.handle_key(key_event),
                TuiEvent::Draw => { /* 重绘 */ }
                _ => {}
            }
        }
    }
    
    screen.outcome()
}
```

### 3. 渲染路径（行 252-270, 273-375）

```rust
impl WidgetRef for &ModelMigrationScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);  // 清屏
        
        let mut column = ColumnRenderable::new();
        if let Some(markdown) = self.copy.markdown.as_ref() {
            self.render_markdown_content(markdown, area.width, &mut column);
        } else {
            column.push(self.heading_line());
            self.render_content(&mut column);
        }
        if self.copy.can_opt_out {
            self.render_menu(&mut column);  // 可选时显示菜单
        }
        
        column.render(area, buf);
    }
}
```

## 依赖与外部交互

### 直接依赖

| 模块 | 用途 |
|------|------|
| `crate::key_hint` | 键盘提示显示 |
| `crate::markdown_render` | Markdown 渲染 |
| `crate::render` | 渲染辅助（Insets, Renderable） |
| `crate::selection_list` | 选择列表行渲染 |
| `crate::tui::{Tui, TuiEvent, FrameRequester}` | TUI 核心 |
| `crossterm::event` | 键盘事件 |
| `ratatui` | 终端 UI 渲染 |

### 依赖模块详情

```rust
use crate::key_hint;
use crate::markdown_render::render_markdown_text_with_width;
use crate::render::Insets;
use crate::render::renderable::{ColumnRenderable, Renderable, RenderableExt};
use crate::selection_list::selection_option_row;
use crate::tui::{FrameRequester, Tui, TuiEvent};
```

### 被调用方

- **应用初始化**：检测模型版本后调用
- **配置管理**：根据用户选择更新默认模型

## 风险、边界与改进建议

### 已知风险

1. **备用屏幕泄漏**：
   - 虽然使用 `AltScreenGuard` 确保恢复，但 panic 时可能泄漏
   - 建议添加 panic hook 处理

2. **事件流中断**：
   - 如果 `events.next().await` 返回 `None`，会自动接受
   - 可能不符合用户预期

3. **Markdown 渲染宽度**：
   - 窄屏幕下长 URL 可能被截断
   - 测试用例 `markdown_prompt_keeps_long_url_tail_visible_when_narrow` 专门验证此场景

### 边界情况处理

| 场景 | 处理方式 |
|------|----------|
| `can_opt_out = false` | 隐藏菜单，Esc/Enter 都接受 |
| Markdown 模板为空 | 回退到默认文案 |
| 描述为空 | 使用默认描述 |
| 窗口大小变化 | 通过 Draw 事件重绘 |
| Ctrl+C/D | 触发 Exit 结果 |

### 测试覆盖

模块包含 7 个测试用例：

1. **`prompt_snapshot`** - 基础提示快照测试
2. **`prompt_snapshot_gpt5_family`** - GPT-5 系列升级提示
3. **`prompt_snapshot_gpt5_codex`** - GPT-5 Codex 升级提示
4. **`prompt_snapshot_gpt5_codex_mini`** - GPT-5 Codex Mini 升级提示
5. **`escape_key_accepts_prompt`** - Esc 键接受行为
6. **`selecting_use_existing_model_rejects_upgrade`** - 拒绝升级选择
7. **`markdown_prompt_keeps_long_url_tail_visible_when_narrow`** - 窄屏 URL 可见性

### 改进建议

1. **动画支持**：添加淡入/滑动动画提升体验
2. **富媒体支持**：支持显示模型能力对比图表
3. **A/B 测试框架**：支持不同文案的效果对比
4. **国际化**：当前硬编码英文，需 i18n 支持
5. **无障碍**：添加屏幕阅读器支持
6. **历史记录**：记录用户选择用于产品分析
7. **定时关闭**：可选的自动接受倒计时

## 文件引用汇总

- **本文件**：`codex-rs/tui/src/model_migration.rs` (627 lines)
- **键盘提示**：`codex-rs/tui/src/key_hint.rs`
- **Markdown 渲染**：`codex-rs/tui/src/markdown_render.rs`
- **渲染辅助**：`codex-rs/tui/src/render/`
- **选择列表**：`codex-rs/tui/src/selection_list.rs`
- **TUI 核心**：`codex-rs/tui/src/tui.rs`
