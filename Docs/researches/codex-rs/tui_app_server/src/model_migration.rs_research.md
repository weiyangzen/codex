# model_migration.rs 深入研究

## 场景与职责

`model_migration.rs` 是 Codex TUI 中负责**模型升级提示**的模块，当检测到用户正在使用旧版或推荐的模型时，显示交互式提示引导用户切换到新模型。

### 核心场景

1. **模型升级引导**：当 Codex 检测到用户使用的是旧模型（如 `gpt-5` → `gpt-5.1`），显示升级提示
2. **新功能介绍**：向用户介绍新模型的优势和特性
3. **用户选择**：允许用户选择尝试新模型或继续使用现有模型（如果配置允许）

### 使用场景示例

- GPT-5 系列升级：gpt-5 → gpt-5.1
- Codex 专用模型：gpt-5-codex → gpt-5.1-codex-max
- Mini 版本：gpt-5-codex-mini → gpt-5.1-codex-mini

## 功能点目的

### 1. 迁移结果枚举

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ModelMigrationOutcome {
    Accepted,   // 用户接受升级
    Rejected,   // 用户拒绝升级（选择继续使用现有模型）
    Exit,       // 用户退出（Ctrl+C/D）
}
```

### 2. 迁移文案结构

```rust
#[derive(Clone)]
pub(crate) struct ModelMigrationCopy {
    pub heading: Vec<Span<'static>>,      // 标题（粗体显示）
    pub content: Vec<Line<'static>>,      // 内容行
    pub can_opt_out: bool,                // 是否允许拒绝
    pub markdown: Option<String>,         // 可选的Markdown内容（覆盖默认渲染）
}
```

### 3. 文案生成函数

```rust
pub(crate) fn migration_copy_for_models(
    current_model: &str,           // 当前模型名称
    target_model: &str,            // 目标模型名称
    model_link: Option<String>,    // 模型详情链接
    migration_copy: Option<String>, // 自定义迁移文案
    migration_markdown: Option<String>, // 自定义Markdown模板
    target_display_name: String,   // 目标模型显示名称
    target_description: Option<String>, // 目标模型描述
    can_opt_out: bool,             // 是否允许选择不升级
) -> ModelMigrationCopy
```

**文案生成逻辑**：
1. 如果提供了 `migration_markdown`，直接使用（支持 `{model_from}` 和 `{model_to}` 占位符）
2. 否则生成默认文案：
   - 标题："Codex just got an upgrade. Introducing {target}."
   - 描述：自定义或默认描述
   - 推荐语：建议从当前模型切换到目标模型
   - 链接：可选的模型详情链接
   - 操作提示：根据 `can_opt_out` 显示不同提示

### 4. 交互式提示界面

```rust
pub(crate) async fn run_model_migration_prompt(
    tui: &mut Tui,
    copy: ModelMigrationCopy,
) -> ModelMigrationOutcome
```

**界面特点**：
- 使用备用屏幕（alternate screen），不污染主终端滚动历史
- 支持键盘导航（上下箭头、j/k、数字键1/2）
- 支持 Esc/Enter 确认
- 使用 ratatui 渲染，支持样式和布局

### 5. 菜单选项

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum MigrationMenuOption {
    TryNewModel,      // "Try new model"
    UseExistingModel, // "Use existing model"
}
```

## 具体技术实现

### 1. 备用屏幕保护

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
        let _ = self.tui.leave_alt_screen();  // 确保退出时恢复
    }
}
```

使用 RAII 模式确保即使发生 panic，也能恢复终端状态。

### 2. 键盘事件处理

```rust
fn handle_key(&mut self, key_event: KeyEvent) {
    if key_event.kind == KeyEventKind::Release {
        return;
    }

    if is_ctrl_exit_combo(key_event) {
        self.exit();
        return;
    }

    if self.copy.can_opt_out {
        self.handle_menu_key(key_event.code);
    } else if matches!(key_event.code, KeyCode::Esc | KeyCode::Enter) {
        self.accept();
    }
}
```

**快捷键映射**：
- `Ctrl+C` / `Ctrl+D`：退出
- `↑` / `k`：选择"Try new model"
- `↓` / `j`：选择"Use existing model"
- `1`：选择并确认"Try new model"
- `2`：选择并确认"Use existing model"
- `Enter` / `Esc`：确认当前选择

### 3. Markdown 内容渲染

```rust
fn render_markdown_content(
    &self,
    markdown: &str,
    area_width: u16,
    column: &mut ColumnRenderable,
) {
    let horizontal_inset = 2;
    let content_width = area_width.saturating_sub(horizontal_inset);
    let wrap_width = (content_width > 0).then_some(content_width as usize);
    let rendered = render_markdown_text_with_width(markdown, wrap_width);
    // ... 渲染到 column
}
```

支持 Markdown 模板，自动换行以适应终端宽度。

### 4. 菜单渲染

```rust
fn render_menu(&self, column: &mut ColumnRenderable) {
    // 显示选项按钮（带高亮背景）
    // 显示操作提示（"Use ↑/↓ to move, press Enter to confirm"）
}
```

使用 ratatui 的样式系统：
- 选中项：青色背景 + 黑色文字
- 未选中项：深灰色背景

## 关键代码路径与文件引用

### 直接依赖

| 文件/模块 | 依赖类型 | 用途 |
|-----------|----------|------|
| `key_hint` | 同级模块 | 键盘快捷键提示渲染 |
| `markdown_render` | 同级模块 | Markdown文本渲染 |
| `render/renderable` | 同级模块 | 可渲染组件trait |
| `selection_list` | 同级模块 | 选择列表行渲染 |
| `tui` | 同级模块 | TUI事件和帧请求 |
| `crossterm::event` | 外部crate | 键盘事件处理 |
| `ratatui` | 外部crate | UI渲染 |

### 调用方

| 文件 | 使用方式 |
|------|----------|
| `app.rs` | 导入 `ModelMigrationOutcome`, `migration_copy_for_models`, `run_model_migration_prompt` |
| `tui/src/app.rs` | TUI主模块使用（如果有） |

### 在 app.rs 中的使用

```rust
// app.rs
use crate::model_migration::ModelMigrationOutcome;
use crate::model_migration::migration_copy_for_models;
use crate::model_migration::run_model_migration_prompt;

// 在模型升级检测逻辑中
let copy = migration_copy_for_models(
    current_model,
    target_model,
    model_link,
    migration_copy,
    migration_markdown,
    target_display_name,
    target_description,
    can_opt_out,
);
let outcome = run_model_migration_prompt(tui, copy).await;
match outcome {
    ModelMigrationOutcome::Accepted => { /* 切换到新模型 */ }
    ModelMigrationOutcome::Rejected => { /* 继续使用当前模型 */ }
    ModelMigrationOutcome::Exit => { /* 退出应用 */ }
}
```

## 依赖与外部交互

### 外部crate依赖

```rust
use crossterm::event::KeyCode;
use crossterm::event::KeyEvent;
use crossterm::event::KeyEventKind;
use crossterm::event::KeyModifiers;
use ratatui::prelude::Stylize as _;
use ratatui::prelude::Widget;
use ratatui::text::Line;
use ratatui::text::Span;
use ratatui::widgets::Clear;
use ratatui::widgets::Paragraph;
use ratatui::widgets::WidgetRef;
use ratatui::widgets::Wrap;
use tokio_stream::StreamExt;
```

### 配置标志

迁移提示的显示由配置控制：

```rust
// core/src/models_manager/model_presets.rs
pub const HIDE_GPT5_1_MIGRATION_PROMPT_CONFIG: &str = "hide_gpt5_1_migration_prompt";
pub const HIDE_GPT_5_1_CODEX_MAX_MIGRATION_PROMPT_CONFIG: &str =
    "hide_gpt-5.1-codex-max_migration_prompt";
```

### 与模型配置的集成

```rust
// protocol/src/openai_models.rs
pub struct ModelUpgrade {
    pub target_model: String,
    pub target_display_name: String,
    pub target_description: Option<String>,
    pub model_link: Option<String>,
    pub migration_copy: Option<String>,
    pub migration_markdown: Option<String>,
    pub can_opt_out: bool,
}
```

## 风险、边界与改进建议

### 已知风险

1. **备用屏幕依赖**：如果终端不支持备用屏幕，提示可能显示异常
2. **事件循环阻塞**：`run_model_migration_prompt` 是同步阻塞的异步函数，会暂停其他UI更新
3. **硬编码快捷键**：快捷键映射硬编码，不支持用户自定义

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| `can_opt_out = false` | 不显示菜单，只显示"Press enter to continue" |
| Markdown模板超长 | 使用 `word_wrap` 自动换行 |
| 终端宽度很窄 | 保持水平内边距2，内容区域自适应 |
| 用户按 Ctrl+C | 触发 `Exit` 结果，上层决定如何处理 |
| 空描述 | 使用默认描述："{target} is recommended for better performance and reliability." |

### 改进建议

1. **可访问性**：
   - 添加屏幕阅读器支持（使用适当的ANSI转义序列）
   - 支持高对比度模式

2. **国际化**：
   - 将文案模板化，支持多语言
   - 快捷键提示本地化

3. **用户体验**：
   - 添加"不再询问"选项，记住用户选择
   - 支持在提示中显示模型对比表格
   - 添加动画效果（如打字机效果显示文案）

4. **配置扩展**：
   - 支持用户自定义迁移提示文案
   - 支持配置默认选择（新模型或现有模型）

5. **测试覆盖**：
   - 当前有快照测试，但可添加：
     - 键盘交互测试
     - 不同终端尺寸的自适应测试
     - 边界情况测试（空文案、超长文案等）

6. **代码质量**：
   - `migration_copy_for_models` 函数参数过多（8个），考虑使用 builder 模式
   - 提取常量字符串到配置或资源文件

### 相关测试

文件包含全面的测试套件：

**快照测试**：
- `prompt_snapshot`：基本提示界面
- `prompt_snapshot_gpt5_family`：GPT-5系列升级
- `prompt_snapshot_gpt5_codex`：Codex模型升级
- `prompt_snapshot_gpt5_codex_mini`：Mini版本升级

**行为测试**：
- `escape_key_accepts_prompt`：Esc键接受
- `selecting_use_existing_model_rejects_upgrade`：选择现有模型
- `markdown_prompt_keeps_long_url_tail_visible_when_narrow`：窄终端URL显示

**快照文件**：
- `codex_tui_app_server__model_migration__tests__model_migration_prompt.snap`
- `codex_tui_app_server__model_migration__tests__model_migration_prompt_gpt5_family.snap`
- `codex_tui_app_server__model_migration__tests__model_migration_prompt_gpt5_codex.snap`
- `codex_tui_app_server__model_migration__tests__model_migration_prompt_gpt5_codex_mini.snap`
