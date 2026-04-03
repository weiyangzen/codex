# Model Migration Prompt 研究文档

## 场景与职责

该组件负责在 Codex TUI 启动时，检测并提示用户升级到新版本的模型。当 OpenAI 发布新的 Codex 模型（如从 gpt-5.1-codex 升级到 gpt-5.3-codex）时，系统需要向用户展示升级提示，介绍新模型的优势并允许用户选择是否升级。

## 功能点目的

模型迁移提示系统的核心目的：

1. **模型升级引导**：引导用户从旧模型迁移到新模型
2. **新特性介绍**：向用户展示新模型的能力和改进
3. **用户选择权**：允许用户选择继续使用旧模型或升级
4. **平滑过渡**：避免强制升级导致用户体验中断
5. **配置持久化**：记录用户的选择，避免重复提示

## 具体技术实现

### 迁移提示数据结构

```rust
#[derive(Clone)]
pub(crate) struct ModelMigrationCopy {
    pub heading: Vec<Span<'static>>,      // 标题（如升级公告）
    pub content: Vec<Line<'static>>,      // 内容描述
    pub can_opt_out: bool,                // 是否允许选择不升级
    pub markdown: Option<String>,         // Markdown 格式内容（可选）
}

pub(crate) enum ModelMigrationOutcome {
    Accepted,     // 用户接受升级
    Rejected,     // 用户拒绝升级
    Exit,         // 用户退出程序
}
```

### 迁移提示生成逻辑

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
) -> ModelMigrationCopy
```

### 提示内容模板

**标准格式**：
```
**Codex just got an upgrade. Introducing gpt-5.3-codex.**

Codex is now powered by gpt-5.3-codex, our most capable agentic coding 
model yet. It's built for long-running, project-scale work, with 
mid-turn steering + frequent progress updates so you can collaborate 
while it runs (and it's faster too).

Learn more: https://openai.com/index/introducing-gpt-5-3-codex/

You can keep using gpt-5.1-codex if you prefer.
```

### 显示条件判断

```rust
fn should_show_model_migration_prompt(
    current_model: &str,
    target_model: &str,
    seen_migrations: &BTreeMap<String, String>,
    available_models: &[ModelPreset],
) -> bool {
    // 1. 目标模型与当前模型不同
    if target_model == current_model { return false; }
    
    // 2. 未看过此迁移提示
    if let Some(seen_target) = seen_migrations.get(current_model) {
        if seen_target == target_model { return false; }
    }
    
    // 3. 目标模型在 picker 中可见
    if !available_models.iter().any(|p| p.model == target_model && p.show_in_picker) {
        return false;
    }
    
    // 4. 当前模型有升级选项或目标模型是某个模型的升级目标
    // ...
    true
}
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/model_migration.rs` | 迁移提示核心逻辑（第 1-627 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/model_migration.rs` | `migration_copy_for_models` 函数（第 61-135 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/model_migration.rs` | `run_model_migration_prompt` 异步函数（第 137-169 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `handle_model_migration_prompt_if_needed`（第 593-696 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `should_show_model_migration_prompt`（第 466-504 行） |

### 调用流程
```
App::run() 启动
    ├── 获取可用模型列表
    ├── handle_model_migration_prompt_if_needed()
    │   ├── 检查当前模型是否有升级选项
    │   ├── should_show_model_migration_prompt() 判断是否需要显示
    │   ├── migration_copy_for_models() 生成提示内容
    │   └── run_model_migration_prompt() 显示交互式提示
    │       ├── ModelMigrationScreen 渲染
    │       └── 等待用户选择
    └── 根据结果更新配置
```

## 依赖与外部交互

### 依赖模块
- `codex_core::models_manager::ModelPreset` - 模型预设配置
- `codex_core::models_manager::ModelUpgrade` - 模型升级配置
- `codex_core::config::Config` - 用户配置
- `crate::markdown_render::render_markdown_text_with_width` - Markdown 渲染

### 模型升级配置
```rust
// codex_core::models_manager::model_presets
pub struct ModelUpgrade {
    pub id: String,                           // 目标模型 ID
    pub reasoning_effort_mapping: Option<HashMap<...>>, // 推理努力级别映射
    pub migration_config_key: String,         // 迁移配置键
    pub model_link: Option<String>,           // 模型介绍链接
    pub upgrade_copy: Option<String>,         // 升级文案
    pub migration_markdown: Option<String>,   // Markdown 格式迁移内容
}
```

### 配置持久化
```rust
// 迁移提示记录
pub struct ModelMigrationNotice {
    pub hide_gpt5_1_migration_prompt: Option<bool>,
    pub hide_gpt_5_1_codex_max_migration_prompt: Option<bool>,
    pub model_migrations: BTreeMap<String, String>, // from_model -> to_model
}
```

## 风险、边界与改进建议

### 边界情况

1. **离线模式**：无法获取最新模型列表时的降级处理
2. **配置冲突**：多个迁移提示同时满足条件时的优先级
3. **Markdown 渲染失败**：回退到纯文本显示

### 潜在风险

1. **提示疲劳**：频繁的迁移提示可能导致用户厌烦
2. **配置漂移**：用户手动修改配置后可能与提示状态不一致
3. **模型回滚**：新模型出现问题时需要支持回滚提示

### 改进建议

1. **智能提示频率控制**：
   ```rust
   // 建议添加提示冷却期
   struct MigrationPromptPolicy {
       max_shows_per_version: u32,
       cooldown_days: u32,
       respect_dnd_hours: (u32, u32), // 免打扰时段
   }
   ```

2. **A/B 测试支持**：
   ```rust
   // 建议支持不同文案的测试
   enum MigrationCopyVariant {
       Control,
       VariantA,
       VariantB,
   }
   ```

3. **迁移影响预览**：
   ```rust
   // 建议显示迁移前后的配置对比
   struct MigrationPreview {
       current_config: ModelConfig,
       target_config: ModelConfig,
       breaking_changes: Vec<String>,
       new_features: Vec<String>,
   }
   ```

4. **批量迁移支持**：
   ```rust
   // 建议支持多模型同时迁移
   struct BatchMigration {
       migrations: Vec<ModelMigration>,
       apply_all: bool,
   }
   ```

5. **迁移后反馈收集**：
   ```rust
   // 建议收集迁移后的用户反馈
   struct PostMigrationFeedback {
       satisfaction: u8,
       issues: Vec<String>,
       would_recommend: bool,
   }
   ```

### 相关测试
- `model_migration_prompt_shows_for_hidden_model` - 隐藏模型的迁移提示
- `prompt_snapshot` - 标准提示快照测试
- `prompt_snapshot_gpt5_family` - GPT-5 系列迁移测试
- `escape_key_accepts_prompt` - 键盘交互测试
- `selecting_use_existing_model_rejects_upgrade` - 拒绝升级测试
