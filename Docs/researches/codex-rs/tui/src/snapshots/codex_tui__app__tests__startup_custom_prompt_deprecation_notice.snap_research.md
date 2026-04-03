# Custom Prompt Deprecation Notice 研究文档

## 场景与职责

该组件负责在 Codex TUI 启动时检测并提示用户关于自定义提示（Custom Prompts）的弃用信息。随着 Codex 转向基于 Skill 的扩展机制，传统的自定义提示功能即将被移除，系统需要在启动时检测用户是否使用了自定义提示，并引导他们迁移到新的 Skill 系统。

## 功能点目的

自定义提示弃用通知系统的核心目的：

1. **功能迁移引导**：引导用户从旧版自定义提示迁移到新版 Skill 系统
2. **提前预警**：在功能正式移除前给用户充分的准备时间
3. **迁移路径指导**：明确告知用户使用 `$skill-creator` Skill 进行转换
4. **兼容性维护**：在过渡期内继续支持自定义提示，同时提供迁移建议

## 具体技术实现

### 弃用检测逻辑

```rust
async fn emit_custom_prompt_deprecation_notice(
    app_event_tx: &AppEventSender,
    codex_home: &Path,
) {
    let prompts_dir = codex_home.join("prompts");
    // 扫描 $CODEX_HOME/prompts 目录中的自定义提示
    let prompt_count = codex_core::custom_prompts::discover_prompts_in(&prompts_dir)
        .await
        .len();
    
    if prompt_count == 0 {
        return; // 无自定义提示，无需通知
    }

    let prompt_label = if prompt_count == 1 { "prompt" } else { "prompts" };
    let details = format!(
        "Detected {prompt_count} custom {prompt_label} in `$CODEX_HOME/prompts`. \
         Use the `$skill-creator` skill to convert each custom prompt into a skill."
    );

    app_event_tx.send(AppEvent::InsertHistoryCell(Box::new(
        history_cell::new_deprecation_notice(
            "Custom prompts are deprecated and will soon be removed.".to_string(),
            Some(details),
        ),
    )));
}
```

### 通知内容格式

```
⚠ Custom prompts are deprecated and will soon be removed.
Detected 1 custom prompt in `$CODEX_HOME/prompts`. Use the `$skill-creator` skill to convert 
each custom prompt into a skill.
```

### 数据结构

```rust
// 弃用通知单元格
pub fn new_deprecation_notice(
    message: String,
    details: Option<String>,
) -> Box<dyn HistoryCell> {
    Box::new(DeprecationNoticeHistoryCell {
        message,
        details,
        timestamp: Instant::now(),
    })
}

struct DeprecationNoticeHistoryCell {
    message: String,
    details: Option<String>,
    timestamp: Instant,
}
```

### 检测流程

```
App::run() 启动
    └── emit_custom_prompt_deprecation_notice(app_event_tx, &config.codex_home)
        ├── 构建 prompts_dir 路径: $CODEX_HOME/prompts
        ├── discover_prompts_in(&prompts_dir) 扫描自定义提示
        │   └── 递归查找 .md 和 .txt 文件
        ├── 如果 prompt_count > 0:
        │   └── 发送弃用通知到历史记录
        └── 如果 prompt_count == 0: 静默返回
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `emit_custom_prompt_deprecation_notice` 函数（第 288-312 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `App::run()` 中调用弃用检测（第 2003 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/history_cell.rs` | `new_deprecation_notice` 函数实现 |
| `/home/sansha/Github/codex/codex-rs/core/src/custom_prompts.rs` | `discover_prompts_in` 函数 |

### 相关配置
```rust
// $CODEX_HOME/prompts/ 目录结构
prompts/
├── my-custom-prompt.md
├── another-prompt.txt
└── nested/
    └── nested-prompt.md
```

### 调用链
```
App::run()
    ├── emit_custom_prompt_deprecation_notice(&app_event_tx, &config.codex_home)
    │   ├── prompts_dir = codex_home.join("prompts")
    │   ├── codex_core::custom_prompts::discover_prompts_in(&prompts_dir).await
    │   └── if prompt_count > 0:
    │       └── AppEvent::InsertHistoryCell(
    │               history_cell::new_deprecation_notice(message, Some(details))
    │           )
    └── 继续初始化...
```

## 依赖与外部交互

### 依赖模块
- `codex_core::custom_prompts::discover_prompts_in` - 自定义提示发现
- `crate::history_cell::new_deprecation_notice` - 弃用通知创建
- `crate::app_event::AppEvent::InsertHistoryCell` - 历史记录插入事件

### 自定义提示扫描
```rust
// codex_core::custom_prompts
pub async fn discover_prompts_in(dir: &Path) -> Vec<CustomPrompt> {
    let mut prompts = Vec::new();
    if !dir.exists() {
        return prompts;
    }
    
    let mut entries = tokio::fs::read_dir(dir).await?;
    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        if path.extension().map_or(false, |ext| {
            ext == "md" || ext == "txt"
        }) {
            prompts.push(CustomPrompt::from_path(&path).await?);
        }
    }
    prompts
}
```

### Skill 系统关联
- `$skill-creator` Skill：用于将自定义提示转换为 Skill
- Skill 存储位置：`$CODEX_HOME/skills/`
- Skill 格式：包含 `SKILL.md` 的目录结构

## 风险、边界与改进建议

### 边界情况

1. **空 prompts 目录**：目录存在但无有效提示文件
2. **权限问题**：无法读取 prompts 目录时的错误处理
3. **大量自定义提示**：用户有数十个自定义提示时的通知显示
4. **重复通知**：每次启动都显示相同通知可能造成干扰

### 潜在风险

1. **用户困惑**：不清楚如何将自定义提示转换为 Skill
2. **功能缺失**：某些自定义提示功能在 Skill 系统中可能没有对应实现
3. **迁移成本**：用户需要学习新的 Skill 创建流程
4. **向后兼容性**：自定义提示功能移除后旧工作流中断

### 改进建议

1. **一键迁移工具**：
   ```rust
   // 建议提供自动迁移命令
   pub async fn migrate_custom_prompts_to_skills(codex_home: &Path) -> MigrationResult {
       let prompts = discover_prompts_in(&codex_home.join("prompts")).await;
       for prompt in prompts {
           let skill = Skill::from_custom_prompt(&prompt)?;
           skill.save_to(&codex_home.join("skills")).await?;
       }
       Ok(MigrationResult { migrated: prompts.len() })
   }
   ```

2. **迁移向导**：
   ```rust
   // 建议提供交互式迁移向导
   pub async fn run_migration_wizard(tui: &mut Tui, codex_home: &Path) {
       let prompts = discover_custom_prompts(codex_home).await;
       for prompt in prompts {
           let converted = preview_skill_conversion(&prompt);
           if confirm_conversion(tui, &converted).await {
               convert_to_skill(&prompt).await;
           }
       }
   }
   ```

3. **智能通知抑制**：
   ```rust
   // 建议记录通知历史，避免重复打扰
   struct DeprecationNoticeHistory {
       first_shown: DateTime,
       last_shown: DateTime,
       show_count: u32,
       dismissed: bool,
   }
   
   // 策略：首次显示后，每周最多显示一次
   fn should_show_notice(history: &DeprecationNoticeHistory) -> bool {
       !history.dismissed && 
       history.last_shown.elapsed() > Duration::days(7)
   }
   ```

4. **详细迁移文档**：
   - 在通知中提供指向详细文档的链接
   - 包含常见自定义提示到 Skill 的转换示例
   - 提供视频教程链接

5. **兼容性检查**：
   ```rust
   // 建议检查自定义提示的兼容性
   fn check_prompt_compatibility(prompt: &CustomPrompt) -> CompatibilityReport {
       CompatibilityReport {
           fully_supported: bool,
           partial_features: Vec<String>,
           unsupported_features: Vec<String>,
           suggested_workarounds: Vec<String>,
       }
   }
   ```

### 相关测试
- `startup_custom_prompt_deprecation_notice` - 启动时弃用通知测试
- 测试覆盖：0 个、1 个、多个自定义提示的场景
- 测试覆盖：prompts 目录不存在、为空、有权限问题的场景
