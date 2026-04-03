# Research: codex_tui__app__tests__model_migration_prompt_shows_for_hidden_model.snap

## 场景与职责

本快照文件测试模型迁移提示（Model Migration Prompt）的纯文本版本输出。当 Codex 有新版本模型可用时，会提示用户升级。此快照验证了迁移提示的 Markdown 格式内容。

## 功能点目的

验证模型迁移提示的内容生成，包括：
- 升级标题和介绍
- 新模型特性说明
- 学习更多链接
- 用户选择权说明

## 具体技术实现

### 内容结构

```markdown
**Codex just got an upgrade. Introducing gpt-5.3-codex.**

Codex is now powered by gpt-5.3-codex, our most capable agentic coding model yet. 
It's built for long-running, project-scale work, with mid-turn steering + frequent 
progress updates so you can collaborate while it runs (and it's faster too).

Learn more: https://openai.com/index/introducing-gpt-5-3-codex/

You can keep using gpt-5.1-codex if you prefer.
```

### 关键函数

```rust
// model_migration.rs
pub(crate) fn migration_copy_for_models(
    current_model: &str,
    target_model: &str,
    model_link: Option<String>,
    migration_copy: Option<String>,
    migration_markdown: Option<String>,
    target_display_name: String,
    target_description: Option<String>,
    can_opt_out: bool,
) -> ModelMigrationCopy
```

### 数据结构

```rust
pub(crate) struct ModelMigrationCopy {
    pub heading: Vec<Span<'static>>,      // 标题（富文本）
    pub content: Vec<Line<'static>>,      // 内容（富文本）
    pub can_opt_out: bool,                // 是否允许选择不升级
    pub markdown: Option<String>,         // Markdown 格式内容
}
```

## 关键代码路径与文件引用

- **源文件**: `codex-rs/tui/src/model_migration.rs`
- **测试文件**: `codex-rs/tui/src/app.rs`
- **模型配置**: `codex-core/src/models_manager/model_presets.rs`

## 依赖与外部交互

- **Markdown 渲染**: `markdown_render` 模块处理 Markdown 内容
- **模型管理器**: 提供模型升级信息和描述
- **配置系统**: `HIDE_GPT_5_1_CODEX_MAX_MIGRATION_PROMPT_CONFIG` 等配置控制提示显示

## 风险、边界与改进建议

### 边界情况

1. **隐藏模型**: 测试名称中的 "hidden_model" 指某些模型默认不在选择器中显示
2. **可选升级**: `can_opt_out` 为 true 时显示 "You can keep using..."
3. **Markdown 回退**: 当 `migration_markdown` 为 None 时使用默认模板

### 风险点

1. **链接有效性**: 硬编码的 URL 需要保持有效
2. **内容更新**: 模型描述需要随产品更新同步更新
3. **本地化**: 当前内容为英文，不支持多语言

### 改进建议

1. 添加本地化支持（i18n）
2. 考虑从远程配置加载迁移提示内容
3. 添加 A/B 测试支持以优化转换率
4. 支持富媒体内容（如图片、视频链接）
