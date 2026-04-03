# 研究文档：model_migration_prompt.snap

## 场景与职责

此快照测试验证模型迁移提示的 UI 显示效果。当有新模型可用时，向用户展示迁移选项，允许用户选择使用新模型或继续使用现有模型。

## 功能点目的

1. **模型升级通知**：告知用户有新模型可用
2. **选择提供**：允许用户选择升级或保持现状
3. **信息展示**：展示新模型的特点和优势

## 具体技术实现

### 快照输出分析

```

> Codex just got an upgrade. Introducing gpt-5.1-codex-max.

  Upgrade to gpt-5.2-codex for the latest and greatest
  agentic coding model.

  You can continue using gpt-5.1-codex-mini if you prefer.

  Choose how you'd like Codex to proceed.

› 1. Try new model
  2. Use existing model

  Use ↑/↓ to move, press enter to confirm
```

关键元素：
- 标题：升级通知
- 描述：新模型优势
- 选择菜单：两个选项
- 操作提示：键盘导航说明

### 数据结构

```rust
// codex-rs/tui/src/model_migration.rs
pub(crate) enum ModelMigrationOutcome {
    Accepted,
    Rejected,
    Exit,
}

pub(crate) struct ModelMigrationCopy {
    pub heading: Vec<Span<'static>>,
    pub content: Vec<Line<'static>>,
    pub can_opt_out: bool,
    pub markdown: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum MigrationMenuOption {
    TryNewModel,
    UseExistingModel,
}
```

## 关键代码路径与文件引用

1. **迁移提示实现**：
   - `codex-rs/tui/src/model_migration.rs`
   - `codex-rs/tui_app_server/src/model_migration.rs`

2. **迁移逻辑**：
   - `migration_copy_for_models` 函数
   - `run_model_migration_prompt` 函数

## 依赖与外部交互

### UI 依赖
- `ratatui::widgets::Clear` - 清除背景
- `ratatui::widgets::Paragraph` - 文本显示
- `crossterm::event::KeyCode` - 键盘事件

### 异步支持
- `tokio_stream::StreamExt` - 事件流处理

## 风险、边界与改进建议

### 潜在风险
1. **用户困惑**：用户可能不理解模型差异
2. **选择后悔**：用户选择后无法立即撤销

### 边界情况
1. 终端尺寸过小
2. 网络问题导致模型信息加载失败
3. 用户快速按键

### 改进建议
1. 添加模型对比表格
2. 支持临时切换，让用户试用新模型
3. 添加 "不再询问" 选项
4. 支持配置默认行为
