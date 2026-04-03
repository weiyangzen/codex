# Model Migration Prompt for Hidden Model - Technical Research Document

## Snapshot File
`codex_tui_app_server__app__tests__model_migration_prompt_shows_for_hidden_model.snap`

## Snapshot Content
```
**Codex just got an upgrade. Introducing gpt-5.3-codex.**

Codex is now powered by gpt-5.3-codex, our most capable agentic coding model yet. It's built for long-running, project-scale work, with mid-turn steering + frequent progress updates so you can collaborate while it runs (and it's faster too).

Learn more: https://openai.com/index/introducing-gpt-5-3-codex/

You can keep using gpt-5.1-codex if you prefer.
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证当用户当前使用的模型被标记为 "hidden"（隐藏）时，模型迁移提示的显示效果。当新模型发布且旧模型被隐藏时，系统需要向用户展示迁移提示，说明升级的优势和选择。

### 1.2 业务职责
- **升级通知**: 告知用户有新模型可用
- **隐藏模型处理**: 当当前模型被隐藏时，提供继续使用或升级的选项
- **信息展示**: 展示新模型的特点和优势
- **用户选择**: 允许用户选择继续使用当前模型或升级

### 1.3 使用场景
1. 用户当前使用 gpt-5.1-codex（已被标记为隐藏）
2. 系统检测到新模型 gpt-5.3-codex 可用
3. 向用户展示迁移提示，说明升级优势
4. 用户可以选择继续使用 gpt-5.1-codex 或升级到 gpt-5.3-codex

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 元素 | 内容 | 目的 |
|------|------|------|
| 标题 | "Codex just got an upgrade" | 吸引用户注意 |
| 新模型介绍 | gpt-5.3-codex 特点 | 说明升级价值 |
| 功能亮点 | 长运行、项目级工作、mid-turn steering | 展示新功能 |
| 文档链接 | 详细介绍页面 | 提供更多信息 |
| 选择提示 | 可以继续使用旧模型 | 尊重用户选择 |

### 2.2 隐藏模型概念
隐藏模型是指：
- 不再向新用户推荐的模型
- 可能即将 deprecated 的模型
- 被新模型替代的模型

当用户使用隐藏模型时，系统会提示升级，但仍允许继续使用。

### 2.3 与强制升级的区别
| 场景 | 用户选择 | 提示内容 |
|------|---------|---------|
| 隐藏模型 | 可以选择继续使用 | 展示 "You can keep using..." |
| 强制升级 | 只能按回车继续 | 显示 "Press enter to continue" |

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 迁移提示数据结构
```rust
// model_migration.rs
pub(crate) struct ModelMigrationCopy {
    pub heading: Vec<Span<'static>>,
    pub content: Vec<Line<'static>>,
    pub can_opt_out: bool,  // 关键：是否允许选择不升级
    pub markdown: Option<String>,
}
```

### 3.2 隐藏模型检测
```rust
// model_migration.rs
fn should_show_migration_prompt(
    current_model: &str,
    available_models: &[ModelInfo],
) -> Option<ModelMigrationCopy> {
    let current = available_models.iter().find(|m| m.id == current_model)?;
    
    // 如果当前模型被隐藏，显示迁移提示
    if current.hidden {
        let target = find_recommended_model(available_models)?;
        Some(migration_copy_for_models(
            current_model,
            &target.id,
            target.model_link.clone(),
            target.migration_copy.clone(),
            target.migration_markdown.clone(),
            target.display_name.clone(),
            target.description.clone(),
            true,  // can_opt_out = true，允许选择不升级
        ))
    } else {
        None
    }
}
```

### 3.3 测试实现
```rust
// app.rs:7741-7780
async fn model_migration_prompt_shows_for_hidden_model() -> String {
    let mut app = make_test_app().await;
    
    // 设置当前模型为隐藏状态
    app.chat_widget.set_model("gpt-5.1-codex");
    app.mock_model_info("gpt-5.1-codex", ModelInfo {
        hidden: true,
        ..Default::default()
    });
    
    // 模拟新模型可用
    app.mock_model_info("gpt-5.3-codex", ModelInfo {
        hidden: false,
        display_name: "GPT-5.3 Codex".to_string(),
        description: Some("Our most capable agentic coding model".to_string()),
        ..Default::default()
    });
    
    // 生成迁移提示
    let copy = app.generate_model_migration_copy();
    let rendered = model_migration_copy_to_plain_text(&copy);
    
    // 验证提示内容
    assert!(rendered.contains("gpt-5.3-codex"));
    assert!(rendered.contains("You can keep using gpt-5.1-codex"));
    
    rendered
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/app.rs` | 迁移提示触发逻辑 |
| `codex-rs/tui_app_server/src/model_migration.rs` | 迁移提示生成和显示 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 模型信息管理 |

### 4.2 调用链
```
App 启动 / 模型切换
  └── check_model_migration()
        └── should_show_migration_prompt()
              ├── 检测当前模型是否 hidden
              ├── 查找推荐的新模型
              └── migration_copy_for_models()
                    └── 生成 ModelMigrationCopy
                          └── 显示迁移提示 UI
```

### 4.3 迁移提示渲染
```rust
// model_migration.rs:200-280
fn render_migration_prompt(&self, copy: &ModelMigrationCopy) -> Vec<Line> {
    let mut lines = vec![];
    
    // 渲染标题（粗体）
    lines.push(Line::from(copy.heading.clone()));
    lines.push(Line::from(""));
    
    // 渲染内容
    lines.extend(copy.content.clone());
    
    // 如果允许选择不升级，显示选项
    if copy.can_opt_out {
        lines.push(Line::from(""));
        lines.push(Line::from(vec![
            "You can keep using ".into(),
            self.current_model.clone().dim(),
            " if you prefer.".into(),
        ]));
        lines.push(Line::from(""));
        lines.push(Line::from("› 1. Try new model"));
        lines.push(Line::from("  2. Use existing model"));
    } else {
        lines.push(Line::from(""));
        lines.push(Line::from("Press enter to continue"));
    }
    
    lines
}
```

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 内部依赖
| 模块 | 用途 |
|------|------|
| `codex_protocol::ModelInfo` | 模型信息结构（含 hidden 字段）|
| `crate::model_migration::ModelMigrationCopy` | 迁移提示内容 |
| `ratatui::text::Line` | 文本行渲染 |

### 5.2 模型信息来源
- OpenAI API 的模型列表端点
- 本地缓存的模型配置
- 用户配置文件中的模型设置

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 已知风险
| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 频繁提示 | 用户每次启动都可能看到提示 | 添加 "不再询问" 选项 |
| 网络依赖 | 模型信息需要网络获取 | 使用缓存，失败时静默处理 |
| 信息过时 | 迁移文案可能过时 | 从服务器动态获取 |

### 6.2 边界情况
1. **无网络连接**: 使用本地缓存的模型信息
2. **所有模型都隐藏**: 选择最新模型作为默认
3. **用户已选择不升级**: 记住选择，不再提示
4. **配置文件禁用迁移**: 尊重用户设置

### 6.3 改进建议
1. **智能提示频率**
   ```rust
   // 添加冷却期，避免频繁提示
   const MIGRATION_PROMPT_COOLDOWN: Duration = Duration::from_days(7);
   ```

2. **迁移影响预览**
   - 显示新模型的性能对比
   - 成本差异估算
   - 功能差异列表

3. **A/B 测试支持**
   ```rust
   // 支持不同的迁移文案
   enum MigrationCopyVariant {
       A,  // 功能导向
       B,  // 性能导向
       C,  // 简洁版
   }
   ```

4. **批量迁移**
   - 支持项目级别的模型迁移
   - 记住每个项目的模型选择

### 6.4 相关测试
- `model_migration_prompt`: 通用迁移提示测试
- `model_migration_prompt_shows_for_hidden_model`: 隐藏模型场景（本测试）
- `model_migration_prompt_gpt5_codex`: 特定模型迁移测试

---

## 7. 相关文档链接

- [AGENTS.md](../../../../../../AGENTS.md) - 项目开发指南
- [Model Migration Prompt](../codex_tui_app_server__model_migration__tests__model_migration_prompt.snap_research.md) - 通用迁移提示文档
