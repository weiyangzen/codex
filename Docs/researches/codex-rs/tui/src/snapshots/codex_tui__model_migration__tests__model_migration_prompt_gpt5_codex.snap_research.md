# GPT-5 Codex 模型迁移提示快照研究文档

## 场景与职责

该快照文件记录了 `codex-rs/tui` 项目中针对 **GPT-5 Codex 模型家族**的强制升级提示界面。当用户当前使用的是 `gpt-5-codex` 模型，而系统推荐使用 `gpt-5.1-codex-max` 时，显示此提示。与可选升级不同，此提示是**强制性的**，用户只能按回车键继续，不能选择保留旧模型。

**核心职责：**
- 通知用户从 `gpt-5-codex` 迁移到 `gpt-5.1-codex-max`
- 解释新模型的优势（"Codex-optimized flagship for deep and fast reasoning"）
- 提供模型详情页面的链接
- 强制用户接受升级（`can_opt_out = false`）

## 功能点目的

### 1. 强制升级通知
- **模型切换说明**：明确告知用户从哪个模型切换到哪个模型
- **升级原因**：解释新模型的定位和优势
- **学习资源**：提供模型详情页面的可点击链接

### 2. 简化交互流程
- **单一操作**：用户只需按回车键继续
- **无选择菜单**：不显示 "Try new model / Use existing model" 选项
- **清晰指引**：底部显示 "Press enter to continue"

### 3. 品牌一致性
- **标题格式**：保持与其他迁移提示一致的视觉风格
- **链接样式**：使用青色下划线显示 URL
- **描述文本**：简洁明了地传达模型优势

## 具体技术实现

### 内容生成

```rust
pub(crate) fn migration_copy_for_models(
    current_model: &str,        // "gpt-5-codex"
    target_model: &str,         // "gpt-5.1-codex-max"
    model_link: Option<String>, // Some("https://www.codex.com/models/gpt-5.1-codex-max")
    migration_copy: Option<String>, // None
    migration_markdown: Option<String>, // None
    target_display_name: String, // "gpt-5.1-codex-max"
    target_description: Option<String>, // Some("Codex-optimized flagship for deep and fast reasoning.")
    can_opt_out: bool,          // false（强制升级）
) -> ModelMigrationCopy
```

### 强制升级的内容结构

当 `can_opt_out = false` 时，内容生成逻辑：

```rust
if can_opt_out {
    content.push(Line::from(format!(
        "You can continue using {current_model} if you prefer."
    )));
} else {
    content.push(Line::from("Press enter to continue".dim()));
}
```

### 键盘事件处理差异

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
        // 强制升级：Esc 和 Enter 都接受
        self.accept();
    }
}
```

### 渲染差异

```rust
impl WidgetRef for &ModelMigrationScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);

        let mut column = ColumnRenderable::new();
        column.push("");
        
        if let Some(markdown) = self.copy.markdown.as_ref() {
            self.render_markdown_content(markdown, area.width, &mut column);
        } else {
            column.push(self.heading_line());
            column.push(Line::from(""));
            self.render_content(&mut column);
        }
        
        // 关键差异：只有 can_opt_out 为 true 时才渲染菜单
        if self.copy.can_opt_out {
            self.render_menu(&mut column);
        }

        column.render(area, buf);
    }
}
```

## 关键代码路径与文件引用

### 测试函数

```rust
#[test]
fn prompt_snapshot_gpt5_codex() {
    let backend = VT100Backend::new(60, 22);
    let mut terminal = Terminal::with_options(backend).expect("terminal");
    terminal.set_viewport_area(Rect::new(0, 0, 60, 22));

    let screen = ModelMigrationScreen::new(
        FrameRequester::test_dummy(),
        migration_copy_for_models(
            "gpt-5-codex",                                    // current_model
            "gpt-5.1-codex-max",                              // target_model
            Some("https://www.codex.com/models/gpt-5.1-codex-max".to_string()),  // model_link
            None,                                             // migration_copy
            None,                                             // migration_markdown
            "gpt-5.1-codex-max".to_string(),                  // target_display_name
            Some("Codex-optimized flagship for deep and fast reasoning.".to_string()),  // target_description
            false,                                            // can_opt_out（关键差异）
        ),
    );
    {
        let mut frame = terminal.get_frame();
        frame.render_widget_ref(&screen, frame.area());
    }
    terminal.flush().expect("flush");
    assert_snapshot!("model_migration_prompt_gpt5_codex", terminal.backend());
}
```

### 相关测试对比

| 测试函数 | can_opt_out | 模型家族 | 特点 |
|---------|-------------|---------|------|
| `prompt_snapshot` | `true` | gpt-5.1-codex | 可选升级，显示菜单 |
| `prompt_snapshot_gpt5_family` | `false` | gpt-5 → gpt-5.1 | 强制升级 |
| `prompt_snapshot_gpt5_codex` | `false` | gpt-5-codex → gpt-5.1-codex-max | 强制升级，Codex 旗舰 |
| `prompt_snapshot_gpt5_codex_mini` | `false` | gpt-5-codex-mini → gpt-5.1-codex-mini | 强制升级，轻量级 |

## 依赖与外部交互

### 与可选升级提示的共享组件

```
model_migration.rs
├── ModelMigrationScreen（共享）
├── migration_copy_for_models（共享）
├── AltScreenGuard（共享）
└── run_model_migration_prompt（共享）
```

### 差异点

| 组件 | 可选升级 (`can_opt_out=true`) | 强制升级 (`can_opt_out=false`) |
|-----|------------------------------|-------------------------------|
| 菜单显示 | 有 | 无 |
| 底部提示 | 方向键+回车确认 | "Press enter to continue" |
| Esc 键行为 | 接受升级 | 接受升级 |
| 选项数量 | 2 | 0 |

## 风险、边界与改进建议

### 已知风险

1. **用户体验摩擦**
   - 强制升级可能打断用户工作流程
   - 风险：用户可能对无法选择感到不满
   - 缓解：仅在必要情况下使用强制升级（如旧模型即将停用）

2. **链接可访问性**
   - URL 在终端中可能无法点击
   - 风险：用户无法访问模型详情页面
   - 缓解：确保描述文本充分解释升级原因

3. **终端兼容性**
   - `dim()` 样式在某些终端上可能显示不明显
   - 风险："Press enter to continue" 可能难以阅读

### 边界情况

1. **网络不可用**
   - 模型详情链接需要网络访问
   - 当前实现不检查网络状态

2. **终端尺寸**
   - 60x22 是测试尺寸
   - 在更小终端中，URL 可能被截断

3. **回车键映射**
   - 某些终端可能将 `Enter` 映射为不同键码
   - 当前仅处理标准 `KeyCode::Enter`

### 改进建议

1. **渐进式披露**
   - 添加 "Learn more" 选项，展开显示详细升级说明
   - 避免在初始界面堆砌过多信息

2. **撤销机制**
   - 允许用户在升级后的一段时间内回退到旧模型
   - 添加 "Don't ask again" 选项（但记录用户偏好）

3. **批处理模式**
   - 为非交互式环境添加 `--accept-model-upgrades` 标志
   - 避免在 CI/CD 环境中阻塞

4. **本地化**
   - 当前所有文本为英文
   - 建议根据系统语言环境显示本地化文本

5. **可访问性增强**
   - 为屏幕阅读器添加语音提示
   - 确保颜色不是唯一的信息传递方式
