# Model Migration Prompt - GPT-5 Codex 快照研究文档

## 快照文件信息

- **文件名**: `codex_tui__model_migration__tests__model_migration_prompt_gpt5_codex.snap`
- **源文件**: `tui/src/model_migration.rs`
- **测试函数**: `prompt_snapshot_gpt5_codex`

---

## 场景与职责

### 业务场景
此快照捕获了 **Codex CLI 模型升级提示界面** 的渲染输出，具体针对从 `gpt-5-codex` 迁移到 `gpt-5.1-codex-max` 的场景。

### 用户场景
当用户当前使用的模型是 `gpt-5-codex` 时，系统检测到存在更新的推荐模型 `gpt-5.1-codex-max`，会弹出此提示界面引导用户升级。

### 核心职责
1. **模型升级通知**: 告知用户有新版本模型可用
2. **迁移建议**: 推荐从当前模型切换到新模型
3. **模型特性说明**: 展示新模型的优势描述
4. **用户决策**: 收集用户是否愿意升级的选择

---

## 功能点目的

### 1. 升级提示展示
```
> Codex just got an upgrade. Introducing gpt-5.1-codex-max.
```
- 使用 `>` 符号和粗体样式突出显示标题
- 明确告知用户有新模型 `gpt-5.1-codex-max` 可用

### 2. 迁移路径说明
```
  We recommend switching from gpt-5-codex to
  gpt-5.1-codex-max.
```
- 清晰说明当前模型 (`gpt-5-codex`) 和目标模型 (`gpt-5.1-codex-max`)
- 使用缩进（2个空格）保持视觉层次

### 3. 模型特性描述
```
  Codex-optimized flagship for deep and fast reasoning.
```
- 展示新模型的核心优势："Codex优化的旗舰模型，用于深度和快速推理"

### 4. 文档链接
```
  Learn more about gpt-5.1-codex-max at
  https://www.codex.com/models/gpt-5.1-codex-max
```
- 提供可点击的链接（渲染为青色下划线样式）
- 链接使用 `.cyan().underlined()` 样式

### 5. 操作提示
```
  Press enter to continue
```
- 由于 `can_opt_out: false`，用户只能选择继续
- 提示文字使用暗淡样式 (`.dim()`)

---

## 具体技术实现

### 核心数据结构

```rust
// 迁移结果枚举
pub(crate) enum ModelMigrationOutcome {
    Accepted,   // 用户接受升级
    Rejected,   // 用户拒绝升级
    Exit,       // 用户退出
}

// 迁移文案结构
pub(crate) struct ModelMigrationCopy {
    pub heading: Vec<Span<'static>>,      // 标题文本
    pub content: Vec<Line<'static>>,      // 内容行
    pub can_opt_out: bool,                // 是否允许退出
    pub markdown: Option<String>,         // 可选的Markdown内容
}
```

### 关键函数: `migration_copy_for_models`

```rust
pub(crate) fn migration_copy_for_models(
    current_model: &str,           // "gpt-5-codex"
    target_model: &str,            // "gpt-5.1-codex-max"
    model_link: Option<String>,    // Some("https://www.codex.com/models/gpt-5.1-codex-max")
    migration_copy: Option<String>,// None
    migration_markdown: Option<String>,// None
    target_display_name: String,   // "gpt-5.1-codex-max"
    target_description: Option<String>, // Some("Codex-optimized flagship...")
    can_opt_out: bool,             // false
) -> ModelMigrationCopy
```

### 渲染流程

1. **标题渲染** (行 84-87):
```rust
let heading_text = Span::from(format!(
    "Codex just got an upgrade. Introducing {target_display_name}."
)).bold();
```

2. **内容构建** (行 102-127):
   - 添加迁移建议文本
   - 添加模型描述和链接
   - 根据 `can_opt_out` 决定显示菜单或简单提示

3. **Widget渲染** (`render_ref` 方法, 行 252-270):
```rust
impl WidgetRef for &ModelMigrationScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);  // 清除背景
        let mut column = ColumnRenderable::new();
        // 渲染标题、内容、菜单（如果允许退出）
        column.render(area, buf);
    }
}
```

### 测试用例实现

```rust
#[test]
fn prompt_snapshot_gpt5_codex() {
    let backend = VT100Backend::new(60, 22);  // 60x22 终端
    let mut terminal = Terminal::with_options(backend).expect("terminal");
    terminal.set_viewport_area(Rect::new(0, 0, 60, 22));

    let screen = ModelMigrationScreen::new(
        FrameRequester::test_dummy(),
        migration_copy_for_models(
            "gpt-5-codex",
            "gpt-5.1-codex-max",
            Some("https://www.codex.com/models/gpt-5.1-codex-max".to_string()),
            None,
            None,
            "gpt-5.1-codex-max".to_string(),
            Some("Codex-optimized flagship for deep and fast reasoning.".to_string()),
            false,  // 不允许退出
        ),
    );
    // 渲染并捕获快照...
}
```

---

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/model_migration.rs` | 模型迁移提示的完整实现 |
| `codex-rs/tui/src/render/renderable.rs` | `ColumnRenderable` 等渲染辅助结构 |
| `codex-rs/tui/src/selection_list.rs` | 选项列表渲染（当 `can_opt_out: true`）|

### 关键代码行
- **行 26-31**: `ModelMigrationOutcome` 枚举定义
- **行 33-39**: `ModelMigrationCopy` 结构定义
- **行 60-135**: `migration_copy_for_models` 函数
- **行 137-169**: `run_model_migration_prompt` 异步运行函数
- **行 171-250**: `ModelMigrationScreen` 状态管理
- **行 252-270**: `WidgetRef` 渲染实现
- **行 484-508**: `prompt_snapshot_gpt5_codex` 测试

### 样式相关
- **行 15**: `ratatui::prelude::Stylize` 导入
- **行 113**: `model_link.cyan().underlined()` 链接样式
- **行 126**: `"Press enter to continue".dim()` 提示样式

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | TUI 渲染框架，提供 `Widget`, `WidgetRef`, `Buffer`, `Rect` 等 |
| `crossterm` | 终端事件处理（键盘输入） |
| `tokio_stream` | 异步事件流处理 |

### 内部模块依赖

```rust
use crate::markdown_render::render_markdown_text_with_width;  // Markdown渲染
use crate::render::Insets;                                     // 边距控制
use crate::render::renderable::{ColumnRenderable, Renderable}; // 渲染抽象
use crate::selection_list::selection_option_row;              // 选项列表
use crate::tui::{FrameRequester, Tui, TuiEvent};              // TUI核心
```

### 交互流程
```
用户启动 Codex CLI
    ↓
系统检测当前模型为 gpt-5-codex
    ↓
调用 migration_copy_for_models() 构建文案
    ↓
创建 ModelMigrationScreen
    ↓
进入备用屏幕 (AltScreenGuard)
    ↓
渲染提示界面
    ↓
等待用户输入 (Enter/Esc)
    ↓
返回 ModelMigrationOutcome
```

---

## 风险、边界与改进建议

### 潜在风险

1. **硬编码模型名称**
   - 风险：模型名称变更时需要更新代码
   - 位置：`migration_copy_for_models` 的调用点
   - 建议：考虑从配置或API动态获取

2. **链接可访问性**
   - 风险：`https://www.codex.com/models/...` 链接可能失效
   - 建议：添加链接有效性检查或降级显示

3. **终端宽度限制**
   - 风险：窄终端下文本换行可能影响可读性
   - 测试：当前测试使用 60 列宽度
   - 建议：添加更窄终端的响应式测试

### 边界情况

1. **can_opt_out = true 时的菜单**
   - 当允许退出时，界面会显示选项菜单
   - 当前快照 `can_opt_out: false`，不显示菜单

2. **Markdown 内容覆盖**
   - 如果提供 `migration_markdown`，会覆盖默认文案
   - 当前测试未使用此路径

3. **长URL处理**
   - 测试 `markdown_prompt_keeps_long_url_tail_visible_when_narrow` 验证长URL在窄终端下的显示

### 改进建议

1. **国际化支持**
   ```rust
   // 当前：硬编码英文
   "Codex just got an upgrade. Introducing {target_display_name}."
   
   // 建议：支持i18n
   t!("model_migration.upgrade_title", target = target_display_name)
   ```

2. **配置化模型描述**
   - 将模型描述移至配置文件或远程配置
   - 便于新模型发布时无需更新代码

3. **A/B 测试支持**
   - 支持不同的文案变体
   - 通过 `migration_copy` 参数实现

4. **无障碍支持**
   - 添加屏幕阅读器友好的输出
   - 考虑色盲用户的颜色选择

### 测试覆盖建议

1. **添加测试**: 极窄终端（<40列）的渲染
2. **添加测试**: 包含完整菜单的 `can_opt_out: true` 场景
3. **添加测试**: Markdown 内容覆盖路径
4. **添加测试**: 键盘导航（上下箭头、数字键选择）
